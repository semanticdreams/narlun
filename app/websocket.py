import asyncio
import contextlib
import json
import logging
import secrets

import aiohttp
import async_timeout
from aiohttp import web
from aiohttp.http_websocket import WSCloseCode

from app.observability import request_log_context
from app.push import normalized_client_id
from app.util import authenticated


active_sockets = {}
logger = logging.getLogger(__name__)
_presence_refresh_interval_seconds = 15


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


def _normalize_live_view(data):
    view = data.get('view')
    if not isinstance(view, str):
        raise ValueError('view must be a string')
    normalized_view = view.strip()
    if normalized_view == 'none':
        return None
    if normalized_view in {'rooms', 'nearby'}:
        return normalized_view
    if normalized_view == 'room':
        room_id = data.get('room_id')
        try:
            return f'room:{int(room_id)}'
        except (TypeError, ValueError) as exc:
            raise ValueError('room_id must be an integer') from exc
    raise ValueError('view must be one of none, rooms, nearby, room')


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
    connection_id = secrets.token_hex(16)
    client_id = normalized_client_id(req.query.get('client_id'))
    client_session_id = req.query.get('client_session_id')
    await req.store.mark_active_websocket(user_id, connection_id, client_id=client_id)
    subscribed_rooms = set()
    current_live_view = None
    logger.info(
        'Websocket connected',
        extra=request_log_context(
            req,
            connection_id=connection_id,
            client_id=client_id,
            client_session_id=client_session_id,
        ),
    )

    async def refresh_presence():
        while True:
            try:
                await asyncio.sleep(_presence_refresh_interval_seconds)
                await req.store.mark_active_websocket(user_id, connection_id, client_id=client_id)
                if client_id and current_live_view is not None:
                    await req.store.mark_live_view(
                        user_id,
                        connection_id,
                        client_id=client_id,
                        view_key=current_live_view,
                    )
            except asyncio.CancelledError:
                break
            except Exception:
                logger.exception(
                    'Failed to refresh websocket presence',
                    extra=request_log_context(
                        req,
                        connection_id=connection_id,
                        client_id=client_id,
                        ),
                )

    async def update_live_view(next_live_view):
        nonlocal current_live_view
        if not client_id or current_live_view == next_live_view:
            current_live_view = next_live_view
            return
        if current_live_view is not None:
            await req.store.clear_live_view(
                user_id,
                connection_id,
                client_id=client_id,
                view_key=current_live_view,
            )
        current_live_view = next_live_view
        if current_live_view is not None:
            await req.store.mark_live_view(
                user_id,
                connection_id,
                client_id=client_id,
                view_key=current_live_view,
            )

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
                        logger.warning(
                            'Ignoring invalid pubsub payload',
                            extra=request_log_context(
                                req,
                                connection_id=connection_id,
                                client_id=client_id,
                                payload=message.get('data'),
                            ),
                        )
                        continue
                    logger.debug(
                        'Forwarding websocket event',
                        extra=request_log_context(
                            req,
                            connection_id=connection_id,
                            client_id=client_id,
                            event_type=data.get('type'),
                            room_id=data.get('room_id'),
                        ),
                    )
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
                logger.exception(
                    'Websocket pubsub reader failed',
                    extra=request_log_context(
                        req,
                        connection_id=connection_id,
                        client_id=client_id,
                    ),
                )
                if not ws.closed:
                    await ws.close(
                        code=WSCloseCode.INTERNAL_ERROR,
                        message=b'Pubsub reader failed',
                    )
                break

    reader_task = asyncio.create_task(reader())
    presence_task = asyncio.create_task(refresh_presence())

    try:
        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    payload = json.loads(msg.data)
                except json.JSONDecodeError:
                    logger.warning(
                        'Rejected invalid websocket JSON payload',
                        extra=request_log_context(
                            req,
                            connection_id=connection_id,
                            client_id=client_id,
                        ),
                    )
                    await _send_error(
                        ws,
                        code='invalid-json',
                        message='Invalid JSON payload',
                    )
                    continue

                if not isinstance(payload, dict):
                    logger.warning(
                        'Rejected non-object websocket payload',
                        extra=request_log_context(
                            req,
                            connection_id=connection_id,
                            client_id=client_id,
                        ),
                    )
                    await _send_error(
                        ws,
                        code='invalid-payload',
                        message='Payload must be an object',
                    )
                    continue

                message_type = payload.get('type')
                data = payload.get('data', {})
                if not isinstance(data, dict):
                    logger.warning(
                        'Rejected websocket payload with invalid data field',
                        extra=request_log_context(
                            req,
                            connection_id=connection_id,
                            client_id=client_id,
                            message_type=message_type,
                        ),
                    )
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
                        logger.warning(
                            'Rejected websocket payload with invalid room id',
                            extra=request_log_context(
                                req,
                                connection_id=connection_id,
                                client_id=client_id,
                                message_type=message_type,
                                room_id=room_id,
                            ),
                        )
                        await _send_error(
                            ws,
                            code='invalid-room-id',
                            message='room_id must be an integer',
                        )
                        continue

                if message_type == 'subscribe-room':
                    if await _subscribe_room(req, channel, room_id, subscribed_rooms):
                        logger.info(
                            'Subscribed websocket to room',
                            extra=request_log_context(
                                req,
                                connection_id=connection_id,
                                client_id=client_id,
                                room_id=room_id,
                            ),
                        )
                        await _send_event(ws, 'subscribed-room', {'room_id': room_id})
                    else:
                        logger.warning(
                            'Denied websocket room subscription',
                            extra=request_log_context(
                                req,
                                connection_id=connection_id,
                                client_id=client_id,
                                room_id=room_id,
                            ),
                        )
                        await _send_error(
                            ws,
                            code='room-access-denied',
                            message='Cannot subscribe to that room',
                            room_id=room_id,
                        )
                elif message_type == 'typing-state':
                    try:
                        room_id = int(room_id)
                    except (TypeError, ValueError):
                        await _send_error(
                            ws,
                            code='invalid-room-id',
                            message='room_id must be an integer',
                        )
                        continue
                    is_typing = data.get('is_typing')
                    if not isinstance(is_typing, bool):
                        await _send_error(
                            ws,
                            code='invalid-typing-state',
                            message='is_typing must be a boolean',
                        )
                        continue
                    if not await req.store.user_in_room(req.user['id'], room_id):
                        await _send_error(
                            ws,
                            code='room-access-denied',
                            message='Cannot send typing updates for that room',
                            room_id=room_id,
                        )
                        continue
                    await req.store.publish_room_typing(
                        room_id,
                        req.user['id'],
                        is_typing=is_typing,
                    )
                    logger.info(
                        'Updated room typing state',
                        extra=request_log_context(
                            req,
                            connection_id=connection_id,
                            client_id=client_id,
                            room_id=room_id,
                            is_typing=is_typing,
                        ),
                    )
                elif message_type == 'unsubscribe-room':
                    if await _unsubscribe_room(channel, room_id, subscribed_rooms):
                        logger.info(
                            'Unsubscribed websocket from room',
                            extra=request_log_context(
                                req,
                                connection_id=connection_id,
                                client_id=client_id,
                                room_id=room_id,
                            ),
                        )
                        await _send_event(ws, 'unsubscribed-room', {'room_id': room_id})
                elif message_type == 'set-live-view':
                    try:
                        next_live_view = _normalize_live_view(data)
                    except ValueError as exc:
                        logger.warning(
                            'Rejected websocket payload with invalid live view',
                            extra=request_log_context(
                                req,
                                connection_id=connection_id,
                                client_id=client_id,
                                message_type=message_type,
                                error=str(exc),
                            ),
                        )
                        await _send_error(
                            ws,
                            code='invalid-live-view',
                            message=str(exc),
                        )
                        continue
                    if next_live_view and next_live_view.startswith('room:'):
                        room_id = int(next_live_view.split(':', 1)[1])
                        if not await req.store.user_in_room(req.user['id'], room_id):
                            logger.warning(
                                'Denied websocket live view for inaccessible room',
                                extra=request_log_context(
                                    req,
                                    connection_id=connection_id,
                                    client_id=client_id,
                                    room_id=room_id,
                                ),
                            )
                            await _send_error(
                                ws,
                                code='room-access-denied',
                                message='Cannot track that room as a live view',
                                room_id=room_id,
                            )
                            continue
                    await update_live_view(next_live_view)
                    logger.info(
                        'Updated websocket live view',
                        extra=request_log_context(
                            req,
                            connection_id=connection_id,
                            client_id=client_id,
                            live_view=current_live_view,
                        ),
                    )
                else:
                    logger.warning(
                        'Rejected websocket payload with unknown message type',
                        extra=request_log_context(
                            req,
                            connection_id=connection_id,
                            client_id=client_id,
                            message_type=message_type,
                        ),
                    )
                    await _send_error(
                        ws,
                        code='unknown-message-type',
                        message='Unknown websocket message type',
                    )
            elif msg.type == aiohttp.WSMsgType.ERROR:
                break
    finally:
        reader_task.cancel()
        presence_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await reader_task
        with contextlib.suppress(asyncio.CancelledError):
            await presence_task
        for room_id in list(subscribed_rooms):
            with contextlib.suppress(Exception):
                await _unsubscribe_room(channel, room_id, subscribed_rooms)
        sockets = active_sockets.get(user_id, set())
        sockets.discard(ws)
        if not sockets and user_id in active_sockets:
            del active_sockets[user_id]
        if client_id and current_live_view is not None:
            with contextlib.suppress(Exception):
                await req.store.clear_live_view(
                    user_id,
                    connection_id,
                    client_id=client_id,
                    view_key=current_live_view,
                )
        with contextlib.suppress(Exception):
            await req.store.clear_active_websocket(user_id, connection_id, client_id=client_id)
        await channel.aclose()
        logger.info(
            'Websocket disconnected',
            extra=request_log_context(
                req,
                connection_id=connection_id,
                client_id=client_id,
                subscribed_room_count=len(subscribed_rooms),
                subscribed_room_ids=sorted(subscribed_rooms),
            ),
        )
    return ws
