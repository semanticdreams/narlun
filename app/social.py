import asyncio
import json
from aiohttp import web

from app.util import authenticated, jsonify, JSONEncoder, InvalidUsage  # , get_logger


# logger = get_logger()

routes = web.RouteTableDef()


class NoSuchRoomError(InvalidUsage):
    code = 1000
    message = 'No such room'


class EmptyBodyError(InvalidUsage):
    code = 1001
    message = 'Empty message body'


def geog_from_coors(lon, lat):
    lon, lat = float(lat), float(lon)
    geog = f'POINT ({lon} {lat})'
    return geog


@routes.post('/checkin')
@authenticated
async def checkin(req):
    """Process current location and return nearby users."""
    geog = geog_from_coors(req.data['lon'], req.data['lat'])

    f1 = req.db.execute('insert into user_checkins (user_id, geog) values ($1, $2)',
                        req.user['id'], geog)
    f2 = req.db.execute('update users set last_geog = $2, last_seen = now()'
                        ' where id = $1',
                        req.user['id'], geog)

    await asyncio.gather(f1, f2)

    # TODO f1 doesn't need to be awaited
    # and the other 2 requests can run at once

    users = await req.db.fetch(
        'select id, username, picture, about_me,'
        ' last_geog, last_seen,'
        '  ST_DistanceSphere(last_geog::geometry, $2::geometry) as distance from users'
        ' where last_seen > now() - interval \'3 days\''
        '  and id != $1 and last_geog is not null'
        '  and id not in (select user_id from participants'
        '    where room_id in (select room_id from participants where user_id = $1))'
        ' order by last_geog <-> $2, last_seen desc'
        ' limit 10',
        req.user['id'], geog)

    def proc_user(u):
        r = dict(u)
        r.pop('last_geog')
        r['distance'] = round(r['distance'], -1)
        return r

    result = {
        'nearby_users': [proc_user(u) for u in users]
    }

    return jsonify(result)


@routes.post('/join-user')
@authenticated
async def join_user(req):
    """Create chat room with other user."""
    room = await req.db.fetchrow(
        'select r.id from rooms r'
        ' join participants p1 on p1.room_id = r.id'
        ' join participants p2 on p2.room_id = r.id'
        ' where p1.user_id = $1 and p2.user_id = $2',
        req.user['id'], req.data['user_id'])

    # TODO check this for RC

    # TODO need to add some permission system
    # so users can't message random users
    # either by including a signed token in /checkin
    # or by checking geo distance here
    # or by saving users connected by geo distance in /checkin to a new table

    if room is None:
        async with req.db.acquire() as con:
            async with con.transaction():
                room = await con.fetchrow(
                    'insert into rooms default values returning id')
                for user_id in [req.user['id'], req.data['user_id']]:
                    await con.execute(
                        'insert into participants (room_id, user_id) values ($1, $2)',
                        room['id'], user_id)

    return jsonify(room)


@routes.post('/send-message')
@authenticated
async def send_message(req):
    """Post a message to a chat room."""
    room_id = req.data['room_id']
    body = req.data['body']
    sender_id = req.user['id']

    if not body:
        raise EmptyBodyError()

    # TODO test this
    participants = await req.db.fetchrow(
        'select 1 from participants where room_id = $1 and user_id = $2',
        room_id, sender_id)
    if participants is None:
        raise NoSuchRoomError()

    message = dict(await req.db.fetchrow(
        'insert into messages (sender_id, room_id, body)'
        ' values ($1, $2, $3) returning timestamp',
        sender_id, room_id, body))
    message['body'] = body
    message['sender_id'] = sender_id
    await req.redis.publish(f'narlun:rooms:{room_id}',
                            json.dumps(
                                {'type': 'new-messages',
                                 'messages': [message],
                                 'room_id': room_id},
                                cls=JSONEncoder))
    return jsonify(message)


@routes.get('/get-rooms')
@authenticated
async def get_rooms(req):
    """Return chat rooms that user is participant of."""
    rooms = await req.db.fetch(
        'select r.id, r.name, r.last_message, r.updated_at, r.picture, r.is_group,'
        '   json_agg(json_build_object(\'id\', u.id, \'username\','
        '      u.username, \'picture\', u.picture)) as participants'
        '  from rooms r'
        ' join participants p on p.room_id = r.id'
        ' join users u on p.user_id = u.id'
        ' where r.id in (select room_id from participants where user_id = $1)'
        ' group by r.id'
        ' order by r.updated_at desc'
        ' limit 30',
        req.user['id'])
    rooms = [dict(x) for x in rooms]
    for room in rooms:
        room['participants'] = json.loads(room['participants'])
    return jsonify(rooms)


@routes.post('/get-messages')
@authenticated
async def get_messages(req):
    """Return messages of a chat room."""
    # TODO check permission for this room (is participant)
    messages = await req.db.fetch(
        'select body, timestamp, sender_id from messages'
        ' where room_id = $1'
        ' order by timestamp desc'
        ' limit 20',
        req.data['room_id'])
    return jsonify(messages)


def create_app():
    app = web.Application()
    app.add_routes(routes)
    return app
