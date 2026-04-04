import asyncio
import json

import async_timeout
from app.websocket import active_sockets

from tests.helpers import HAMBURG, MADRID, checkin, get_rooms, join_user, send_message, signup


async def test_room_subscription_and_signout_disconnect(cli):
    users = [await signup(cli) for _ in range(2)]
    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], MADRID)
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(f'/api/ws?token={users[0]["jwt"]}') as ws:
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

        await cli.post('/api/users/signout', cookies={'jwt': users[0]['jwt']})
        async with async_timeout.timeout(2):
            while active_sockets.get(users[0]['user']['id']):
                await asyncio.sleep(0.05)


async def test_room_deleted_event_when_other_guest_account_disappears(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    async with cli.ws_connect(f'/api/ws?token={users[0]["jwt"]}') as ws:
        await ws.send_str(json.dumps({'type': 'subscribe-room', 'data': {'room_id': room['id']}}))
        subscribed = await ws.receive()
        payload = json.loads(subscribed.data)
        assert payload['type'] == 'subscribed-room'
        await cli.post('/api/users/signout', cookies={'jwt': users[1]['jwt']})

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
