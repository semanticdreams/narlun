import asyncio
import json

import async_timeout
import aiohttp
from app.websocket import active_sockets

from tests.helpers import (
    HAMBURG,
    MADRID,
    auth_headers,
    checkin,
    get_rooms,
    join_user,
    send_message,
    signup,
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


async def test_room_deleted_event_when_other_guest_account_disappears(cli):
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

        seen_room_deleted = False
        seen_rooms_changed = False

        async with async_timeout.timeout(2):
            while not (seen_room_deleted and seen_rooms_changed):
                message = await ws.receive()
                payload = json.loads(message.data)
                if payload['type'] == 'room-deleted':
                    assert payload['data']['room_id'] == room['id']
                    seen_room_deleted = True
                elif payload['type'] == 'rooms-changed':
                    seen_rooms_changed = True

    rooms = await get_rooms(cli, users[0]['jwt'])
    assert all(existing_room['id'] != room['id'] for existing_room in rooms)


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


async def test_room_deleted_unsubscribes_backend_pubsub_subscription(cli):
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
        deleted = await ws.receive_json()
        changed = await ws.receive_json()
        assert {deleted['type'], changed['type']} == {'room-deleted', 'rooms-changed'}

        deadline = asyncio.get_running_loop().time() + 2
        while asyncio.get_running_loop().time() < deadline:
            pubsub_counts = await cli.app['redis'].execute_command(
                'PUBSUB',
                'NUMSUB',
                f'room:{room["id"]}',
            )
            if int(pubsub_counts[1]) == 0:
                break
            await asyncio.sleep(0.05)
        else:
            raise AssertionError('room subscription was not cleaned up')


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
