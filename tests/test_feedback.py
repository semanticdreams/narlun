import json

from app.app import create_app
from tests.helpers import auth_headers, signup


async def test_feedback_is_logged_to_dedicated_jsonl_file(
    aiohttp_client,
    redis_url,
    monkeypatch,
    tmp_path,
):
    log_path = tmp_path / 'feedback.jsonl'
    monkeypatch.setattr('config.FEEDBACK_LOG_PATH', str(log_path))

    app = await create_app(redis_url=redis_url, enable_cors=False)
    await app['redis'].flushdb()
    client = await aiohttp_client(app)
    created = await signup(client)

    response = await client.post(
        '/api/users/feedback',
        json={
            'app': 'narlun-ui',
            'release': 'abc123',
            'source': 'profile',
            'route': '/profile',
            'message': 'Nearby users did not appear after granting location.',
            'details': {'surface': 'profile'},
            'screen': {'w': 1440, 'h': 900},
        },
        headers={
            **auth_headers(created['jwt']),
            'X-Narlun-Client-Session-ID': 'session-1',
            'User-Agent': 'Mozilla/5.0',
        },
    )

    assert response.status == 204
    assert response.headers['X-Request-ID']
    logged = [json.loads(line) for line in log_path.read_text().splitlines()]
    assert len(logged) == 1
    assert logged[0]['request_id'] == response.headers['X-Request-ID']
    assert logged[0]['user_id'] == created['user']['id']
    assert logged[0]['username'] == created['username']
    assert logged[0]['client_session_id'] == 'session-1'
    assert logged[0]['route'] == '/profile'
    assert logged[0]['source'] == 'profile'
    assert logged[0]['message'] == 'Nearby users did not appear after granting location.'
    assert logged[0]['details'] == {'surface': 'profile'}
    assert logged[0]['screen'] == {'w': 1440, 'h': 900}
    assert logged[0]['remote_ip'] == '127.0.0.1'

