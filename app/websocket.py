import asyncio
import contextlib
import json
import logging

import aiohttp
import async_timeout
from aiohttp import web
from aiohttp.http_websocket import WSCloseCode

from app.util import authenticated


active_sockets = {}
logger = logging.getLogger(__name__)


async def _close_socket_after_grace_period(ws):
    await asyncio.sleep(0.2)
    if not ws.closed:
        await ws.close()


async def notify_local_signout(user_id):
    sockets = list(active_sockets.get(int(user_id), set()))
    if not sockets:
        return
    for ws in sockets:
        try:
            await _send_event(ws, 'signout', {'type': 'signout'})
        except Exception:
            logger.exception('Failed to send local signout event', extra={'user_id': user_id})
        asyncio.create_task(_close_socket_after_grace_period(ws))


async def _send_event(ws, event_type, data):
    if not ws.closed:
        await ws.send_str(json.dumps({'type': event_type, 'data': data}))


async def _send_error(ws, *, code, message, **data):
    await _send_event(ws, 'error', {'code': code, 'message': message, **data})


async def _subscribe_room(req, channel, room_id, subscribed_rooms):
    if await req.store.user_in_room(req.user['id'], int(room_id)):
        await channel.subscribe(f'room:{room_id}')
        subscribed_rooms.add(int(room_id))
        return True
    return False


async def _unsubscribe_room(channel, room_id, subscribed_rooms):
    room_id = int(room_id)
    if room_id in subscribed_rooms:
        await channel.unsubscribe(f'room:{room_id}')
        subscribed_rooms.discard(room_id)
        return True
    return False


@authenticated
async def websocket_handler(req):
    ws = web.WebSocketResponse(
        heartbeat=30.0,
        receive_timeout=60.0,
    )
    await ws.prepare(req)
    user_id = int(req.user['id'])

    channel = req.redis.pubsub()
    await channel.subscribe(f'user:{user_id}')
    active_sockets.setdefault(user_id, set()).add(ws)
    subscribed_rooms = set()

    async def reader():
        while True:
            try:
                async with async_timeout.timeout(1):
                    message = await channel.get_message(ignore_subscribe_messages=True)
                    if message is None:
                        await asyncio.sleep(0.01)
                        continue
                    try:
                        data = json.loads(message['data'])
                    except (TypeError, json.JSONDecodeError):
                        logger.warning('Ignoring invalid pubsub payload', extra={
                            'user_id': user_id,
                            'payload': message.get('data'),
                        })
                        continue
                    if data['type'] == 'signout':
                        await _send_event(ws, 'signout', data)
                        asyncio.create_task(_close_socket_after_grace_period(ws))
                        break
                    if data['type'] == 'room-deleted':
                        room_id = data.get('room_id')
                        if room_id is not None:
                            await _unsubscribe_room(channel, room_id, subscribed_rooms)
                    await _send_event(ws, data['type'], data)
            except asyncio.TimeoutError:
                pass
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception('Websocket pubsub reader failed', extra={'user_id': user_id})
                if not ws.closed:
                    await ws.close(
                        code=WSCloseCode.INTERNAL_ERROR,
                        message=b'Pubsub reader failed',
                    )
                break

    reader_task = asyncio.create_task(reader())

    try:
        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    payload = json.loads(msg.data)
                except json.JSONDecodeError:
                    await _send_error(
                        ws,
                        code='invalid-json',
                        message='Invalid JSON payload',
                    )
                    continue

                if not isinstance(payload, dict):
                    await _send_error(
                        ws,
                        code='invalid-payload',
                        message='Payload must be an object',
                    )
                    continue

                message_type = payload.get('type')
                data = payload.get('data', {})
                if not isinstance(data, dict):
                    await _send_error(
                        ws,
                        code='invalid-data',
                        message='Payload data must be an object',
                    )
                    continue

                room_id = data.get('room_id')
                if message_type in {'subscribe-room', 'unsubscribe-room'}:
                    try:
                        room_id = int(room_id)
                    except (TypeError, ValueError):
                        await _send_error(
                            ws,
                            code='invalid-room-id',
                            message='room_id must be an integer',
                        )
                        continue

                if message_type == 'subscribe-room':
                    if await _subscribe_room(req, channel, room_id, subscribed_rooms):
                        await _send_event(ws, 'subscribed-room', {'room_id': room_id})
                    else:
                        await _send_error(
                            ws,
                            code='room-access-denied',
                            message='Cannot subscribe to that room',
                            room_id=room_id,
                        )
                elif message_type == 'unsubscribe-room':
                    if await _unsubscribe_room(channel, room_id, subscribed_rooms):
                        await _send_event(ws, 'unsubscribed-room', {'room_id': room_id})
                else:
                    await _send_error(
                        ws,
                        code='unknown-message-type',
                        message='Unknown websocket message type',
                    )
            elif msg.type == aiohttp.WSMsgType.ERROR:
                break
    finally:
        reader_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await reader_task
        for room_id in list(subscribed_rooms):
            with contextlib.suppress(Exception):
                await _unsubscribe_room(channel, room_id, subscribed_rooms)
        sockets = active_sockets.get(user_id, set())
        sockets.discard(ws)
        if not sockets and user_id in active_sockets:
            del active_sockets[user_id]
        await channel.aclose()
    return ws
