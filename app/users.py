import datetime
import logging

import jwt
from aiohttp import web

import config
from app.redis_store import StatusTooLong, UserNotFound, UsernameAlreadyExists
from app.util import InvalidUsage, authenticated, is_request_secure, jsonify, no_content
from app.websocket import notify_local_signout


routes = web.RouteTableDef()
logger = logging.getLogger(__name__)


class UsernameExistsError(InvalidUsage):
    code = 2
    message = 'Username exists'


class PasswordTooShortError(InvalidUsage):
    code = 3
    message = 'Password must be at least 8 characters long'


class UnknownUserError(InvalidUsage):
    code = 5
    message = 'Unknown user'

    def __init__(self, **kwargs):
        self.payload = kwargs


class BadPasswordError(InvalidUsage):
    code = 6
    message = 'Bad password'


class InvalidUsernameError(InvalidUsage):
    code = 7
    message = 'Username cannot be empty'


class InvalidStatusError(InvalidUsage):
    code = 9
    message = 'Status must be 80 characters or fewer'


class InvalidAvatarError(InvalidUsage):
    code = 8
    message = 'Invalid avatar'

    def __init__(self, message):
        self.message = message


def issue_auth_cookie(req, resp, user):
    token = jwt.encode(
        {
            'sub': str(user['id']),
            'iat': datetime.datetime.now(datetime.timezone.utc),
        },
        config.SECRET_KEY,
    )
    resp.set_cookie('jwt', token, path='/api', httponly=True, samesite='Lax', secure=is_request_secure(req))
    return resp


@routes.get('/me')
async def get_me(req):
    return jsonify(req.user)


@routes.post('/signup')
async def signup(req):
    try:
        user = await req.store.create_guest_user(req.data['username'])
    except KeyError:
        raise InvalidUsernameError()
    except ValueError:
        raise InvalidUsernameError()
    except UsernameAlreadyExists:
        raise UsernameExistsError()

    return issue_auth_cookie(req, jsonify(user), user)


@routes.post('/signin')
async def signin(req):
    username = req.data.get('username', '')
    password = req.data.get('password', '')
    user = await req.store.authenticate(username, password)
    if user is None:
        raise UnknownUserError(username=username)
    if user is False:
        raise BadPasswordError()
    return issue_auth_cookie(req, jsonify(user), user)


@routes.post('/update-profile')
@authenticated
async def update_profile(req):
    password = req.data.get('password')
    if password is not None and len(password) < 8:
        raise PasswordTooShortError()

    try:
        user = await req.store.update_user(
            req.user['id'],
            username=req.data.get('username'),
            password=password,
            status=req.data.get('status'),
        )
    except ValueError:
        raise InvalidUsernameError()
    except StatusTooLong:
        raise InvalidStatusError()
    except UsernameAlreadyExists:
        raise UsernameExistsError()
    except UserNotFound:
        raise UnknownUserError(id=req.user['id'])

    return jsonify(user)


@routes.post('/upload-profile-picture')
@authenticated
async def upload_profile_picture(req):
    data = await req.post()
    uploaded = data.get('file')
    if uploaded is None:
        raise InvalidAvatarError('Missing file')

    raw_bytes = uploaded.file.read()
    try:
        picture = await req.store.normalize_and_store_avatar(req.user['id'], raw_bytes)
    except UserNotFound:
        raise UnknownUserError(id=req.user['id'])
    except ValueError as exc:
        raise InvalidAvatarError(str(exc))

    return jsonify({'picture': picture})


@routes.get(r'/avatar/{user_id:\d+}')
async def get_avatar(req):
    user_id = int(req.match_info['user_id'])
    try:
        data, content_type = await req.store.get_avatar(user_id)
    except UserNotFound:
        raise web.HTTPNotFound()
    return web.Response(body=data, content_type=content_type)


@routes.post('/signout')
async def signout(req):
    resp = no_content()
    resp.del_cookie('jwt', path='/api')
    if req.user.get('authenticated'):
        await notify_local_signout(req.user['id'])
        try:
            await req.store.publish_signout(req.user['id'])
        except Exception:
            logger.exception('Failed to publish signout event', extra={'user_id': req.user['id']})
        if not req.user['has_password']:
            await req.store.delete_account(req.user['id'])
    return resp


@routes.delete('/me')
@authenticated
async def delete_account(req):
    await notify_local_signout(req.user['id'])
    try:
        await req.store.publish_signout(req.user['id'])
    except Exception:
        logger.exception('Failed to publish delete-account signout event', extra={'user_id': req.user['id']})
    await req.store.delete_account(req.user['id'])
    resp = no_content()
    resp.del_cookie('jwt', path='/api')
    return resp


def create_app():
    app = web.Application()
    app.add_routes(routes)
    return app
