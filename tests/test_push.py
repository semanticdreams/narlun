from app.push import PushService
from tests.helpers import join_user, signup


async def test_push_delivery_skips_users_with_active_websocket_presence(
    cli,
    monkeypatch,
):
    monkeypatch.setattr('config.PUSH_VAPID_PUBLIC_KEY', 'public-key')
    monkeypatch.setattr('config.PUSH_VAPID_PRIVATE_KEY', 'private-key')
    monkeypatch.setattr('config.PUSH_VAPID_SUBJECT', 'mailto:test@example.com')

    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])
    invite_room = await cli.app['store']._add_user_to_room(
        room['id'],
        users[2]['user']['id'],
        inviter_id=users[0]['user']['id'],
    )
    assert invite_room['room']['id'] == room['id']

    for user in users[1:]:
        await cli.app['store'].upsert_push_subscription(
            user['user']['id'],
            {
                'endpoint': f'https://push.example.test/{user["user"]["id"]}',
                'keys': {'p256dh': 'p256dh', 'auth': 'auth'},
                'client_id': f'client-{user["user"]["id"]}',
            },
            client_id=f'client-{user["user"]["id"]}',
        )

    await cli.app['store'].set_room_push_muted(
        users[2]['user']['id'],
        room['id'],
        push_muted=True,
    )
    await cli.app['store'].mark_active_websocket(
        users[1]['user']['id'],
        'socket-1',
        client_id=f'client-{users[1]["user"]["id"]}',
    )

    delivered = []

    def fake_send_web_push(subscription, payload):
        delivered.append((subscription['user_id'], payload))

    monkeypatch.setattr('app.push._send_web_push', fake_send_web_push)

    push_service = PushService(cli.app['store'])
    message = await cli.app['store'].send_message(
        users[0]['user']['id'],
        room['id'],
        'hello',
    )
    await push_service.notify_new_message(users[0]['user']['id'], room['id'], message)
    assert delivered == []

    await cli.app['store'].clear_active_websocket(
        users[1]['user']['id'],
        'socket-1',
        client_id=f'client-{users[1]["user"]["id"]}',
    )
    await push_service.notify_new_message(users[0]['user']['id'], room['id'], message)

    assert [user_id for user_id, _payload in delivered] == [users[1]['user']['id']]


async def test_join_request_push_respects_room_mute_and_request_approval_notifies_requester(
    cli,
    monkeypatch,
):
    monkeypatch.setattr('config.PUSH_VAPID_PUBLIC_KEY', 'public-key')
    monkeypatch.setattr('config.PUSH_VAPID_PRIVATE_KEY', 'private-key')
    monkeypatch.setattr('config.PUSH_VAPID_SUBJECT', 'mailto:test@example.com')

    users = [await signup(cli) for _ in range(3)]
    room = await join_user(cli, users[0]['jwt'], users[1]['user']['id'])

    for user in users:
        await cli.app['store'].upsert_push_subscription(
            user['user']['id'],
            {
                'endpoint': f'https://push.example.test/{user["user"]["id"]}',
                'keys': {'p256dh': 'p256dh', 'auth': 'auth'},
                'client_id': f'client-{user["user"]["id"]}',
            },
            client_id=f'client-{user["user"]["id"]}',
        )

    await cli.app['store'].set_room_push_muted(
        users[1]['user']['id'],
        room['id'],
        push_muted=True,
    )

    delivered = []

    def fake_send_web_push(subscription, payload):
        delivered.append((subscription['user_id'], payload))

    monkeypatch.setattr('app.push._send_web_push', fake_send_web_push)

    push_service = PushService(cli.app['store'])
    await push_service.notify_room_join_request(
        users[2]['user']['id'],
        room['id'],
        [users[0]['user']['id'], users[1]['user']['id']],
    )

    assert [user_id for user_id, _payload in delivered] == [users[0]['user']['id']]

    delivered.clear()
    await push_service.notify_room_request_approved(users[2]['user']['id'], room['id'])

    assert [user_id for user_id, _payload in delivered] == [users[2]['user']['id']]
