import asyncio
import aiohttp
from aiohttp import web
import aioredis
import json


class WebSocketHandler:
    def __init__(self, redis):
        self.clients = {}  # Maps WebSocket to a set of subscribed channels
        self.redis = redis
        self.subscribed_channels = {}
        self.listener_tasks = {}  # Maps channel names to listener tasks

    #async def start_redis(self):
    #    self.redis = await aioredis.create_redis_pool('redis://localhost')

    async def manage_subscription(self, channel, subscribe=True):
        if subscribe and channel not in self.subscribed_channels:
            # Subscribe to new channel
            redis_channel = await self.redis.subscribe(channel)
            self.subscribed_channels[channel] = redis_channel[0]
            task = asyncio.create_task(self.channel_listener(redis_channel[0]))
            self.listener_tasks[channel] = task
        elif not subscribe and channel in self.subscribed_channels:
            # Unsubscribe if no clients are interested in this channel
            if all(channel not in client_subs for client_subs in self.clients.values()):
                await self.redis.unsubscribe(channel)
                self.listener_tasks[channel].cancel()  # Cancel the listener task
                del self.subscribed_channels[channel]
                del self.listener_tasks[channel]

    async def channel_listener(self, channel):
        while True:
            try:
                await channel.wait_message()
                message = await channel.get()
                await self.broadcast(channel.name, message)
            except asyncio.CancelledError:
                # Handle cancellation here if needed
                break

    async def broadcast(self, channel_name, message):
        for ws, subscriptions in self.clients.items():
            if channel_name in subscriptions:
                try:
                    await ws.send_str(message.decode('utf-8'))
                except Exception as e:
                    # Handle disconnected client
                    del self.clients[ws]

    async def websocket_handler(self, req):
        ws = web.WebSocketResponse()
        await ws.prepare(req)

        self.clients[ws] = set()

        user_id = req.user['id']
        self.clients[ws].add(f'narlun:users:{user_id}')

        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                data = json.loads(msg.data)
                action = data.get('action')
                channel = data.get('channel')
                if action == 'subscribe':
                    self.clients[ws].add(channel)
                    await self.manage_subscription(channel, subscribe=True)
                elif action == 'unsubscribe':
                    self.clients[ws].discard(channel)
                    await self.manage_subscription(channel, subscribe=False)

        for channel in self.clients[ws]:
            await self.manage_subscription(channel, subscribe=False)
        del self.clients[ws]
        return ws
