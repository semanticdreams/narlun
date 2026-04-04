import asyncio
import json
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

from aiohttp import web


MAX_CLIENT_ERROR_BYTES = 16 * 1024
MAX_EVENTS_PER_CLIENT_PER_MINUTE = 20
MAX_EVENTS_PER_FINGERPRINT_PER_MINUTE = 5


class FrontendErrorLogWriter:
    def __init__(self, path):
        self.path = Path(path)
        self._lock = asyncio.Lock()

    async def write(self, event):
        line = json.dumps(event, separators=(',', ':'), ensure_ascii=True)
        async with self._lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with self.path.open('a', encoding='utf-8') as handle:
                handle.write(line)
                handle.write('\n')


class ClientErrorRateLimiter:
    def __init__(
        self,
        *,
        per_client_limit=MAX_EVENTS_PER_CLIENT_PER_MINUTE,
        per_fingerprint_limit=MAX_EVENTS_PER_FINGERPRINT_PER_MINUTE,
        window_seconds=60,
    ):
        self.per_client_limit = per_client_limit
        self.per_fingerprint_limit = per_fingerprint_limit
        self.window_seconds = window_seconds
        self._events_by_client = {}
        self._events_by_fingerprint = {}

    def allow(self, *, client_key, fingerprint):
        now = time.monotonic()
        client_bucket = self._get_bucket(self._events_by_client, client_key, now)
        fingerprint_bucket = self._get_bucket(
            self._events_by_fingerprint,
            fingerprint,
            now,
        )
        if len(client_bucket) >= self.per_client_limit:
            return False
        if len(fingerprint_bucket) >= self.per_fingerprint_limit:
            return False
        client_bucket.append(now)
        fingerprint_bucket.append(now)
        return True

    def _get_bucket(self, buckets, key, now):
        bucket = buckets.setdefault(key, deque())
        cutoff = now - self.window_seconds
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if bucket:
            return bucket
        buckets.pop(key, None)
        bucket = deque()
        buckets[key] = bucket
        return bucket


def create_frontend_error_tools(path):
    return {
        'writer': FrontendErrorLogWriter(path),
        'rate_limiter': ClientErrorRateLimiter(),
    }


async def frontend_error_handler(req):
    if req.content_length and req.content_length > MAX_CLIENT_ERROR_BYTES:
        return web.Response(status=204)

    payload = req.data if isinstance(req.data, dict) else None
    if payload is None:
        return web.Response(status=204)

    event = _build_event(req, payload)
    if event is None:
        return web.Response(status=204)

    client_key = f'{event["remote_ip"]}:{event.get("client_session_id", "-")}'
    rate_limiter = req.app['frontend_error_rate_limiter']
    if not rate_limiter.allow(
        client_key=client_key,
        fingerprint=event['fingerprint'],
    ):
        return web.Response(status=204)

    await req.app['frontend_error_log_writer'].write(event)
    return web.Response(status=204)


def _build_event(req, payload):
    message = _string_field(payload, 'message', limit=1000)
    stack = _string_field(payload, 'stack', limit=8000)
    fingerprint = _string_field(payload, 'fingerprint', limit=128)
    kind = _string_field(payload, 'kind', limit=64)

    if not message or not stack or not fingerprint or not kind:
        return None

    server_user_id = req.user.get('id') if req.user.get('authenticated') else None
    event = {
        'received_at': datetime.now(timezone.utc).isoformat(),
        'ts': _string_field(payload, 'ts', limit=64),
        'app': _string_field(payload, 'app', limit=32) or 'narlun-ui',
        'env': _string_field(payload, 'env', limit=32),
        'release': _string_field(payload, 'release', limit=128),
        'route': _string_field(payload, 'route', limit=512),
        'user_id': server_user_id if server_user_id is not None else _int_field(payload, 'user_id'),
        'client_session_id': _string_field(payload, 'client_session_id', limit=128),
        'fingerprint': fingerprint,
        'kind': kind,
        'message': message,
        'stack': stack,
        'user_agent': _string_field(payload, 'user_agent', limit=512)
        or _string_value(req.headers.get('User-Agent'), limit=512),
        'screen': _screen_field(payload.get('screen')),
        'remote_ip': _client_ip(req),
    }
    return {key: value for key, value in event.items() if value is not None}


def _client_ip(req):
    forwarded = req.headers.get('X-Forwarded-For', '')
    if forwarded:
        first = forwarded.split(',', 1)[0].strip()
        if first:
            return first
    return req.remote or '-'


def _string_field(payload, key, *, limit):
    return _string_value(payload.get(key), limit=limit)


def _string_value(value, *, limit):
    if not isinstance(value, str):
        return None
    stripped = value.strip()
    if not stripped:
        return None
    return stripped[:limit]


def _int_field(payload, key):
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _screen_field(value):
    if not isinstance(value, dict):
        return None

    width = value.get('w')
    height = value.get('h')
    if isinstance(width, bool) or not isinstance(width, int):
        width = None
    if isinstance(height, bool) or not isinstance(height, int):
        height = None
    if width is None and height is None:
        return None
    return {'w': width, 'h': height}
