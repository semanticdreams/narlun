import logging
from urllib.parse import urlsplit, urlunsplit

from aiohttp import web

from app.observability import request_log_context, sample_values
from app.redis_store import (
    InviteNotFound,
    JoinRequestNotFound,
    PermissionDenied,
    RoomNotFound,
    UserNotFound,
)
from app.util import InvalidUsage, authenticated, jsonify


routes = web.RouteTableDef()
logger = logging.getLogger(__name__)


class NoSuchRoomError(InvalidUsage):
    code = 1000
    message = 'No such room'


class EmptyBodyError(InvalidUsage):
    code = 1001
    message = 'Empty message body'


class NoSuchUserError(InvalidUsage):
    code = 1002
    message = 'No such user'


class InvalidRoomError(InvalidUsage):
    code = 1003
    message = 'Invalid room'

    def __init__(self, message=None):
        if message is not None:
            self.message = message


class InvalidInviteError(InvalidUsage):
    code = 1004
    message = 'Invalid invite'

    def __init__(self, message=None):
        if message is not None:
            self.message = message


class InvalidRoomSettingsError(InvalidUsage):
    code = 1005
    message = 'Invalid room settings'

    def __init__(self, message=None):
        if message is not None:
            self.message = message


class InvalidJoinRequestError(InvalidUsage):
    code = 1006
    message = 'Invalid join request'

    def __init__(self, message=None):
        if message is not None:
            self.message = message


class InvalidReadReceiptError(InvalidUsage):
    code = 1007
    message = 'Invalid read receipt'


class InvalidMessageContentError(InvalidUsage):
    code = 1008
    message = 'Invalid message content'

    def __init__(self, message=None):
        if message is not None:
            self.message = message


def _normalize_whatsapp_invite_url(raw_value):
    value = (raw_value or '').strip()
    if not value:
        return None
    candidate = value if '://' in value else f'https://{value}'
    parsed = urlsplit(candidate)
    if parsed.scheme not in ('http', 'https'):
        return None
    if parsed.hostname != 'chat.whatsapp.com':
        return None
    path_parts = [part for part in parsed.path.split('/') if part]
    if len(path_parts) != 1:
        return None
    return urlunsplit(('https', 'chat.whatsapp.com', f'/{path_parts[0]}', '', ''))


def _parse_outgoing_message_payload(data):
    kind = data.get('kind') or 'text'
    if kind == 'text':
        body = data.get('body', '')
        if not body.strip():
            raise EmptyBodyError()
        return {
            'kind': 'text',
            'body': body,
            'whatsapp_group': None,
        }
    if kind == 'whatsapp_group':
        whatsapp_group = data.get('whatsapp_group')
        invite_url = ''
        if isinstance(whatsapp_group, dict):
            invite_url = whatsapp_group.get('invite_url', '')
        normalized_url = _normalize_whatsapp_invite_url(invite_url)
        if normalized_url is None:
            raise InvalidMessageContentError(
                message='WhatsApp invite link must use chat.whatsapp.com.',
            )
        return {
            'kind': 'whatsapp_group',
            'body': '',
            'whatsapp_group': {'invite_url': normalized_url},
        }
    raise InvalidMessageContentError(message='Unknown message type.')


@routes.post('/checkin')
@authenticated
async def checkin(req):
    result = await req.store.checkin(
        req.user['id'],
        lat=float(req.data['lat']),
        lon=float(req.data['lon']),
    )
    logger.info(
        'Nearby checkin completed',
        extra=request_log_context(
            req,
            nearby_item_count=len(result['nearby']),
            nearby_room_ids=sample_values(
                [item['room']['id'] for item in result['nearby'] if item['type'] == 'room'],
            ),
        ),
    )
    return jsonify(result)


@routes.post('/create-room')
@authenticated
async def create_room(req):
    try:
        room = await req.store.create_group_room(
            req.user['id'],
            name=req.data.get('name', ''),
            user_ids=req.data.get('user_ids', []),
        )
    except UserNotFound:
        raise NoSuchUserError()
    except ValueError as exc:
        raise InvalidRoomError(message=str(exc))
    await req.store.publish_rooms_changed([req.user['id'], *req.data.get('user_ids', [])])
    await _publish_room_nearby_changes(req, room['id'])
    req.push.enqueue_room_created(
        req.user['id'],
        room['id'],
        req.data.get('user_ids', []),
    )
    logger.info(
        'Created room',
        extra=request_log_context(
            req,
            room_id=room['id'],
            member_count=len({int(req.user['id']), *[int(user_id) for user_id in req.data.get('user_ids', [])]}),
            invited_user_ids=sample_values(req.data.get('user_ids', [])),
        ),
    )
    return jsonify(room)


@routes.post('/request-room-join')
@authenticated
async def request_room_join(req):
    try:
        room_id = int(req.data.get('room_id'))
    except (TypeError, ValueError):
        raise InvalidJoinRequestError()

    try:
        request_result = await req.store.request_join_room(req.user['id'], room_id)
    except RoomNotFound:
        raise NoSuchRoomError()
    except PermissionDenied:
        raise NoSuchRoomError()

    if request_result.get('created') is True:
        await req.store.publish_room_requests_changed(room_id)
        room_members = await req.store.get_room_members(room_id)
        await req.store.publish_rooms_changed(room_members)
        await req.store.publish_nearby_changed([req.user['id']])
        req.push.enqueue_room_join_request(req.user['id'], room_id, room_members)
    logger.info(
        'Requested room join',
        extra=request_log_context(
            req,
            room_id=room_id,
            join_request_created=request_result.get('created') is True,
        ),
    )
    return jsonify(request_result)


@routes.get('/get-room-requests')
@authenticated
async def get_room_requests(req):
    try:
        room_id = int(req.query.get('room_id'))
    except (TypeError, ValueError):
        raise InvalidJoinRequestError()

    try:
        requests = await req.store.get_room_join_requests(req.user['id'], room_id)
    except PermissionDenied:
        raise NoSuchRoomError()
    except RoomNotFound:
        raise NoSuchRoomError()
    logger.info(
        'Fetched room join requests',
        extra=request_log_context(
            req,
            room_id=room_id,
            request_count=len(requests),
            requester_user_ids=sample_values([item['user']['id'] for item in requests]),
        ),
    )
    return jsonify(requests)


async def _resolve_room_request_update(req):
    try:
        room_id = int(req.data.get('room_id'))
        user_id = int(req.data.get('user_id'))
    except (TypeError, ValueError):
        raise InvalidJoinRequestError()
    return room_id, user_id


async def _publish_room_nearby_changes(req, room_id, *, include_user_ids=()):
    changed_user_ids = set(await req.store.get_room_nearby_update_targets(room_id))
    changed_user_ids.update(int(user_id) for user_id in include_user_ids)
    if changed_user_ids:
        await req.store.publish_nearby_changed(changed_user_ids)


@routes.post('/approve-room-request')
@authenticated
async def approve_room_request(req):
    room_id, user_id = await _resolve_room_request_update(req)

    try:
        result = await req.store.approve_room_join_request(req.user['id'], room_id, user_id)
    except PermissionDenied:
        raise NoSuchRoomError()
    except RoomNotFound:
        raise NoSuchRoomError()
    except JoinRequestNotFound:
        raise InvalidJoinRequestError(message='Join request is no longer pending')

    room_members = await req.store.get_room_members(room_id)
    await req.store.publish_room_requests_changed(room_id)
    await req.store.publish_rooms_changed(room_members)
    await _publish_room_nearby_changes(
        req,
        room_id,
        include_user_ids=[user_id],
    )
    if result.get('membership_changed') is True:
        req.push.enqueue_room_joined(
            user_id,
            room_id,
            [member_id for member_id in room_members if member_id != user_id],
        )
        req.push.enqueue_room_request_approved(user_id, room_id)
    logger.info(
        'Approved room join request',
        extra=request_log_context(
            req,
            room_id=room_id,
            requester_user_id=user_id,
            membership_changed=result.get('membership_changed') is True,
        ),
    )
    return jsonify(result['room'])


@routes.post('/reject-room-request')
@authenticated
async def reject_room_request(req):
    room_id, user_id = await _resolve_room_request_update(req)

    try:
        await req.store.reject_room_join_request(req.user['id'], room_id, user_id)
    except PermissionDenied:
        raise NoSuchRoomError()
    except RoomNotFound:
        raise NoSuchRoomError()
    except JoinRequestNotFound:
        raise InvalidJoinRequestError(message='Join request is no longer pending')

    await req.store.publish_room_requests_changed(room_id)
    room_members = await req.store.get_room_members(room_id)
    await req.store.publish_rooms_changed(room_members)
    await req.store.publish_nearby_changed([user_id])
    req.push.enqueue_room_request_rejected(user_id, room_id)
    logger.info(
        'Rejected room join request',
        extra=request_log_context(
            req,
            room_id=room_id,
            requester_user_id=user_id,
        ),
    )
    return web.Response(status=204)


@routes.post('/leave-room')
@authenticated
async def leave_room(req):
    try:
        room_id = int(req.data.get('room_id'))
    except (TypeError, ValueError):
        raise InvalidRoomError()

    try:
        result = await req.store.leave_room(req.user['id'], room_id)
    except PermissionDenied:
        raise NoSuchRoomError()
    except RoomNotFound:
        raise NoSuchRoomError()

    await req.store.publish_rooms_changed([req.user['id'], *result['remaining_member_ids']])
    logger.info(
        'Left room',
        extra=request_log_context(
            req,
            room_id=room_id,
            room_deleted=result['room_deleted'] is True,
            remaining_member_ids=sample_values(result['remaining_member_ids']),
        ),
    )
    return web.Response(status=204)


@routes.post('/send-message')
@authenticated
async def send_message(req):
    payload = _parse_outgoing_message_payload(req.data)

    try:
        message = await req.store.send_message(
            req.user['id'],
            req.data['room_id'],
            payload['body'],
            kind=payload['kind'],
            whatsapp_group=payload['whatsapp_group'],
        )
    except PermissionDenied:
        raise NoSuchRoomError()
    except RoomNotFound:
        raise NoSuchRoomError()

    await req.store.publish_room_message(req.data['room_id'], message)
    await req.store.publish_rooms_changed(
        await req.store.get_room_members(req.data['room_id']),
    )
    await _publish_room_nearby_changes(req, req.data['room_id'])
    req.push.enqueue_new_message(req.user['id'], req.data['room_id'], message)
    logger.info(
        'Sent room message',
        extra=request_log_context(
            req,
            room_id=req.data['room_id'],
            message_id=message['id'],
            message_kind=payload['kind'],
            message_body_length=len(payload['body'].strip()),
        ),
    )
    return jsonify(message)


@routes.post('/mark-room-read')
@authenticated
async def mark_room_read(req):
    room_id = req.data.get('room_id')
    message_id = req.data.get('message_id')
    try:
        read_state = await req.store.mark_room_read(
            req.user['id'],
            room_id,
            message_id=message_id,
        )
    except PermissionDenied:
        raise NoSuchRoomError()
    except RoomNotFound:
        raise InvalidReadReceiptError(message='Message is no longer available')

    if read_state is None:
        return web.Response(status=204)

    await req.store.publish_room_read(room_id, read_state)
    logger.info(
        'Marked room read',
        extra=request_log_context(
            req,
            room_id=room_id,
            message_id=read_state['message_id'],
        ),
    )
    return jsonify(read_state)


@routes.post('/create-invite')
@authenticated
async def create_invite(req):
    try:
        room_id = int(req.data.get('room_id'))
    except (TypeError, ValueError):
        raise InvalidRoomError(message='Room invite requires a room')
    try:
        invite = await req.store.create_invite(req.user['id'], room_id=room_id)
    except RoomNotFound:
        raise NoSuchRoomError()
    except PermissionDenied:
        raise NoSuchRoomError()
    logger.info(
        'Created invite',
        extra=request_log_context(
            req,
            room_id=invite['room_id'],
        ),
    )
    return jsonify(invite)


@routes.post('/accept-invite')
@authenticated
async def accept_invite(req):
    token = req.data.get('token', '')
    if not token:
        raise InvalidInviteError()

    try:
        invite_result = await req.store.accept_invite(req.user['id'], token)
    except InviteNotFound:
        raise InvalidInviteError(message='Invite is invalid or has expired')
    except RoomNotFound:
        raise InvalidInviteError(message='Invite room is no longer available')
    except PermissionDenied as exc:
        raise InvalidInviteError(message=str(exc) or 'Invite could not be accepted')
    except UserNotFound:
        raise InvalidInviteError(message='Invite is no longer valid')

    room = invite_result['room']
    room_members = await req.store.get_room_members(room['id'])
    await req.store.publish_rooms_changed(room_members)
    if invite_result.get('membership_changed') is True:
        await _publish_room_nearby_changes(
            req,
            room['id'],
            include_user_ids=[req.user['id']],
        )
        req.push.enqueue_room_joined(
            req.user['id'],
            room['id'],
            [member_id for member_id in room_members if member_id != req.user['id']],
        )
    logger.info(
        'Accepted invite',
        extra=request_log_context(
            req,
            room_id=room['id'],
            membership_changed=invite_result.get('membership_changed') is True,
        ),
    )
    return jsonify(room)


@routes.get('/get-rooms')
@authenticated
async def get_rooms(req):
    rooms = await req.store.get_rooms(req.user['id'])
    logger.info(
        'Fetched room summaries',
        extra=request_log_context(
            req,
            room_count=len(rooms),
            room_ids=sample_values([room['id'] for room in rooms]),
        ),
    )
    return jsonify(rooms)


@routes.post('/update-room-settings')
@authenticated
async def update_room_settings(req):
    room_id = req.data.get('room_id')
    try:
        room_id = int(room_id)
    except (TypeError, ValueError):
        raise InvalidRoomSettingsError()

    push_muted = req.data.get('push_muted')
    room_name = req.data.get('name')

    has_push_muted = push_muted is not None
    has_room_name = room_name is not None
    if not has_push_muted and not has_room_name:
        raise InvalidRoomSettingsError()
    if has_push_muted and not isinstance(push_muted, bool):
        raise InvalidRoomSettingsError()
    if has_room_name and not isinstance(room_name, str):
        raise InvalidRoomSettingsError()

    try:
        if has_room_name:
            room = await req.store.set_room_name(
                req.user['id'],
                room_id,
                name=room_name,
            )
        if has_push_muted:
            room = await req.store.set_room_push_muted(
                req.user['id'],
                room_id,
                push_muted=push_muted,
            )
    except PermissionDenied:
        raise NoSuchRoomError()
    except ValueError as exc:
        raise InvalidRoomSettingsError(message=str(exc))
    except RoomNotFound:
        raise NoSuchRoomError()

    room_members = await req.store.get_room_members(room_id)
    await req.store.publish_rooms_changed(
        room_members if has_room_name else [req.user['id']],
    )
    logger.info(
        'Updated room settings',
        extra=request_log_context(
            req,
            room_id=room_id,
            push_muted=push_muted if has_push_muted else None,
            room_name=room_name.strip() if has_room_name else None,
        ),
    )
    return jsonify(room)


@routes.post('/get-messages')
@authenticated
async def get_messages(req):
    try:
        messages = await req.store.get_messages(req.user['id'], req.data['room_id'])
    except PermissionDenied:
        raise NoSuchRoomError()
    logger.info(
        'Fetched room messages',
        extra=request_log_context(
            req,
            room_id=req.data['room_id'],
            message_count=len(messages),
            message_ids=sample_values([message['id'] for message in messages]),
        ),
    )
    return jsonify(messages)


def create_app():
    app = web.Application()
    app.add_routes(routes)
    return app
