import asyncio
import uvloop
import asyncpg
import aiohttp_cors
import aioredis

import config

import sentry_sdk
from sentry_sdk.integrations.aiohttp import AioHttpIntegration

from aiohttp import web
from aiohttp.web import middleware

from app.log import get_logger

from app.users import create_app as create_users_app
from app.social import create_app as create_social_app
from app.util import load_user_from_token, InvalidUsage
#from app.websocket import routes as websocket_routes
from app.ws import WebSocketHandler

logger = get_logger()


@middleware
async def middleware(req, handler):
    """Custom middleware loads data, checks user auth and adds some convenience objects."""
    req.db = req.config_dict['db']
    req.redis = req.config_dict['redis']
    req.user = await load_user_from_token(req)
    if req.can_read_body \
       and req.headers['Content-Type'].split(';')[0] \
       in ['text/plain', 'application/json']:
        req.data = await req.json()
    try:
        resp = await handler(req)
    except InvalidUsage as e:
        return web.json_response({'message': e.message, 'code': e.code, 'payload': e.payload},
                                 status=e.status)
    return resp


async def create_app():
    # add sentry for error tracking
    sentry_sdk.init(
        dsn=config.SENTRY_DSN,
        integrations=[AioHttpIntegration()],
        traces_sample_rate=0.0,
    )

    app = web.Application(middlewares=[middleware])

    # add postgres and redis connection pools
    app['db'] = await asyncpg.create_pool(dsn=config.DATABASE_URL)
    app['redis'] = await aioredis.from_url(config.REDIS_URL, decode_responses=True)

    handler = WebSocketHandler(app['redis'])
    app.router.add_get('/api/ws', handler.websocket_handler)
    #await handler.start_redis()

    #app.add_routes(websocket_routes) old logic

    app.add_subapp('/api/users', create_users_app())
    app.add_subapp('/api/social', create_social_app())

    # cors should allow localhost so frontend can use
    # remote backend
    cors = aiohttp_cors.setup(app, defaults={
        'http://localhost:8080': aiohttp_cors.ResourceOptions(
            expose_headers='*',
            allow_headers='*',
            allow_credentials=True
        )
    })
    for route in list(app.router.routes()):
        cors.add(route)

    return app


if __name__ == '__main__':
    uvloop.install()
    loop = asyncio.get_event_loop()
    app = loop.run_until_complete(create_app())
    web.run_app(app, port=config.PORT, handle_signals=False, loop=loop)
