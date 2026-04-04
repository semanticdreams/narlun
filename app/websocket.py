import asyncio
import json

import aiohttp
import async_timeout
from aiohttp import web

from app.util import authenticated


active_sockets = {}


async def close_user_websockets(user_id):
    sockets = list(active_sockets.get(int(user_id), set()))
    for ws in sockets:
        await ws.close()


async def _subscribe_room(req, channel, room_id):
    if await req.store.user_in_room(req.user['id'], int(room_id)):
        await channel.subscribe(f'room:{room_id}')
        return True
    return False


async def _unsubscribe_room(req, channel, room_id):
    if await req.store.user_in_room(req.user['id'], int(room_id)):
        await channel.unsubscribe(f'room:{room_id}')
        return True
    return False


@authenticated
async def websocket_handler(req):
    ws = web.WebSocketResponse()
    await ws.prepare(req)
    user_id = int(req.user['id'])

    channel = req.redis.pubsub()
    await channel.subscribe(f'user:{user_id}')
    active_sockets.setdefault(user_id, set()).add(ws)

    async def reader():
        while True:
            try:
                async with async_timeout.timeout(1):
                    message = await channel.get_message(ignore_subscribe_messages=True)
                    if message is None:
                        await asyncio.sleep(0.01)
                        continue
                    data = json.loads(message['data'])
                    if data['type'] == 'signout':
                        await ws.send_str(json.dumps({'type': 'signout', 'data': data}))
                        await ws.close()
                        break
                    await ws.send_str(json.dumps({'type': data['type'], 'data': data}))
            except asyncio.TimeoutError:
                pass
            except asyncio.CancelledError:
                break

    reader_task = asyncio.create_task(reader())

    async for msg in ws:
        if msg.type == aiohttp.WSMsgType.TEXT:
            payload = json.loads(msg.data)
            message_type = payload.get('type')
            data = payload.get('data', {})
            room_id = data.get('room_id')
            if message_type == 'subscribe-room' and room_id is not None:
                if await _subscribe_room(req, channel, room_id):
                    await ws.send_str(json.dumps({
                        'type': 'subscribed-room',
                        'data': {'room_id': int(room_id)},
                    }))
            elif message_type == 'unsubscribe-room' and room_id is not None:
                if await _unsubscribe_room(req, channel, room_id):
                    await ws.send_str(json.dumps({
                        'type': 'unsubscribed-room',
                        'data': {'room_id': int(room_id)},
                    }))
        elif msg.type == aiohttp.WSMsgType.ERROR:
            break

    reader_task.cancel()
    sockets = active_sockets.get(user_id, set())
    sockets.discard(ws)
    if not sockets and user_id in active_sockets:
        del active_sockets[user_id]
    await channel.aclose()
    return ws
