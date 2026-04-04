import asyncio

import aiohttp_cors
import sentry_sdk
import uvloop
from aiohttp import web
from aiohttp.web import middleware
from sentry_sdk.integrations.aiohttp import AioHttpIntegration

import config
from app.redis_store import RedisStore
from app.social import create_app as create_social_app
from app.users import create_app as create_users_app
from app.util import InvalidUsage, load_user_from_token
from app.websocket import websocket_handler


@middleware
async def request_context(req, handler):
    req.store = req.config_dict['store']
    req.redis = req.config_dict['redis']
    req.redis_bytes = req.config_dict['redis_bytes']
    req.user = await load_user_from_token(req)

    if req.can_read_body:
        content_type = req.headers.get('Content-Type', '').split(';')[0]
        if content_type in {'text/plain', 'application/json'}:
            req.data = await req.json()
        else:
            req.data = {}
    else:
        req.data = {}

    try:
        return await handler(req)
    except InvalidUsage as exc:
        return web.json_response(
            {'message': exc.message, 'code': exc.code, 'payload': exc.payload},
            status=exc.status,
        )


async def create_app(*, redis_url=None, enable_cors=True):
    sentry_sdk.init(
        dsn=config.SENTRY_DSN,
        integrations=[AioHttpIntegration()],
        traces_sample_rate=0.0,
    )

    store = await RedisStore.create(redis_url or config.REDIS_URL)
    app = web.Application(middlewares=[request_context])
    app['store'] = store
    app['redis'] = store.redis
    app['redis_bytes'] = store.redis_bytes

    app.router.add_get('/api/ws', websocket_handler)
    app.add_subapp('/api/users', create_users_app())
    app.add_subapp('/api/social', create_social_app())

    if enable_cors:
        cors = aiohttp_cors.setup(app, defaults={
            'http://localhost:8080': aiohttp_cors.ResourceOptions(
                expose_headers='*',
                allow_headers='*',
                allow_credentials=True,
            )
        })
        for route in list(app.router.routes()):
            cors.add(route)

    async def close_store(_app):
        await store.close()

    app.on_cleanup.append(close_store)
    return app


if __name__ == '__main__':
    uvloop.install()
    loop = asyncio.get_event_loop()
    web.run_app(loop.run_until_complete(create_app()), port=config.PORT, handle_signals=False, loop=loop)
