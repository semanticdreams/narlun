import asyncio
import json
import logging

import config


logger = logging.getLogger(__name__)


class InvalidPushSubscriptionError(ValueError):
    pass


def push_enabled():
    return bool(
        config.PUSH_VAPID_PUBLIC_KEY
        and config.PUSH_VAPID_PRIVATE_KEY
        and config.PUSH_VAPID_SUBJECT
    )


def normalize_subscription(payload):
    if not isinstance(payload, dict):
        raise InvalidPushSubscriptionError('Subscription payload must be an object')

    endpoint = payload.get('endpoint')
    if not isinstance(endpoint, str) or not endpoint.strip():
        raise InvalidPushSubscriptionError('Subscription endpoint is required')

    keys = payload.get('keys')
    if not isinstance(keys, dict):
        raise InvalidPushSubscriptionError('Subscription keys are required')

    p256dh = keys.get('p256dh')
    auth = keys.get('auth')
    if not isinstance(p256dh, str) or not p256dh.strip():
        raise InvalidPushSubscriptionError('Subscription p256dh key is required')
    if not isinstance(auth, str) or not auth.strip():
        raise InvalidPushSubscriptionError('Subscription auth key is required')

    expiration_time = payload.get('expirationTime')
    if expiration_time is not None and not isinstance(expiration_time, (int, float)):
        expiration_time = None

    return {
        'endpoint': endpoint.strip(),
        'expirationTime': expiration_time,
        'keys': {
            'p256dh': p256dh.strip(),
            'auth': auth.strip(),
        },
    }


class PushService:
    def __init__(self, store):
        self.store = store
        self._background_tasks = set()

    @property
    def enabled(self):
        return push_enabled()

    def client_config(self):
        return {
            'enabled': self.enabled,
            'vapid_public_key': config.PUSH_VAPID_PUBLIC_KEY if self.enabled else None,
        }

    async def save_subscription(self, user_id, subscription, *, user_agent=''):
        if not self.enabled:
            logger.warning(
                'Skipped saving push subscription because push is disabled',
                extra={'user_id': int(user_id)},
            )
            return False
        normalized = normalize_subscription(subscription)
        await self.store.upsert_push_subscription(
            int(user_id),
            normalized,
            user_agent=user_agent,
            client_id=normalized_client_id(subscription.get('client_id')),
        )
        logger.info(
            'Stored push subscription',
            extra={
                'user_id': int(user_id),
                'endpoint': normalized['endpoint'],
                'client_id': normalized_client_id(subscription.get('client_id')),
            },
        )
        return True

    async def delete_subscription(self, user_id, endpoint):
        if not endpoint:
            logger.warning(
                'Skipped deleting push subscription because endpoint was empty',
                extra={'user_id': int(user_id)},
            )
            return False
        removed = await self.store.remove_push_subscription(int(user_id), endpoint)
        logger.info(
            'Deleted push subscription from store',
            extra={
                'user_id': int(user_id),
                'endpoint': endpoint,
                'removed': removed,
            },
        )
        return removed

    async def notify_room_created(self, actor_id, room_id, recipient_ids):
        if not self.enabled:
            return

        room = await self.store.get_room(room_id)
        actor = await self.store.get_public_user(actor_id)
        if room is None or actor is None:
            return

        actor_username = actor.get('username') or 'Someone'
        room_name = (room.get('name') or '').strip()
        title = f'Added to {room_name}' if room_name else 'New room'
        body = (
            f'{actor_username} added you to {room_name}.'
            if room_name
            else f'{actor_username} added you to a room.'
        )

        await self._notify_users(
            recipient_ids,
            {
                'title': title,
                'body': body,
                'tag': f'room-{int(room_id)}',
                'data': {
                    'url': f'/rooms?open_room={int(room_id)}',
                    'room_id': int(room_id),
                    'type': 'room-created',
                },
            },
        )

    async def notify_room_joined(self, joined_user_id, room_id, recipient_ids):
        if not self.enabled:
            return

        room = await self.store.get_room(room_id)
        joined_user = await self.store.get_public_user(joined_user_id)
        if room is None or joined_user is None:
            return

        room_name = (room.get('name') or '').strip()
        joined_username = joined_user.get('username') or 'Someone'
        title = (
            f'{joined_username} joined {room_name}'
            if room_name
            else f'{joined_username} joined the room'
        )
        filtered_recipient_ids = []
        for recipient_id in recipient_ids:
            if await self.store.get_room_push_muted(recipient_id, room_id):
                continue
            filtered_recipient_ids.append(recipient_id)

        await self._notify_users(
            filtered_recipient_ids,
            {
                'title': title,
                'body': 'Open the room to continue.',
                'tag': f'room-{int(room_id)}',
                'data': {
                    'url': f'/rooms?open_room={int(room_id)}',
                    'room_id': int(room_id),
                    'type': 'room-joined',
                },
            },
        )

    async def notify_room_join_request(self, requester_id, room_id, recipient_ids):
        if not self.enabled:
            return

        room = await self.store.get_room(room_id)
        requester = await self.store.get_public_user(requester_id)
        if room is None or requester is None:
            return

        requester_username = requester.get('username') or 'Someone'
        room_name = (room.get('name') or '').strip()
        title = (
            f'{requester_username} wants to join {room_name}'
            if room_name
            else f'{requester_username} wants to join your room'
        )
        filtered_recipient_ids = []
        for recipient_id in recipient_ids:
            if await self.store.get_room_push_muted(recipient_id, room_id):
                continue
            filtered_recipient_ids.append(recipient_id)

        await self._notify_users(
            filtered_recipient_ids,
            {
                'title': title,
                'body': 'Open the room to approve or reject the request.',
                'tag': f'room-request-{int(room_id)}',
                'data': {
                    'url': f'/rooms?open_room={int(room_id)}',
                    'room_id': int(room_id),
                    'requester_id': int(requester_id),
                    'type': 'room-join-request',
                },
            },
        )

    async def notify_room_request_approved(self, requester_id, room_id):
        if not self.enabled:
            return

        room = await self.store.get_room(room_id)
        if room is None:
            return

        room_name = (room.get('name') or '').strip()
        await self._notify_users(
            [requester_id],
            {
                'title': (
                    f'Joined {room_name}'
                    if room_name
                    else 'Your room request was approved'
                ),
                'body': 'Open the room to join.',
                'tag': f'room-request-{int(room_id)}',
                'data': {
                    'url': f'/rooms?open_room={int(room_id)}',
                    'room_id': int(room_id),
                    'type': 'room-request-approved',
                },
            },
        )

    async def notify_room_request_rejected(self, requester_id, room_id):
        if not self.enabled:
            return

        room = await self.store.get_room(room_id)
        room_name = (room.get('name') or '').strip() if room is not None else ''
        await self._notify_users(
            [requester_id],
            {
                'title': (
                    f'Request declined for {room_name}'
                    if room_name
                    else 'Your room request was declined'
                ),
                'body': 'You can keep browsing nearby rooms.',
                'tag': f'room-request-{int(room_id)}',
                'data': {
                    'url': '/nearby',
                    'room_id': int(room_id),
                    'type': 'room-request-rejected',
                },
            },
        )

    async def notify_new_message(self, sender_id, room_id, message):
        if not self.enabled:
            return

        room = await self.store.get_room(room_id)
        sender = await self.store.get_public_user(sender_id)
        if room is None or sender is None:
            return

        sender_username = sender.get('username') or 'Someone'
        room_name = (room.get('name') or '').strip()
        title = f'{sender_username} in {room_name}' if room_name else sender_username

        recipient_ids = [
            member_id
            for member_id in await self.store.get_room_members(room_id)
            if int(member_id) != int(sender_id)
        ]
        filtered_recipient_ids = []
        for recipient_id in recipient_ids:
            if await self.store.get_room_push_muted(recipient_id, room_id):
                continue
            filtered_recipient_ids.append(recipient_id)

        if not filtered_recipient_ids:
            return

        await self._notify_users(
            filtered_recipient_ids,
            {
                'title': title,
                'body': (message.get('body') or 'New message').strip() or 'New message',
                'tag': f'room-{int(room_id)}',
                'data': {
                    'url': f'/rooms?open_room={int(room_id)}',
                    'room_id': int(room_id),
                    'message_id': message.get('id'),
                    'type': 'new-message',
                },
            },
        )

    async def _notify_users(self, user_ids, notification):
        subscriptions = await self.store.get_push_subscriptions_for_users(user_ids)
        if not subscriptions:
            logger.info(
                'Skipped push delivery because no subscriptions were found',
                extra={'recipient_count': len(user_ids)},
            )
            return

        tasks = []
        skipped_live_view = 0
        for subscription in subscriptions:
            if await self._should_skip_for_live_view(subscription, notification):
                skipped_live_view += 1
                continue
            tasks.append(self._send_notification(subscription, notification))
        logger.info(
            'Prepared push delivery batch',
            extra={
                'recipient_count': len(user_ids),
                'subscription_count': len(subscriptions),
                'delivery_count': len(tasks),
                'skipped_live_view_count': skipped_live_view,
                'notification_tag': notification.get('tag'),
                'notification_type': (notification.get('data') or {}).get('type'),
                'notification_room_id': (notification.get('data') or {}).get('room_id'),
                'candidate_live_views': _notification_live_views(notification),
            },
        )
        if tasks:
            await asyncio.gather(*tasks)

    async def _should_skip_for_live_view(self, subscription, notification):
        client_id = normalized_client_id(subscription.get('client_id'))
        if client_id is None:
            return False

        user_id = int(subscription['user_id'])
        for view_key in _notification_live_views(notification):
            if await self.store.has_live_view(
                user_id,
                client_id=client_id,
                view_key=view_key,
            ):
                logger.info(
                    'Skipped push delivery because client already has the relevant page open',
                    extra={
                        'user_id': user_id,
                        'client_id': client_id,
                        'view_key': view_key,
                        'notification_tag': notification.get('tag'),
                        'notification_type': (notification.get('data') or {}).get('type'),
                        'notification_room_id': (notification.get('data') or {}).get('room_id'),
                    },
                )
                return True
        return False

    def enqueue_room_created(self, actor_id, room_id, recipient_ids):
        self._enqueue(
            'room-created',
            lambda: self.notify_room_created(actor_id, room_id, recipient_ids),
        )

    def enqueue_room_joined(self, joined_user_id, room_id, recipient_ids):
        self._enqueue(
            'room-joined',
            lambda: self.notify_room_joined(joined_user_id, room_id, recipient_ids),
        )

    def enqueue_new_message(self, sender_id, room_id, message):
        self._enqueue(
            'new-message',
            lambda: self.notify_new_message(sender_id, room_id, message),
        )

    def enqueue_room_join_request(self, requester_id, room_id, recipient_ids):
        self._enqueue(
            'room-join-request',
            lambda: self.notify_room_join_request(requester_id, room_id, recipient_ids),
        )

    def enqueue_room_request_approved(self, requester_id, room_id):
        self._enqueue(
            'room-request-approved',
            lambda: self.notify_room_request_approved(requester_id, room_id),
        )

    def enqueue_room_request_rejected(self, requester_id, room_id):
        self._enqueue(
            'room-request-rejected',
            lambda: self.notify_room_request_rejected(requester_id, room_id),
        )

    def _enqueue(self, operation, coro_factory):
        if not self.enabled:
            return
        task = asyncio.create_task(self._run_background(operation, coro_factory))
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)

    async def _run_background(self, operation, coro_factory):
        try:
            await coro_factory()
        except Exception:
            logger.exception('Background push task failed', extra={'operation': operation})

    async def shutdown(self):
        if not self._background_tasks:
            return
        tasks = list(self._background_tasks)
        done, pending = await asyncio.wait(tasks, timeout=2)
        for task in pending:
            task.cancel()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)
        for task in done:
            task.result()

    async def _send_notification(self, subscription, notification):
        try:
            await asyncio.to_thread(
                _send_web_push,
                subscription,
                {'notification': _notification_payload(notification)},
            )
            logger.info(
                'Delivered web push notification',
                extra={
                    'subscription_id': subscription['id'],
                    'user_id': subscription['user_id'],
                    'endpoint': subscription['endpoint'],
                    'notification_tag': notification.get('tag'),
                    'notification_type': (notification.get('data') or {}).get('type'),
                    'notification_room_id': (notification.get('data') or {}).get('room_id'),
                },
            )
        except Exception as exc:
            response = getattr(exc, 'response', None)
            status = getattr(response, 'status_code', None) or getattr(response, 'status', None)
            if status in {404, 410}:
                await self.store.remove_push_subscription_by_id(subscription['id'])
                return
            logger.exception(
                'Failed to deliver web push notification',
                extra={
                    'subscription_id': subscription['id'],
                    'user_id': subscription['user_id'],
                    'endpoint': subscription['endpoint'],
                    'notification_tag': notification.get('tag'),
                    'notification_type': (notification.get('data') or {}).get('type'),
                    'notification_room_id': (notification.get('data') or {}).get('room_id'),
                },
            )


def _notification_payload(notification):
    payload = {
        'title': notification.get('title') or 'Narlun',
        'body': notification.get('body') or '',
        'tag': notification.get('tag') or 'narlun',
        'icon': '/icons/Icon-192.png',
        'badge': '/icons/Icon-maskable-192.png',
        'data': notification.get('data') or {},
    }
    if notification.get('renotify') is True:
        payload['renotify'] = True
    return payload


def _notification_live_views(notification):
    data = notification.get('data') or {}
    notification_type = data.get('type')
    room_id = data.get('room_id')

    if notification_type in {'new-message', 'room-join-request'}:
        try:
            return [f'room:{int(room_id)}']
        except (TypeError, ValueError):
            return []
    if notification_type in {'room-created', 'room-joined'}:
        return ['rooms']
    if notification_type in {'room-request-approved', 'room-request-rejected'}:
        return ['rooms', 'nearby']
    return []


def _send_web_push(subscription, payload):
    from pywebpush import webpush

    webpush(
        subscription_info={
            'endpoint': subscription['endpoint'],
            'keys': subscription['keys'],
        },
        data=json.dumps(payload),
        vapid_private_key=config.PUSH_VAPID_PRIVATE_KEY,
        vapid_claims={'sub': config.PUSH_VAPID_SUBJECT},
        ttl=120,
    )


def normalized_client_id(value):
    if not isinstance(value, str):
        return None
    candidate = value.strip()
    if not candidate or len(candidate) > 128:
        return None
    return candidate
