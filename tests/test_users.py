import io
from types import SimpleNamespace

import pytest

from app import redis_store
from app.users import InvalidAvatarError, read_uploaded_file_bytes

from tests.helpers import (
    auth_headers,
    create_avatar_bytes,
    create_group_room,
    get_rooms,
    join_user,
    random_username,
    signin,
    signup,
    update_profile,
)


def test_read_uploaded_file_bytes_accepts_file_field_like_uploads():
    uploaded = SimpleNamespace(file=io.BytesIO(b'avatar-bytes'))

    assert read_uploaded_file_bytes(uploaded) == b'avatar-bytes'


def test_read_uploaded_file_bytes_normalizes_file_like_bytearrays():
    uploaded = SimpleNamespace(file=SimpleNamespace(read=lambda: bytearray(b'avatar-bytes')))

    assert read_uploaded_file_bytes(uploaded) == b'avatar-bytes'


def test_read_uploaded_file_bytes_accepts_bytearray_uploads():
    assert read_uploaded_file_bytes(bytearray(b'avatar-bytes')) == b'avatar-bytes'


def test_read_uploaded_file_bytes_rejects_unknown_upload_shapes():
    with pytest.raises(InvalidAvatarError, match='Invalid file upload'):
        read_uploaded_file_bytes(object())


async def test_guest_signup_password_upgrade_and_signin(cli):
    response = await cli.get('/api/users/me')
    assert response.status == 200
    body = await response.json()
    assert body['authenticated'] is False

    created = await signup(cli)
    assert created['user']['authenticated'] is True
    assert created['user']['has_password'] is False
    assert created['user']['picture'].startswith('/api/users/avatar/')

    response = await update_profile(
        cli,
        created['jwt'],
        password='correct horse battery',
        status='hello',
    )
    assert response.status == 200
    me = await response.json()
    assert me['has_password'] is True
    assert me['status'] == 'hello'
    assert 'phone' not in me

    await cli.post('/api/users/signout', headers=auth_headers(created['jwt']))

    response = await signin(cli, created['username'], 'correct horse battery')
    assert response.status == 200
    signed_in = await response.json()
    assert signed_in['username'] == created['username']
    assert signed_in['has_password'] is True


async def test_status_is_normalized_and_limited(cli):
    created = await signup(cli)

    response = await update_profile(
        cli,
        created['jwt'],
        status='   hello   from\nnearby   ',
    )
    assert response.status == 200
    me = await response.json()
    assert me['status'] == 'hello from nearby'
    assert 'phone' not in me

    response = await update_profile(
        cli,
        created['jwt'],
        status='x' * 81,
    )
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 9


async def test_guest_signout_deletes_account(cli):
    created = await signup(cli)

    response = await cli.post(
        '/api/users/signout',
        headers=auth_headers(created['jwt']),
    )
    assert response.status == 204

    response = await signin(cli, created['username'], 'does-not-matter')
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 5


async def test_avatar_upload_and_fetch(cli):
    created = await signup(cli)
    avatar = create_avatar_bytes()

    response = await cli.post(
        '/api/users/upload-profile-picture',
        data={'file': io.BytesIO(avatar)},
        headers=auth_headers(created['jwt']),
    )
    assert response.status == 200
    body = await response.json()
    assert body['picture'].startswith('/api/users/avatar/')

    avatar_response = await cli.get(body['picture'])
    assert avatar_response.status == 200
    assert avatar_response.content_type == 'image/png'
    payload = await avatar_response.read()
    assert payload.startswith(b'\x89PNG')


async def test_avatar_upload_accepts_multipart_without_filename(cli):
    created = await signup(cli)
    avatar = create_avatar_bytes()
    boundary = 'avatar-upload-boundary'
    body = b''.join([
        f'--{boundary}\r\n'.encode(),
        b'Content-Disposition: form-data; name="file"\r\n',
        b'Content-Type: application/octet-stream\r\n\r\n',
        avatar,
        b'\r\n',
        f'--{boundary}--\r\n'.encode(),
    ])

    response = await cli.post(
        '/api/users/upload-profile-picture',
        data=body,
        headers={
            **auth_headers(created['jwt']),
            'Content-Type': f'multipart/form-data; boundary={boundary}',
        },
    )

    assert response.status == 200
    body = await response.json()
    assert body['picture'].startswith('/api/users/avatar/')


async def test_invalid_avatar_upload_returns_usage_error(cli):
    created = await signup(cli)

    response = await cli.post(
        '/api/users/upload-profile-picture',
        data={'file': io.BytesIO(b'not-an-image')},
        headers=auth_headers(created['jwt']),
    )
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 8


async def test_invalid_json_request_returns_usage_error(cli):
    response = await cli.post(
        '/api/users/signup',
        data='{not valid json',
        headers={'Content-Type': 'application/json'},
    )
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 11


async def test_invalid_json_encoding_returns_usage_error(cli):
    response = await cli.post(
        '/api/users/signup',
        data=b'\xff',
        headers={'Content-Type': 'application/json; charset=utf-8'},
    )
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 11


async def test_feedback_requires_a_message(cli):
    created = await signup(cli)

    response = await cli.post(
        '/api/users/feedback',
        json={'message': '   '},
        headers=auth_headers(created['jwt']),
    )

    assert response.status == 400
    body = await response.json()
    assert body['code'] == 12


async def test_delete_account_removes_permanent_user(cli):
    username = random_username()
    created = await signup(cli, username=username)
    response = await update_profile(cli, created['jwt'], password='permanent123')
    assert response.status == 200

    response = await cli.delete('/api/users/me', headers=auth_headers(created['jwt']))
    assert response.status == 204

    response = await signin(cli, username, 'permanent123')
    assert response.status == 400


async def test_cleanup_inactive_users_deletes_stale_accounts_and_their_rooms(cli, monkeypatch):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    original_time = redis_store.time.time
    base_time = original_time()
    stale_now = base_time + redis_store.INACTIVE_USER_TTL_SECONDS + 1
    monkeypatch.setattr(redis_store.time, 'time', lambda: stale_now)

    await get_rooms(cli, users[0]['jwt'])

    result = await cli.app['store'].cleanup_inactive_data(current_ts=stale_now)

    assert result['deleted_user_ids'] == [users[1]['user']['id']]
    assert room['id'] in result['deleted_room_ids']
    assert await cli.app['store']._load_user_hash(users[1]['user']['id']) is None

    remaining_rooms = await get_rooms(cli, users[0]['jwt'])
    assert remaining_rooms == []


async def test_cleanup_prunes_historical_group_rooms_with_fewer_than_two_members(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await create_group_room(
        cli,
        users[0]['jwt'],
        '',
        [users[1]['user']['id']],
    )

    await cli.app['redis'].srem(cli.app['store']._room_members_key(room['id']), users[1]['user']['id'])
    await cli.app['redis'].zrem(cli.app['store']._user_rooms_key(users[1]['user']['id']), room['id'])

    result = await cli.app['store'].cleanup_inactive_data()

    assert result['deleted_user_ids'] == []
    assert result['deleted_room_ids'] == [room['id']]
    assert await cli.app['store'].get_room(room['id']) is None
    remaining_rooms = await get_rooms(cli, users[0]['jwt'])
    assert remaining_rooms == []


async def test_push_subscription_routes_store_and_remove_browser_subscription(
    cli,
    monkeypatch,
):
    monkeypatch.setattr('config.PUSH_VAPID_PUBLIC_KEY', 'public-key')
    monkeypatch.setattr('config.PUSH_VAPID_PRIVATE_KEY', 'private-key')
    monkeypatch.setattr('config.PUSH_VAPID_SUBJECT', 'mailto:test@example.com')

    created = await signup(cli)
    response = await update_profile(cli, created['jwt'], password='permanent123')
    assert response.status == 200

    config_response = await cli.get(
        '/api/users/push-config',
        headers=auth_headers(created['jwt']),
    )
    assert config_response.status == 200
    assert await config_response.json() == {
        'enabled': True,
        'vapid_public_key': 'public-key',
    }

    subscription = {
        'endpoint': 'https://push.example.test/sub/1',
        'keys': {
            'p256dh': 'p256dh-value',
            'auth': 'auth-value',
        },
        'expirationTime': None,
    }
    response = await cli.post(
        '/api/users/push-subscriptions',
        json={'subscription': subscription},
        headers=auth_headers(created['jwt']),
    )
    assert response.status == 204

    subscriptions = await cli.app['store'].get_push_subscriptions_for_users(
        [created['user']['id']],
    )
    assert len(subscriptions) == 1
    assert subscriptions[0]['user_id'] == created['user']['id']
    assert subscriptions[0]['endpoint'] == subscription['endpoint']
    assert subscriptions[0]['keys'] == subscription['keys']
    assert subscriptions[0]['expirationTime'] is None
    assert subscriptions[0]['user_agent']

    signout = await cli.post(
        '/api/users/signout',
        json={'push_endpoint': subscription['endpoint']},
        headers=auth_headers(created['jwt']),
    )
    assert signout.status == 204
    assert await cli.app['store'].get_push_subscriptions_for_users(
        [created['user']['id']],
    ) == []


async def test_invalid_push_subscription_returns_usage_error(cli, monkeypatch):
    monkeypatch.setattr('config.PUSH_VAPID_PUBLIC_KEY', 'public-key')
    monkeypatch.setattr('config.PUSH_VAPID_PRIVATE_KEY', 'private-key')
    monkeypatch.setattr('config.PUSH_VAPID_SUBJECT', 'mailto:test@example.com')

    created = await signup(cli)
    response = await cli.post(
        '/api/users/push-subscriptions',
        json={'subscription': {'endpoint': '', 'keys': {}}},
        headers=auth_headers(created['jwt']),
    )
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 10


async def test_non_object_push_subscription_returns_usage_error(cli, monkeypatch):
    monkeypatch.setattr('config.PUSH_VAPID_PUBLIC_KEY', 'public-key')
    monkeypatch.setattr('config.PUSH_VAPID_PRIVATE_KEY', 'private-key')
    monkeypatch.setattr('config.PUSH_VAPID_SUBJECT', 'mailto:test@example.com')

    created = await signup(cli)
    response = await cli.post(
        '/api/users/push-subscriptions',
        json={'subscription': 'invalid'},
        headers=auth_headers(created['jwt']),
    )
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 10
