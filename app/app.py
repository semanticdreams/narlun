import asyncio
import json
import logging
import secrets
import time
from pathlib import Path

import aiohttp_cors
import uvloop
from aiohttp import web
from aiohttp.web import middleware

import app.log  # noqa: F401
import config
from app.frontend_errors import create_frontend_error_tools, frontend_error_handler
from app.observability import request_log_context
from app.push import PushService
from app.redis_store import RedisStore
from app.social import create_app as create_social_app
from app.users import create_app as create_users_app
from app.util import InvalidJsonBody, InvalidUsage, load_user_from_token
from app.websocket import websocket_handler


logger = logging.getLogger(__name__)


def _request_success_logger(req):
    if req.path == '/api/client-errors':
        return logger.debug
    return logger.info


@middleware
async def request_context(req, handler):
    req.store = req.config_dict['store']
    req.push = req.config_dict['push']
    req.redis = req.config_dict['redis']
    req.redis_bytes = req.config_dict['redis_bytes']
    req.request_id = req.headers.get('X-Request-ID') or secrets.token_hex(8)
    started_at = time.perf_counter()
    req.user = await load_user_from_token(req)

    try:
        if req.can_read_body:
            content_type = req.headers.get('Content-Type', '').split(';')[0]
            if content_type in {'text/plain', 'application/json'}:
                try:
                    req.data = await req.json()
                except (json.JSONDecodeError, UnicodeDecodeError) as exc:
                    raise InvalidJsonBody() from exc
            else:
                    req.data = {}
        else:
            req.data = {}
        response = await handler(req)
    except InvalidUsage as exc:
        response = web.json_response(
            {'message': exc.message, 'code': exc.code, 'payload': exc.payload},
            status=exc.status,
        )
        response.headers['X-Request-ID'] = req.request_id
        logger.info(
            'Request completed with usage error',
            extra=request_log_context(
                req,
                status=exc.status,
                duration_ms=round((time.perf_counter() - started_at) * 1000, 1),
                error_code=exc.code,
                error_message=exc.message,
            ),
        )
        return response
    except web.HTTPException as exc:
        if exc.headers is None:
            exc.headers = {}
        exc.headers['X-Request-ID'] = req.request_id
        log_method = logger.warning if exc.status >= 500 else logger.info
        log_method(
            'Request raised HTTP exception',
            extra=request_log_context(
                req,
                status=exc.status,
                duration_ms=round((time.perf_counter() - started_at) * 1000, 1),
                reason=exc.reason,
            ),
        )
        raise
    except Exception:
        logger.exception(
            'Request failed unexpectedly',
            extra=request_log_context(
                req,
                duration_ms=round((time.perf_counter() - started_at) * 1000, 1),
            ),
        )
        raise
    response.headers['X-Request-ID'] = req.request_id
    _request_success_logger(req)(
        'Request completed',
        extra=request_log_context(
            req,
            status=response.status,
            duration_ms=round((time.perf_counter() - started_at) * 1000, 1),
        ),
    )
    return response


async def create_app(*, redis_url=None, enable_cors=True, push_service=None):
    store = await RedisStore.create(redis_url or config.REDIS_URL)
    frontend_error_tools = create_frontend_error_tools(config.FRONTEND_ERROR_LOG_PATH)
    app = web.Application(middlewares=[request_context])
    app['store'] = store
    app['push'] = push_service or PushService(store)
    app['redis'] = store.redis
    app['redis_bytes'] = store.redis_bytes
    app['frontend_error_log_writer'] = frontend_error_tools['writer']
    app['frontend_error_rate_limiter'] = frontend_error_tools['rate_limiter']

    app.router.add_get('/api/ws', websocket_handler)
    app.router.add_post('/api/client-errors', frontend_error_handler)
    app.add_subapp('/api/users', create_users_app())
    app.add_subapp('/api/social', create_social_app())
    _configure_web_routes(app)

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

    async def close_push(_app):
        shutdown = getattr(app['push'], 'shutdown', None)
        if shutdown is not None:
            await shutdown()

    async def close_store(_app):
        await store.close()

    app.on_cleanup.append(close_push)
    app.on_cleanup.append(close_store)
    return app


def _configure_web_routes(app):
    web_root = getattr(config, 'WEB_ROOT', '')
    if not web_root:
        return

    web_dir = Path(web_root).resolve()
    index_path = web_dir / 'index.html'
    if not index_path.is_file():
        raise FileNotFoundError(f'WEB_ROOT does not contain index.html: {web_dir}')

    async def serve_index(_req):
        return web.FileResponse(index_path)

    async def serve_web(req):
        relative_path = Path(req.match_info.get('path_info', '')).as_posix().lstrip('/')
        if relative_path == 'api' or relative_path.startswith('api/'):
            raise web.HTTPNotFound()
        if any(part.startswith('.') for part in Path(relative_path).parts):
            raise web.HTTPNotFound()
        candidate = (web_dir / relative_path).resolve()
        if candidate.is_file() and candidate.is_relative_to(web_dir):
            return web.FileResponse(candidate)
        if Path(relative_path).suffix:
            raise web.HTTPNotFound()
        return await serve_index(req)

    app.router.add_get('/', serve_index)
    app.router.add_get('/{path_info:.*}', serve_web)


if __name__ == '__main__':
    uvloop.install()
    loop = asyncio.get_event_loop()
    web.run_app(
        loop.run_until_complete(create_app()),
        host=config.BIND_HOST,
        port=config.PORT,
        handle_signals=False,
        loop=loop,
    )
