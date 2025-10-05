import asyncio
from tests.helpers import random_username


BERLIN = (52.52437, 13.41053)
HAMBURG = (53.57532, 10.01534)
MADRID = (40.2085, -3.713)


async def create_user(cli, username=None):
    if username is None:
        username = random_username()
    r = await cli.post('/api/users/signup',
                       json=dict(username=username))
    assert r.status == 200
    d = await r.json()
    assert d['id']
    assert (jwt := r.cookies['jwt'].value)
    return dict(id=d['id'], jwt=jwt)


async def create_users(cli, num):
    return await asyncio.gather(*[create_user(cli) for _ in range(num)])


async def checkin(cli, user, loc):
    r = await cli.post('/api/social/checkin',
                       json=dict(lat=loc[0], lon=loc[1]),
                       cookies=dict(jwt=user['jwt']))
    assert r.status == 200
    return await r.json()


async def join_user(cli, user, user2):
    r = await cli.post('/api/social/join-user',
                       json=dict(user_id=user2['id']),
                       cookies=dict(jwt=user['jwt']))
    assert r.status == 200
    return await r.json()


async def send_message(cli, user, room, body):
    r = await cli.post('/api/social/send-message',
                       json=dict(room_id=room['id'],
                                 body=body),
                       cookies=dict(jwt=user['jwt']))
    assert r.status == 200
    return await r.json()


async def get_rooms(cli, user):
    r = await cli.get('/api/social/get-rooms',
                      cookies=dict(jwt=user['jwt']))
    assert r.status == 200
    return await r.json()


async def get_messages(cli, user, room):
    r = await cli.post('/api/social/get-messages',
                       json=dict(room_id=room['id']),
                       cookies=dict(jwt=user['jwt']))
    assert r.status == 200
    return await r.json()


async def test_checkin(cli):
    users = await create_users(cli, 3)

    r = await checkin(cli, users[0], HAMBURG)

    r = await checkin(cli, users[1], MADRID)
    assert len(r['nearby_users']) > 0
    assert r['nearby_users'][0]['id'] == users[0]['id']

    r = await checkin(cli, users[2], BERLIN)
    assert r['nearby_users'][0]['id'] == users[0]['id']
    assert r['nearby_users'][1]['id'] == users[1]['id']

    r = await checkin(cli, users[0], HAMBURG)
    assert r['nearby_users'][0]['id'] == users[2]['id']

    room = await join_user(cli, users[0], users[1])
    assert room['id']

    r = await send_message(cli, users[0], room, 'hello there')

    rooms = await get_rooms(cli, users[0])
    assert rooms[0]['id'] == room['id']

    messages = await get_messages(cli, users[0], room)
    assert messages[0]['body'] == 'hello there'
