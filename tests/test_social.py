import app.redis_store as redis_store
from tests.helpers import (
    BERLIN,
    HAMBURG,
    MADRID,
    checkin,
    create_group_room,
    get_messages,
    get_rooms,
    join_user,
    send_message,
    signup,
)


async def test_nearby_users_exclude_shared_rooms(cli):
    users = [await signup(cli) for _ in range(3)]

    await checkin(cli, users[0]['jwt'], HAMBURG)
    nearby = await checkin(cli, users[1]['jwt'], MADRID)
    assert nearby['nearby_users'][0]['id'] == users[0]['user']['id']

    nearby = await checkin(cli, users[2]['jwt'], BERLIN)
    nearby_ids = [user['id'] for user in nearby['nearby_users']]
    assert users[0]['user']['id'] in nearby_ids
    assert users[1]['user']['id'] in nearby_ids

    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    assert room['id']

    nearby = await checkin(cli, users[0]['jwt'], HAMBURG)
    nearby_ids = [user['id'] for user in nearby['nearby_users']]
    assert users[1]['user']['id'] not in nearby_ids
    assert users[2]['user']['id'] in nearby_ids


async def test_dm_rooms_messages_and_group_rooms(cli):
    users = [await signup(cli) for _ in range(3)]

    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    await send_message(cli, users[0]['jwt'], room['id'], 'hello there')

    rooms = await get_rooms(cli, users[0]['jwt'])
    assert rooms[0]['id'] == room['id']
    assert rooms[0]['last_message']['body'] == 'hello there'

    messages_response = await get_messages(cli, users[0]['jwt'], room['id'])
    assert messages_response.status == 200
    messages = await messages_response.json()
    assert messages[0]['body'] == 'hello there'

    group_room = await create_group_room(
        cli,
        users[0]['jwt'],
        'group',
        [users[1]['user']['id'], users[2]['user']['id']],
    )
    rooms = await get_rooms(cli, users[2]['jwt'])
    assert any(room['id'] == group_room['id'] and room['is_group'] for room in rooms)


async def test_message_expiry_after_seven_days(cli, monkeypatch):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    original_time = redis_store.time.time
    base_time = original_time()

    monkeypatch.setattr(redis_store.time, 'time', lambda: base_time - (8 * 24 * 60 * 60))
    await send_message(cli, users[0]['jwt'], room['id'], 'old message')

    monkeypatch.setattr(redis_store.time, 'time', lambda: base_time)
    await send_message(cli, users[0]['jwt'], room['id'], 'fresh message')

    response = await get_messages(cli, users[0]['jwt'], room['id'])
    assert response.status == 200
    messages = await response.json()
    assert [message['body'] for message in messages] == ['fresh message']


async def test_message_ordering_within_one_second(cli, monkeypatch):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    values = iter([1000001, 1000002])
    monkeypatch.setattr(redis_store, 'now_ms', lambda: next(values))

    await send_message(cli, users[0]['jwt'], room['id'], 'first')
    await send_message(cli, users[0]['jwt'], room['id'], 'second')

    monkeypatch.setattr(redis_store, 'now_ms', lambda: 1000003)
    response = await get_messages(cli, users[0]['jwt'], room['id'])
    assert response.status == 200
    messages = await response.json()
    assert [message['body'] for message in messages[:2]] == ['second', 'first']
