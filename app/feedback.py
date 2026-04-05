import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from app.observability import client_ip, request_log_context


MAX_FEEDBACK_MESSAGE_CHARS = 2000


class FeedbackLogWriter:
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


def create_feedback_tools(path):
    return {
        'writer': FeedbackLogWriter(path),
    }


def build_feedback_event(
    req,
    *,
    message,
    source=None,
    route=None,
    details=None,
    app=None,
    env=None,
    release=None,
    user_agent=None,
    screen=None,
):
    context = request_log_context(req)
    event = {
        'received_at': datetime.now(timezone.utc).isoformat(),
        'request_id': context.get('request_id'),
        'path': req.path_qs,
        'app': _string_value(app, limit=32) or 'narlun-ui',
        'env': _string_value(env, limit=32),
        'release': _string_value(release, limit=128),
        'user_id': req.user.get('id'),
        'username': _string_value(req.user.get('username'), limit=64),
        'client_session_id': context.get('client_session_id'),
        'route': _string_value(route, limit=512),
        'source': _string_value(source, limit=64) or 'in-app',
        'message': _string_value(message, limit=MAX_FEEDBACK_MESSAGE_CHARS),
        'details': _details_field(details),
        'user_agent': _string_value(user_agent, limit=512)
        or _string_value(req.headers.get('User-Agent'), limit=512),
        'screen': _screen_field(screen),
        'remote_ip': client_ip(req),
    }
    return {key: value for key, value in event.items() if value is not None}


def _string_value(value, *, limit):
    if not isinstance(value, str):
        return None
    stripped = value.strip()
    if not stripped:
        return None
    return stripped[:limit]


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


def _details_field(value):
    if not isinstance(value, dict):
        return None
    serialized = json.dumps(value, separators=(',', ':'), ensure_ascii=True)
    if len(serialized) > 4096:
        return {'truncated': True, 'preview': serialized[:4096]}
    return value
