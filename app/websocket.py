import json

import asyncio
import async_timeout

import aiohttp
from aiohttp import web

from app.log import get_logger
from app.util import JSONEncoder, authenticated


logger = get_logger()

routes = web.RouteTableDef()

pubsub_handlers = {}
ws_handlers = {}


def pubsub_handler(typ):
    """Collect redis pubsub handler functions."""
    def decorate(f):
        pubsub_handlers[typ] = f
        return f
    return decorate


def ws_handler(typ):
    """Collect websocket handler functions."""
    def decorate(f):
        ws_handlers[typ] = f
        return f
    return decorate


class UnknownPubsubMessageTypeError(Exception):
    pass


class UnknownWebsocketMessageTypeError(Exception):
    pass


class WsContext:
    """Bundle context data to be passed to handler functions."""
    def __init__(self, req, ws, channel, data):
        self.req = req
        self.ws = ws
        self.channel = channel
        self.data = data


@pubsub_handler('new-messages')
async def on_new_messages(ctx):
    # send new messages to ws client
    payload = json.dumps({'type': 'new-messages', 'data': ctx.data},
                         cls=JSONEncoder)
    await ctx.ws.send_str(payload)


@pubsub_handler('signout')
async def on_signout(ctx):
    # close ws connection on signout
    await ctx.ws.close()
    logger.debug('ws connection closed upon signout')


@ws_handler('subscribe-room')
async def ws_subscribe_room(ctx):
    # check room, ensure user is in it and subscribe user to room
    if (room_id := ctx.data['data']['room_id']) is not None:
        room = await ctx.req.db.fetchrow('select 1 from participants'
                                         ' where room_id = $1 and user_id = $2',
                                         room_id, ctx.req.user['id'])
        if room:
            channel_name = f'narlun:rooms:{room_id}'
            await ctx.channel.subscribe(channel_name)


@ws_handler('unsubscribe-room')
async def ws_unsubscribe_room(ctx):
    # check room, ensure user is in it and unsubscribe user from room
    if (room_id := ctx.data['data']['room_id']) is not None:
        room = await ctx.req.db.fetchrow('select 1 from participants'
                                         ' where room_id = $1 and user_id = $2',
                                         room_id, ctx.req.user['id'])
        if room:
            channel_name = f'narlun:rooms:{room_id}'
            await ctx.channel.unsubscribe(channel_name)


@routes.get('/api/ws')
@authenticated
async def websocket_handler(req):
    """Handle websocket request."""
    ws = web.WebSocketResponse()

    await ws.prepare(req)

    # create pubsub channel
    channel = req.redis.pubsub()

    # automatically subscribe all users to a channel corresponding to their id
    await channel.subscribe(f'narlun:users:{req.user["id"]}')

    # the reader will handle messages incoming from the pubsub channel
    async def reader(pubsub):
        while True:
            try:
                async with async_timeout.timeout(1):
                    message = await pubsub.get_message(ignore_subscribe_messages=True)
                    if message is not None:
                        data_str = message['data']
                        data = json.loads(data_str)
                        if data['type'] == 'stop':
                            break
                        else:
                            handler = pubsub_handlers.get(data['type'])
                            if handler:
                                await handler(WsContext(req=req, channel=channel, ws=ws,
                                                        data=data))
                            else:
                                raise UnknownPubsubMessageTypeError(data['type'])
                    await asyncio.sleep(0.01)
            except asyncio.TimeoutError:
                pass
            except Exception as e:
                logger.error(e, exc_info=True, stack_info=True)
                await ws.close()

    # trigger reader task but don't await
    reader_task = asyncio.create_task(reader(channel))

    # now handle incoming websocket messages
    async for msg in ws:
        if msg.type == aiohttp.WSMsgType.TEXT:
            if msg.data == 'close':
                await ws.close()
            else:
                data = json.loads(msg.data)
                handler = ws_handlers.get(data['type'])
                if handler:
                    await handler(WsContext(req=req, channel=channel, ws=ws,
                                            data=data))
                else:
                    raise UnknownWebsocketMessageTypeError(data['type'])
        elif msg.type == aiohttp.WSMsgType.ERROR:
            logger.error('ws connection closed with exception %s' %
                         ws.exception())

    # cancel reader task to prevent error
    reader_task.cancel()

    return ws
