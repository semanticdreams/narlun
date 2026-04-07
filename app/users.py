import datetime
import logging
from typing import Any

import jwt
from aiohttp import web

import config
from app.feedback import MAX_FEEDBACK_MESSAGE_CHARS, build_feedback_event
from app.observability import request_log_context
from app.push import InvalidPushSubscriptionError, normalized_client_id
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


class InvalidPushSubscriptionErrorResponse(InvalidUsage):
    code = 10
    message = 'Invalid push subscription'

    def __init__(self, message=None):
        if message is not None:
            self.message = message


class MissingFeedbackMessageError(InvalidUsage):
    code = 12
    message = 'Feedback message is required'


class FeedbackMessageTooLongError(InvalidUsage):
    code = 13
    message = f'Feedback message must be {MAX_FEEDBACK_MESSAGE_CHARS} characters or fewer'


class InvalidInstallSessionError(InvalidUsage):
    code = 14
    message = 'Invalid install session'


def _coerce_uploaded_file_bytes(payload: Any) -> bytes:
    if isinstance(payload, memoryview):
        return payload.tobytes()
    if isinstance(payload, (bytes, bytearray)):
        return bytes(payload)
    raise InvalidAvatarError('Invalid file upload')


def read_uploaded_file_bytes(uploaded: Any) -> bytes:
    if isinstance(uploaded, web.FileField):
        return _coerce_uploaded_file_bytes(uploaded.file.read())
    if isinstance(uploaded, (bytes, bytearray, memoryview)):
        return _coerce_uploaded_file_bytes(uploaded)

    fileobj = getattr(uploaded, 'file', None)
    if fileobj is not None:
        return _coerce_uploaded_file_bytes(fileobj.read())

    raise InvalidAvatarError('Invalid file upload')


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


def _sanitize_install_next_route(value):
    if not isinstance(value, str):
        return None
    route = value.strip()
    if not route or not route.startswith('/'):
        return None
    if route.startswith('//'):
        return None
    return route


async def publish_public_profile_updates(req, user_id, *, include_room_nearby_viewers=False):
    targets = await req.store.get_public_profile_update_targets(
        user_id,
        include_room_nearby_viewers=include_room_nearby_viewers,
    )
    if targets['room_member_ids']:
        await req.store.publish_rooms_changed(targets['room_member_ids'])
    if targets['nearby_viewer_ids']:
        await req.store.publish_nearby_changed(targets['nearby_viewer_ids'])
    for room_id in targets['pending_request_room_ids']:
        await req.store.publish_room_requests_changed(room_id)


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

    await publish_public_profile_updates(req, req.user['id'])
    return jsonify(user)


@routes.post('/upload-profile-picture')
@authenticated
async def upload_profile_picture(req):
    data = await req.post()
    uploaded = data.get('file')
    if uploaded is None:
        raise InvalidAvatarError('Missing file')

    raw_bytes = read_uploaded_file_bytes(uploaded)
    try:
        picture = await req.store.normalize_and_store_avatar(req.user['id'], raw_bytes)
    except UserNotFound:
        raise UnknownUserError(id=req.user['id'])
    except ValueError as exc:
        raise InvalidAvatarError(str(exc))

    await publish_public_profile_updates(
        req,
        req.user['id'],
        include_room_nearby_viewers=True,
    )
    return jsonify({'picture': picture})


@routes.get('/push-config')
@authenticated
async def get_push_config(req):
    logger.info(
        'Served push config',
        extra={'user_id': req.user['id'], 'push_enabled': req.push.enabled},
    )
    return jsonify(req.push.client_config())


@routes.post('/install-session')
@authenticated
async def create_install_session(req):
    install_session = await req.store.create_install_session(req.user['id'])
    next_route = _sanitize_install_next_route(req.data.get('next_route'))
    claim_url = req.url.with_path('/').with_query({
        'install_session': install_session['token'],
        **({'next': next_route} if next_route is not None else {}),
    })
    logger.info(
        'Created install session handoff',
        extra={
            'user_id': req.user['id'],
            'next_route': next_route,
            'expires_at': install_session['expires_at'],
        },
    )
    return jsonify({
        'claim_url': str(claim_url),
        'expires_at': install_session['expires_at'],
    })


@routes.post('/claim-install-session')
async def claim_install_session(req):
    token = req.data.get('token')
    if not isinstance(token, str) or not token.strip():
        raise InvalidInstallSessionError()

    user = await req.store.consume_install_session(token.strip())
    if user is None:
        raise InvalidInstallSessionError()

    logger.info(
        'Claimed install session handoff',
        extra={'user_id': user['id']},
    )
    return issue_auth_cookie(req, jsonify(user), user)


@routes.post('/push-subscriptions')
@authenticated
async def create_push_subscription(req):
    if req.push.enabled is not True:
        logger.warning(
            'Rejected push subscription because push is disabled',
            extra={'user_id': req.user['id']},
        )
        return jsonify({'enabled': False, 'saved': False})
    subscription = req.data.get('subscription')
    if isinstance(subscription, dict):
        subscription = {
            **subscription,
            'client_id': normalized_client_id(req.data.get('client_id')),
        }
    try:
        await req.push.save_subscription(
            req.user['id'],
            subscription,
            user_agent=req.headers.get('User-Agent', ''),
        )
    except InvalidPushSubscriptionError as exc:
        logger.warning(
            'Rejected invalid push subscription payload',
            extra={'user_id': req.user['id'], 'error': str(exc)},
        )
        raise InvalidPushSubscriptionErrorResponse(str(exc))
    logger.info(
        'Saved push subscription',
        extra={
            'user_id': req.user['id'],
            'endpoint': subscription.get('endpoint') if isinstance(subscription, dict) else None,
        },
    )
    return no_content()


@routes.delete('/push-subscriptions')
@authenticated
async def delete_push_subscription(req):
    endpoint = req.data.get('endpoint', '')
    await req.push.delete_subscription(req.user['id'], endpoint)
    logger.info(
        'Deleted push subscription',
        extra={'user_id': req.user['id'], 'endpoint': endpoint},
    )
    return no_content()


@routes.post('/feedback')
@authenticated
async def submit_feedback(req):
    message = req.data.get('message')
    if not isinstance(message, str) or not message.strip():
        raise MissingFeedbackMessageError()
    normalized_message = message.strip()
    if len(normalized_message) > MAX_FEEDBACK_MESSAGE_CHARS:
        raise FeedbackMessageTooLongError()

    event = build_feedback_event(
        req,
        message=normalized_message,
        source=req.data.get('source'),
        route=req.data.get('route'),
        details=req.data.get('details'),
        app=req.data.get('app'),
        env=req.data.get('env'),
        release=req.data.get('release'),
        user_agent=req.data.get('user_agent'),
        screen=req.data.get('screen'),
    )
    await req.config_dict['feedback_log_writer'].write(event)
    logger.info(
        'Logged user feedback',
        extra=request_log_context(
            req,
            feedback_source=event.get('source'),
            feedback_route=event.get('route'),
        ),
    )
    return no_content()


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
        if req.data.get('push_endpoint'):
            await req.push.delete_subscription(req.user['id'], req.data['push_endpoint'])
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
