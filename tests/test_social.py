import app.redis_store as redis_store
from tests.helpers import (
    accept_invite,
    approve_room_request,
    BERLIN,
    HAMBURG,
    MADRID,
    checkin,
    create_invite,
    create_group_room,
    get_room_requests,
    get_messages,
    get_rooms,
    join_user,
    request_room_join,
    reject_room_request,
    send_message,
    signup,
)


class FakePushService:
    enabled = True

    def __init__(self):
        self.room_created_calls = []
        self.room_joined_calls = []
        self.room_join_request_calls = []
        self.room_request_approved_calls = []
        self.room_request_rejected_calls = []
        self.new_message_calls = []

    async def notify_room_created(self, actor_id, room_id, recipient_ids):
        self.room_created_calls.append((actor_id, room_id, list(recipient_ids)))

    async def notify_room_joined(self, joined_user_id, room_id, recipient_ids):
        self.room_joined_calls.append((joined_user_id, room_id, list(recipient_ids)))

    async def notify_new_message(self, sender_id, room_id, message):
        self.new_message_calls.append((sender_id, room_id, message))

    async def notify_room_join_request(self, requester_id, room_id, recipient_ids):
        self.room_join_request_calls.append((requester_id, room_id, list(recipient_ids)))

    async def notify_room_request_approved(self, requester_id, room_id):
        self.room_request_approved_calls.append((requester_id, room_id))

    async def notify_room_request_rejected(self, requester_id, room_id):
        self.room_request_rejected_calls.append((requester_id, room_id))

    def enqueue_room_created(self, actor_id, room_id, recipient_ids):
        self.room_created_calls.append((actor_id, room_id, list(recipient_ids)))

    def enqueue_room_joined(self, joined_user_id, room_id, recipient_ids):
        self.room_joined_calls.append((joined_user_id, room_id, list(recipient_ids)))

    def enqueue_new_message(self, sender_id, room_id, message):
        self.new_message_calls.append((sender_id, room_id, message))

    def enqueue_room_join_request(self, requester_id, room_id, recipient_ids):
        self.room_join_request_calls.append((requester_id, room_id, list(recipient_ids)))

    def enqueue_room_request_approved(self, requester_id, room_id):
        self.room_request_approved_calls.append((requester_id, room_id))

    def enqueue_room_request_rejected(self, requester_id, room_id):
        self.room_request_rejected_calls.append((requester_id, room_id))


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


async def test_nearby_includes_joinable_rooms_and_requested_rooms(cli):
    users = [await signup(cli) for _ in range(4)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    await send_message(cli, users[0]['jwt'], room['id'], 'hello from nearby room')

    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], HAMBURG)
    nearby = await checkin(cli, users[2]['jwt'], HAMBURG)

    room_items = [item for item in nearby['nearby'] if item['type'] == 'room']
    assert len(room_items) == 1
    assert room_items[0]['room']['id'] == room['id']
    assert room_items[0]['room']['join_requested'] is False
    assert room_items[0]['room']['last_message']['body'] == 'hello from nearby room'
    assert room_items[0]['room']['member_count'] == 2

    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    requested = await checkin(cli, users[2]['jwt'], MADRID)
    requested_room_items = [item for item in requested['nearby'] if item['type'] == 'room']
    assert len(requested_room_items) == 1
    assert requested_room_items[0]['room']['id'] == room['id']
    assert requested_room_items[0]['room']['join_requested'] is True


async def test_requested_rooms_stay_visible_when_nearby_list_is_full(cli, monkeypatch):
    monkeypatch.setattr(redis_store, 'MAX_NEARBY_RESULTS', 1)

    users = [await signup(cli) for _ in range(4)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], HAMBURG)
    await checkin(cli, users[3]['jwt'], HAMBURG)

    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    nearby = await checkin(cli, users[2]['jwt'], HAMBURG)
    room_items = [item for item in nearby['nearby'] if item['type'] == 'room']
    assert len(nearby['nearby']) == 2
    assert len(room_items) == 1
    assert room_items[0]['room']['id'] == room['id']
    assert room_items[0]['room']['join_requested'] is True


async def test_nearby_users_legacy_list_is_not_truncated_by_room_items(cli, monkeypatch):
    monkeypatch.setattr(redis_store, 'MAX_NEARBY_RESULTS', 2)

    users = [await signup(cli) for _ in range(4)]
    await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], MADRID)
    await checkin(cli, users[3]['jwt'], BERLIN)

    nearby = await checkin(cli, users[2]['jwt'], HAMBURG)
    nearby_user_ids = {user['id'] for user in nearby['nearby_users']}

    assert [item['type'] for item in nearby['nearby']] == ['user', 'room']
    assert nearby_user_ids == {
        users[0]['user']['id'],
        users[3]['user']['id'],
    }


async def test_room_join_request_requires_member_approval(cli):
    users = [await signup(cli) for _ in range(4)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    requests_response = await get_room_requests(cli, users[0]['jwt'], room['id'])
    assert requests_response.status == 200
    requests = await requests_response.json()
    assert [request['user']['id'] for request in requests] == [users[2]['user']['id']]

    reject_response = await reject_room_request(
        cli,
        users[1]['jwt'],
        room['id'],
        users[2]['user']['id'],
    )
    assert reject_response.status == 204

    nearby = await checkin(cli, users[2]['jwt'], BERLIN)
    room_items = [item for item in nearby['nearby'] if item['type'] == 'room']
    assert room_items == []

    await request_room_join(cli, users[2]['jwt'], room['id'])
    approve_response = await approve_room_request(
        cli,
        users[1]['jwt'],
        room['id'],
        users[2]['user']['id'],
    )
    assert approve_response.status == 200
    approved_room = await approve_response.json()
    participant_ids = sorted(participant['id'] for participant in approved_room['participants'])
    assert participant_ids == sorted([
        users[0]['user']['id'],
        users[1]['user']['id'],
        users[2]['user']['id'],
    ])

    user_rooms = await get_rooms(cli, users[2]['jwt'])
    assert [candidate['id'] for candidate in user_rooms] == [room['id']]


async def test_room_join_requests_update_room_summaries_for_members(cli):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    member_rooms = await get_rooms(cli, users[0]['jwt'])
    assert member_rooms[0]['pending_join_request_count'] == 0


async def test_room_name_snapshots_creator_status_on_creation(cli):
    created = await signup(cli)
    response = await cli.post(
        '/api/users/update-profile',
        json={'status': 'Morning coffee crew'},
        headers={'Cookie': f'jwt={created["jwt"]}'},
    )
    assert response.status == 200

    other = await signup(cli)
    room = await join_user(cli, created['jwt'], other['user']['id'])
    rooms = await get_rooms(cli, created['jwt'])
    assert rooms[0]['id'] == room['id']
    assert rooms[0]['name'] == 'Morning coffee crew'

    response = await cli.post(
        '/api/users/update-profile',
        json={'status': 'Changed later'},
        headers={'Cookie': f'jwt={created["jwt"]}'},
    )
    assert response.status == 200
    rooms = await get_rooms(cli, created['jwt'])
    assert rooms[0]['name'] == 'Morning coffee crew'


async def test_expired_join_request_clears_member_count_and_requester_pinned_room(cli, monkeypatch):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    original_time = redis_store.time.time
    base_time = original_time()
    monkeypatch.setattr(redis_store.time, 'time', lambda: base_time)

    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    member_rooms = await get_rooms(cli, users[0]['jwt'])
    assert member_rooms[0]['pending_join_request_count'] == 1

    monkeypatch.setattr(
        redis_store.time,
        'time',
        lambda: base_time + redis_store.JOIN_REQUEST_TTL_SECONDS + 1,
    )

    member_rooms = await get_rooms(cli, users[0]['jwt'])
    assert member_rooms[0]['pending_join_request_count'] == 0

    nearby = await checkin(cli, users[2]['jwt'], BERLIN)
    room_items = [item for item in nearby['nearby'] if item['type'] == 'room']
    assert room_items == []


async def test_rejected_room_reappears_after_rejection_cooldown_expires(cli, monkeypatch):
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    original_time = redis_store.time.time
    base_time = original_time()
    monkeypatch.setattr(redis_store.time, 'time', lambda: base_time)

    await checkin(cli, users[0]['jwt'], HAMBURG)
    await checkin(cli, users[1]['jwt'], HAMBURG)
    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    reject_response = await reject_room_request(
        cli,
        users[0]['jwt'],
        room['id'],
        users[2]['user']['id'],
    )
    assert reject_response.status == 204

    hidden = await checkin(cli, users[2]['jwt'], HAMBURG)
    hidden_room_items = [item for item in hidden['nearby'] if item['type'] == 'room']
    assert hidden_room_items == []

    monkeypatch.setattr(
        redis_store.time,
        'time',
        lambda: base_time + redis_store.REJECTED_JOIN_REQUEST_TTL_SECONDS + 1,
    )

    visible = await checkin(cli, users[2]['jwt'], HAMBURG)
    visible_room_items = [item for item in visible['nearby'] if item['type'] == 'room']
    assert len(visible_room_items) == 1
    assert visible_room_items[0]['room']['id'] == room['id']

    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    member_rooms = await get_rooms(cli, users[0]['jwt'])
    assert member_rooms[0]['pending_join_request_count'] == 1

    reject_response = await reject_room_request(
        cli,
        users[1]['jwt'],
        room['id'],
        users[2]['user']['id'],
    )
    assert reject_response.status == 204

    member_rooms = await get_rooms(cli, users[0]['jwt'])
    assert member_rooms[0]['pending_join_request_count'] == 0


async def test_join_request_requires_membership_for_approval_and_rejection(cli):
    users = [await signup(cli) for _ in range(4)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert response.status == 200

    approve_response = await approve_room_request(
        cli,
        users[3]['jwt'],
        room['id'],
        users[2]['user']['id'],
    )
    assert approve_response.status == 400
    approve_body = await approve_response.json()
    assert approve_body['code'] == 1000

    reject_response = await reject_room_request(
        cli,
        users[3]['jwt'],
        room['id'],
        users[2]['user']['id'],
    )
    assert reject_response.status == 400
    reject_body = await reject_response.json()
    assert reject_body['code'] == 1000


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


async def test_user_invite_accept_creates_direct_room(cli):
    users = [await signup(cli) for _ in range(2)]

    invite = await create_invite(cli, users[0]['jwt'])
    response = await accept_invite(cli, users[1]['jwt'], invite['token'])
    assert response.status == 200
    room = await response.json()

    assert room['is_group'] is False
    participant_ids = sorted(participant['id'] for participant in room['participants'])
    assert participant_ids == sorted([users[0]['user']['id'], users[1]['user']['id']])


async def test_room_invite_adds_user_and_converts_dm_to_group(cli):
    users = [await signup(cli) for _ in range(3)]
    dm_room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    invite = await create_invite(cli, users[0]['jwt'], room_id=dm_room['id'])

    response = await accept_invite(cli, users[2]['jwt'], invite['token'])
    assert response.status == 200
    room = await response.json()

    assert room['id'] == dm_room['id']
    assert room['is_group'] is True
    participant_ids = sorted(participant['id'] for participant in room['participants'])
    assert participant_ids == sorted(user['user']['id'] for user in users)

    recreated = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    assert recreated['id'] != dm_room['id']


async def test_invite_requires_valid_token(cli):
    created = await signup(cli)

    response = await accept_invite(cli, created['jwt'], 'invalid-token')
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 1004


async def test_room_push_mute_settings_round_trip(cli):
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    response = await cli.post(
        '/api/social/update-room-settings',
        json={'room_id': room['id'], 'push_muted': True},
        headers={'Cookie': f'jwt={users[0]["jwt"]}'},
    )
    assert response.status == 200
    updated_room = await response.json()
    assert updated_room['push_muted'] is True

    owner_rooms = await get_rooms(cli, users[0]['jwt'])
    other_rooms = await get_rooms(cli, users[1]['jwt'])
    assert owner_rooms[0]['push_muted'] is True
    assert other_rooms[0]['push_muted'] is False


async def test_send_message_requests_push_delivery(cli_factory):
    fake_push = FakePushService()
    cli = await cli_factory(push_service=fake_push)
    users = [await signup(cli) for _ in range(2)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    message = await send_message(cli, users[0]['jwt'], room['id'], 'hello')

    assert fake_push.new_message_calls == [
        (users[0]['user']['id'], room['id'], message),
    ]


async def test_room_creation_and_invite_accept_request_push_delivery(cli_factory):
    fake_push = FakePushService()
    cli = await cli_factory(push_service=fake_push)
    users = [await signup(cli) for _ in range(4)]

    dm_room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    assert fake_push.room_created_calls == [
        (users[0]['user']['id'], dm_room['id'], [users[1]['user']['id']]),
    ]

    group_room = await create_group_room(
        cli,
        users[0]['jwt'],
        'group',
        [users[1]['user']['id'], users[2]['user']['id']],
    )
    assert fake_push.room_created_calls[-1] == (
        users[0]['user']['id'],
        group_room['id'],
        [users[1]['user']['id'], users[2]['user']['id']],
    )

    invite = await create_invite(cli, users[0]['jwt'], room_id=group_room['id'])
    response = await accept_invite(cli, users[3]['jwt'], invite['token'])
    assert response.status == 200
    assert fake_push.room_joined_calls[-1] == (
        users[3]['user']['id'],
        group_room['id'],
        [users[0]['user']['id'], users[1]['user']['id'], users[2]['user']['id']],
    )


async def test_join_request_lifecycle_requests_push_delivery(cli_factory):
    fake_push = FakePushService()
    cli = await cli_factory(push_service=fake_push)
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    request_response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert request_response.status == 200
    assert fake_push.room_join_request_calls == [
        (
            users[2]['user']['id'],
            room['id'],
            [users[0]['user']['id'], users[1]['user']['id']],
        ),
    ]

    approve_response = await approve_room_request(
        cli,
        users[0]['jwt'],
        room['id'],
        users[2]['user']['id'],
    )
    assert approve_response.status == 200
    assert fake_push.room_request_approved_calls == [
        (users[2]['user']['id'], room['id']),
    ]

    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    request_response = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert request_response.status == 200

    reject_response = await reject_room_request(
        cli,
        users[1]['jwt'],
        room['id'],
        users[2]['user']['id'],
    )
    assert reject_response.status == 204
    assert fake_push.room_request_rejected_calls[-1] == (
        users[2]['user']['id'],
        room['id'],
    )


async def test_duplicate_join_request_does_not_request_duplicate_push_delivery(cli_factory):
    fake_push = FakePushService()
    cli = await cli_factory(push_service=fake_push)
    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    first = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert first.status == 200
    second = await request_room_join(cli, users[2]['jwt'], room['id'])
    assert second.status == 200

    assert fake_push.room_join_request_calls == [
        (
            users[2]['user']['id'],
            room['id'],
            [users[0]['user']['id'], users[1]['user']['id']],
        ),
    ]


async def test_reopening_existing_dm_does_not_request_push_delivery(cli_factory):
    fake_push = FakePushService()
    cli = await cli_factory(push_service=fake_push)
    users = [await signup(cli) for _ in range(2)]

    await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    fake_push.room_created_calls.clear()

    await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    assert fake_push.room_created_calls == []


async def test_accepting_invite_twice_does_not_request_duplicate_push(cli_factory):
    fake_push = FakePushService()
    cli = await cli_factory(push_service=fake_push)
    users = [await signup(cli) for _ in range(4)]
    group_room = await create_group_room(
        cli,
        users[0]['jwt'],
        'group',
        [users[1]['user']['id'], users[2]['user']['id']],
    )
    invite = await create_invite(cli, users[0]['jwt'], room_id=group_room['id'])

    first = await accept_invite(cli, users[3]['jwt'], invite['token'])
    assert first.status == 200
    fake_push.room_joined_calls.clear()

    second = await accept_invite(cli, users[3]['jwt'], invite['token'])
    assert second.status == 200
    assert fake_push.room_joined_calls == []


async def test_reaccepting_room_invite_preserves_viewer_push_muted_state(cli):
    users = [await signup(cli) for _ in range(3)]
    group_room = await create_group_room(
        cli,
        users[0]['jwt'],
        'group',
        [users[1]['user']['id']],
    )
    invite = await create_invite(cli, users[0]['jwt'], room_id=group_room['id'])

    first = await accept_invite(cli, users[2]['jwt'], invite['token'])
    assert first.status == 200

    response = await cli.post(
        '/api/social/update-room-settings',
        json={'room_id': group_room['id'], 'push_muted': True},
        headers={'Cookie': f'jwt={users[2]["jwt"]}'},
    )
    assert response.status == 200

    second = await accept_invite(cli, users[2]['jwt'], invite['token'])
    assert second.status == 200
    room = await second.json()
    assert room['push_muted'] is True
