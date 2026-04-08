import asyncio
import json

import async_timeout
import aiohttp
from app.websocket import active_sockets

from tests.helpers import (
    approve_room_request,
    HAMBURG,
    MADRID,
    auth_headers,
    checkin,
    create_group_room,
    create_avatar_bytes,
    get_messages,
    get_rooms,
    join_user,
    mark_room_read,
    reject_room_request,
    request_room_join,
    send_message,
    signup,
    update_profile,
    upload_avatar,
)


def websocket_cookie_headers(jwt):
    return {'Cookie': f'jwt={jwt}'}


async def test_room_subscription_and_signout_disconnect(cli):
    users = [await signup(cli) for _ in range(2)]
    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], MADRID)
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({'type': 'subscribe-room', 'data': {'room_id': room['id']}}))
        subscribed = await ws.receive()
        payload = json.loads(subscribed.data)
        assert payload['type'] == 'subscribed-room'
        await send_message(cli, users[0]['jwt'], room['id'], 'hey')

        async with async_timeout.timeout(2):
            message = await ws.receive()
        payload = json.loads(message.data)
        assert payload['type'] == 'new-messages'
        assert payload['data']['messages'][0]['body'] == 'hey'

        await cli.post('/api/users/signout', headers=auth_headers(users[0]['jwt']))
        seen_signout = False
        async with async_timeout.timeout(2):
            while not seen_signout:
                payload = await ws.receive_json()
                if payload == {
                    'type': 'signout',
                    'data': {'type': 'signout'},
                }:
                    seen_signout = True
        async with async_timeout.timeout(2):
            while active_sockets.get(users[0]['user']['id']):
                await asyncio.sleep(0.05)


async def test_signout_closes_local_socket_even_if_pubsub_publish_fails(cli):
    created = await signup(cli)
    original_publish_signout = cli.app['store'].publish_signout

    async def broken_publish_signout(_user_id):
        raise AssertionError('publish_signout should not be required for local socket teardown')

    cli.app['store'].publish_signout = broken_publish_signout
    try:
        async with cli.ws_connect(
            '/api/ws',
            headers=websocket_cookie_headers(created['jwt']),
        ) as ws:
            response = await cli.post('/api/users/signout', headers=auth_headers(created['jwt']))
            assert response.status == 204

            seen_signout = False
            async with async_timeout.timeout(2):
                while not seen_signout:
                    payload = await ws.receive_json()
                    if payload == {
                        'type': 'signout',
                        'data': {'type': 'signout'},
                    }:
                        seen_signout = True

            async with async_timeout.timeout(2):
                while active_sockets.get(created['user']['id']):
                    await asyncio.sleep(0.05)
    finally:
        cli.app['store'].publish_signout = original_publish_signout


async def test_rooms_changed_event_when_other_guest_account_disappears(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({'type': 'subscribe-room', 'data': {'room_id': room['id']}}))
        subscribed = await ws.receive()
        payload = json.loads(subscribed.data)
        assert payload['type'] == 'subscribed-room'
        await cli.post('/api/users/signout', headers=auth_headers(users[1]['jwt']))

        async with async_timeout.timeout(2):
            while True:
                message = await ws.receive()
                payload = json.loads(message.data)
                if payload['type'] == 'rooms-changed':
                    break

    rooms = await get_rooms(cli, users[0]['jwt'])
    assert [existing_room['id'] for existing_room in rooms] == [room['id']]


async def test_invalid_websocket_payload_returns_error_and_connection_stays_open(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        await ws.send_str('{')
        message = await ws.receive_json()
        assert message == {
            'type': 'error',
            'data': {
                'code': 'invalid-json',
                'message': 'Invalid JSON payload',
            },
        }

        await ws.send_str(json.dumps({
            'type': 'subscribe-room',
            'data': {'room_id': room['id']},
        }))
        subscribed = await ws.receive_json()
        assert subscribed == {
            'type': 'subscribed-room',
            'data': {'room_id': room['id']},
        }

        await send_message(cli, users[0]['jwt'], room['id'], 'still alive')
        delivered = await ws.receive_json()
        assert delivered['type'] == 'new-messages'
        assert delivered['data']['messages'][0]['body'] == 'still alive'
        assert delivered['data']['messages'][0]['sender']['id'] == users[0]['user']['id']


async def test_mark_room_read_broadcasts_room_read_event(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    sent = await send_message(cli, users[0]['jwt'], room['id'], 'hello')

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({'type': 'subscribe-room', 'data': {'room_id': room['id']}}))
        subscribed = await ws.receive_json()
        assert subscribed == {
            'type': 'subscribed-room',
            'data': {'room_id': room['id']},
        }

        response = await mark_room_read(cli, users[1]['jwt'], room['id'], sent['id'])
        assert response.status == 200

        event = await ws.receive_json()
        assert event['type'] == 'room-read'
        assert event['data']['room_id'] == room['id']
        assert event['data']['user_id'] == users[1]['user']['id']
        assert event['data']['message_id'] == sent['id']

        messages_response = await get_messages(cli, users[0]['jwt'], room['id'])
        messages = await messages_response.json()
        assert sorted(reader['id'] for reader in messages[0]['read_by_users']) == sorted([
            users[0]['user']['id'],
            users[1]['user']['id'],
        ])


async def test_typing_state_is_broadcast_to_room_subscribers(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({'type': 'subscribe-room', 'data': {'room_id': room['id']}}))
        subscribed = await ws.receive_json()
        assert subscribed == {
            'type': 'subscribed-room',
            'data': {'room_id': room['id']},
        }

        async with cli.ws_connect(
            '/api/ws',
            headers=websocket_cookie_headers(users[1]['jwt']),
        ) as other_ws:
            await other_ws.send_str(json.dumps({
                'type': 'typing-state',
                'data': {'room_id': room['id'], 'is_typing': True},
            }))

            event = await ws.receive_json()
            assert event == {
                'type': 'typing-state',
                'data': {
                    'type': 'typing-state',
                    'room_id': room['id'],
                    'user_id': users[1]['user']['id'],
                    'is_typing': True,
                    'user': {
                        'id': users[1]['user']['id'],
                        'username': users[1]['username'],
                        'picture': users[1]['user']['picture'],
                    },
                },
            }


async def test_invalid_room_id_returns_error(cli):
    created = await signup(cli)

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(created['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({
            'type': 'subscribe-room',
            'data': {'room_id': 'abc'},
        }))
        message = await ws.receive_json()
        assert message == {
            'type': 'error',
            'data': {
                'code': 'invalid-room-id',
                'message': 'room_id must be an integer',
            },
        }


async def test_solo_room_remains_subscribed_when_other_guest_account_disappears(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({'type': 'subscribe-room', 'data': {'room_id': room['id']}}))
        subscribed = await ws.receive_json()
        assert subscribed['type'] == 'subscribed-room'

        pubsub_counts = await cli.app['redis'].execute_command(
            'PUBSUB',
            'NUMSUB',
            f'room:{room["id"]}',
        )
        assert int(pubsub_counts[1]) == 1

        await cli.post('/api/users/signout', headers=auth_headers(users[1]['jwt']))
        changed = await ws.receive_json()
        assert changed['type'] == 'rooms-changed'

        pubsub_counts = await cli.app['redis'].execute_command(
            'PUBSUB',
            'NUMSUB',
            f'room:{room["id"]}',
        )
        assert int(pubsub_counts[1]) == 1


async def test_unknown_message_type_returns_error(cli):
    created = await signup(cli)

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(created['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({'type': 'bogus', 'data': {}}))
        message = await ws.receive_json()
        assert message == {
            'type': 'error',
            'data': {
                'code': 'unknown-message-type',
                'message': 'Unknown websocket message type',
            },
        }


async def test_room_access_denied_error_includes_room_id(cli):
    created = await signup(cli)

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(created['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({
            'type': 'subscribe-room',
            'data': {'room_id': 999999},
        }))
        message = await ws.receive_json()
        assert message == {
            'type': 'error',
            'data': {
                'code': 'room-access-denied',
                'message': 'Cannot subscribe to that room',
                'room_id': 999999,
            },
        }


async def test_websocket_requires_auth(cli):
    try:
        async with cli.ws_connect('/api/ws') as ws:
            await ws.receive()
    except aiohttp.WSServerHandshakeError as exc:
        assert exc.status == 401
    else:
        raise AssertionError('Expected websocket handshake to be rejected')


async def test_websocket_query_token_auth_is_rejected(cli):
    created = await signup(cli)

    try:
        async with cli.ws_connect(f'/api/ws?token={created["jwt"]}') as ws:
            await ws.receive()
    except aiohttp.WSServerHandshakeError as exc:
        assert exc.status == 401
    else:
        raise AssertionError('Expected websocket handshake to reject query-token auth')


async def test_profile_update_broadcasts_rooms_changed_to_room_members(cli):
    users = [await signup(cli) for _ in range(2)]
    await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        response = await update_profile(
            cli,
            users[1]['jwt'],
            username='renamed-user',
            status='updated status',
        )
        assert response.status == 200

        event = await ws.receive_json()
        assert event == {
            'type': 'rooms-changed',
            'data': {'type': 'rooms-changed'},
        }


async def test_room_rename_broadcasts_rooms_changed_to_other_members(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[1]['jwt']),
    ) as ws:
        response = await cli.post(
            '/api/social/update-room-settings',
            json={'room_id': room['id'], 'name': 'Night walk'},
            headers=auth_headers(users[0]['jwt']),
        )
        assert response.status == 200

        event = await ws.receive_json()
        assert event == {
            'type': 'rooms-changed',
            'data': {'type': 'rooms-changed'},
        }


async def test_profile_update_broadcasts_nearby_changed_to_nearby_viewers(cli):
    users = [await signup(cli) for _ in range(2)]
    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], HAMBURG)

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        response = await update_profile(
            cli,
            users[1]['jwt'],
            status='nearby status update',
        )
        assert response.status == 200

        event = await ws.receive_json()
        assert event == {
            'type': 'nearby-changed',
            'data': {'type': 'nearby-changed'},
        }


async def test_remote_room_member_status_update_does_not_refresh_unrelated_nearby_room_viewers(cli):
    users = [await signup(cli) for _ in range(3)]
    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], HAMBURG)
    room = await create_group_room(
        cli,
        users[1]['jwt'],
        'Coffee crew',
        [users[2]['user']['id']],
    )
    assert room['id']

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        response = await update_profile(
            cli,
            users[2]['jwt'],
            status='updated remotely',
        )
        assert response.status == 200

        try:
            async with async_timeout.timeout(0.2):
                event = await ws.receive_json()
            raise AssertionError(f'Unexpected websocket event: {event}')
        except asyncio.TimeoutError:
            pass


async def test_room_creation_broadcasts_nearby_changed_to_nearby_viewers(cli):
    users = [await signup(cli) for _ in range(3)]
    for user in users:
        await checkin(cli, user['jwt'], HAMBURG)

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        room = await create_group_room(
            cli,
            users[1]['jwt'],
            'Coffee crew',
            [users[2]['user']['id']],
        )
        assert room['id']

        event = await ws.receive_json()
        assert event == {
            'type': 'nearby-changed',
            'data': {'type': 'nearby-changed'},
        }


async def test_remote_room_member_avatar_upload_broadcasts_nearby_changed_to_room_viewers(cli):
    users = [await signup(cli) for _ in range(3)]
    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], HAMBURG)
    room = await create_group_room(
        cli,
        users[1]['jwt'],
        'Coffee crew',
        [users[2]['user']['id']],
    )
    assert room['id']

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        response = await upload_avatar(
            cli,
            users[2]['jwt'],
            create_avatar_bytes(color=(255, 0, 0, 255)),
        )
        assert response.status == 200

        event = await ws.receive_json()
        assert event == {
            'type': 'nearby-changed',
            'data': {'type': 'nearby-changed'},
        }


async def test_room_membership_change_broadcasts_nearby_changed_to_room_viewers(cli):
    users = [await signup(cli) for _ in range(3)]
    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], HAMBURG)
    room = await create_group_room(
        cli,
        users[1]['jwt'],
        'Coffee crew',
        [users[2]['user']['id']],
    )
    assert room['id']

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        response = await cli.post(
            '/api/users/signout',
            headers=auth_headers(users[2]['jwt']),
        )
        assert response.status == 204

        event = await ws.receive_json()
        assert event == {
            'type': 'nearby-changed',
            'data': {'type': 'nearby-changed'},
        }


async def test_nearby_room_message_broadcasts_nearby_changed_to_nearby_viewers(cli):
    users = [await signup(cli) for _ in range(3)]
    for user in users:
        await checkin(cli, user['jwt'], HAMBURG)
    room = await create_group_room(
        cli,
        users[1]['jwt'],
        'Coffee crew',
        [users[2]['user']['id']],
    )

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        response = await send_message(
            cli,
            users[1]['jwt'],
            room['id'],
            'Meet us by the window',
        )
        assert response['body'] == 'Meet us by the window'

        event = await ws.receive_json()
        assert event == {
            'type': 'nearby-changed',
            'data': {'type': 'nearby-changed'},
        }


async def test_requester_profile_update_broadcasts_room_requests_changed(cli):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({'type': 'subscribe-room', 'data': {'room_id': room['id']}}))
        subscribed = await ws.receive_json()
        assert subscribed == {
            'type': 'subscribed-room',
            'data': {'room_id': room['id']},
        }

        response = await update_profile(
            cli,
            users[2]['jwt'],
            status='please let me in',
        )
        assert response.status == 200

        event = await ws.receive_json()
        assert event == {
            'type': 'room-requests-changed',
            'data': {'type': 'room-requests-changed', 'room_id': room['id']},
        }


async def test_avatar_upload_broadcasts_rooms_changed_to_room_members(cli):
    users = [await signup(cli) for _ in range(2)]
    await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        response = await upload_avatar(
            cli,
            users[1]['jwt'],
            create_avatar_bytes(),
        )
        assert response.status == 200

        event = await ws.receive_json()
        assert event == {
            'type': 'rooms-changed',
            'data': {'type': 'rooms-changed'},
        }


async def test_room_join_request_broadcasts_room_requests_changed(cli):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        await ws.send_str(json.dumps({'type': 'subscribe-room', 'data': {'room_id': room['id']}}))
        subscribed = await ws.receive_json()
        assert subscribed == {
            'type': 'subscribed-room',
            'data': {'room_id': room['id']},
        }

        response = await request_room_join(cli, users[2]['jwt'], room['id'])
        assert response.status == 200

        event = await ws.receive_json()
        assert event == {
            'type': 'room-requests-changed',
            'data': {'type': 'room-requests-changed', 'room_id': room['id']},
        }


async def test_room_join_request_broadcasts_rooms_changed_to_members(cli):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[0]['jwt']),
    ) as ws:
        response = await request_room_join(cli, users[2]['jwt'], room['id'])
        assert response.status == 200

        event = await ws.receive_json()
        assert event == {
            'type': 'rooms-changed',
            'data': {'type': 'rooms-changed'},
        }


async def test_room_join_request_rejection_broadcasts_nearby_changed(cli):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[2]['jwt']),
    ) as ws:
        response = await reject_room_request(
            cli,
            users[1]['jwt'],
            room['id'],
            users[2]['user']['id'],
        )
        assert response.status == 204

        event = await ws.receive_json()
        assert event == {
            'type': 'nearby-changed',
            'data': {'type': 'nearby-changed'},
        }


async def test_send_message_broadcasts_nearby_changed_to_pending_requesters(cli):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[2]['jwt']),
    ) as ws:
        await send_message(cli, users[0]['jwt'], room['id'], 'hello from inside')

        event = await ws.receive_json()
        assert event == {
            'type': 'nearby-changed',
            'data': {'type': 'nearby-changed'},
        }


async def test_room_join_request_approval_broadcasts_rooms_changed_and_nearby_changed(cli):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[2]['jwt']),
    ) as requester_ws:
        response = await approve_room_request(
            cli,
            users[0]['jwt'],
            room['id'],
            users[2]['user']['id'],
        )
        assert response.status == 200

        payloads = set()
        async with async_timeout.timeout(2):
            while payloads != {'rooms-changed', 'nearby-changed'}:
                event = await requester_ws.receive_json()
                payloads.add(event['type'])
        assert payloads == {'rooms-changed', 'nearby-changed'}


async def test_approving_one_request_broadcasts_nearby_changed_to_remaining_requesters(cli):
    users = [await signup(cli) for _ in range(4)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    first = await request_room_join(cli, users[2]['jwt'], room['id'])
    second = await request_room_join(cli, users[3]['jwt'], room['id'])
    assert first.status == 200
    assert second.status == 200

    async with cli.ws_connect(
        '/api/ws',
        headers=websocket_cookie_headers(users[3]['jwt']),
    ) as requester_ws:
        response = await approve_room_request(
            cli,
            users[0]['jwt'],
            room['id'],
            users[2]['user']['id'],
        )
        assert response.status == 200

        event = await requester_ws.receive_json()
        assert event == {
            'type': 'nearby-changed',
            'data': {'type': 'nearby-changed'},
        }
