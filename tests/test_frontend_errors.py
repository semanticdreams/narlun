import json

from app.app import create_app
from app.frontend_errors import (
    MAX_EVENTS_PER_FINGERPRINT_PER_MINUTE,
    ClientErrorRateLimiter,
)


async def test_client_errors_are_logged_to_dedicated_jsonl_file(
    aiohttp_client,
    redis_url,
    monkeypatch,
    tmp_path,
):
    log_path = tmp_path / 'frontend-errors.jsonl'
    monkeypatch.setattr('config.FRONTEND_ERROR_LOG_PATH', str(log_path))

    app = await create_app(redis_url=redis_url, enable_cors=False)
    await app['redis'].flushdb()
    client = await aiohttp_client(app)

    response = await client.post(
        '/api/client-errors',
        json={
            'ts': '2026-04-04T12:34:56.789Z',
            'app': 'narlun-ui',
            'env': 'PROD',
            'release': 'abc123',
            'route': '/rooms?open_room=12',
            'user_id': 7,
            'client_session_id': 'session-1',
            'fingerprint': 'fp-1',
            'kind': 'flutter_uncaught',
            'message': 'Null check operator used on a null value',
            'stack': 'frame-1\nframe-2',
            'user_agent': 'Mozilla/5.0',
            'screen': {'w': 1440, 'h': 900},
        },
    )

    assert response.status == 204
    logged = [json.loads(line) for line in log_path.read_text().splitlines()]
    assert len(logged) == 1
    assert logged[0]['message'] == 'Null check operator used on a null value'
    assert logged[0]['route'] == '/rooms?open_room=12'
    assert logged[0]['user_id'] == 7
    assert logged[0]['client_session_id'] == 'session-1'
    assert logged[0]['screen'] == {'w': 1440, 'h': 900}
    assert logged[0]['remote_ip'] == '127.0.0.1'


async def test_client_errors_are_rate_limited_per_fingerprint(
    aiohttp_client,
    redis_url,
    monkeypatch,
    tmp_path,
):
    log_path = tmp_path / 'frontend-errors.jsonl'
    monkeypatch.setattr('config.FRONTEND_ERROR_LOG_PATH', str(log_path))

    app = await create_app(redis_url=redis_url, enable_cors=False)
    await app['redis'].flushdb()
    client = await aiohttp_client(app)

    payload = {
        'fingerprint': 'fp-flood',
        'kind': 'flutter_uncaught',
        'message': 'Repeated error',
        'stack': 'frame-1\nframe-2',
        'client_session_id': 'session-1',
    }

    for _ in range(MAX_EVENTS_PER_FINGERPRINT_PER_MINUTE + 3):
        response = await client.post('/api/client-errors', json=payload)
        assert response.status == 204

    logged = [json.loads(line) for line in log_path.read_text().splitlines()]
    assert len(logged) == MAX_EVENTS_PER_FINGERPRINT_PER_MINUTE


def test_client_rate_limit_rejection_does_not_consume_fingerprint_quota():
    limiter = ClientErrorRateLimiter(per_client_limit=1, per_fingerprint_limit=2)

    assert limiter.allow(client_key='client-a', fingerprint='fp') is True
    assert limiter.allow(client_key='client-a', fingerprint='fp') is False
    assert limiter.allow(client_key='client-b', fingerprint='fp') is True
