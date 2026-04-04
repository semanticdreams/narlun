import redis.asyncio as redis
import hashlib
import json
import secrets
import time
from datetime import datetime, timezone
from io import BytesIO

from PIL import Image, UnidentifiedImageError
from werkzeug.security import generate_password_hash, check_password_hash

from app.util import create_random_avatar


MESSAGE_TTL_SECONDS = 7 * 24 * 60 * 60
ACTIVE_WINDOW_SECONDS = 3 * 24 * 60 * 60
INVITE_TTL_SECONDS = 24 * 60 * 60
WEBSOCKET_PRESENCE_TTL_SECONDS = 45
MAX_NEARBY_RESULTS = 10
MAX_GEO_RESULTS = 50
MAX_ROOM_RESULTS = 30
MAX_MESSAGE_RESULTS = 20
AVATAR_SIZE = 256
MAX_AVATAR_BYTES = 2 * 1024 * 1024
MAX_AVATAR_PIXELS = 20_000_000
MAX_STATUS_LENGTH = 80


class UsernameAlreadyExists(Exception):
    pass


class UserNotFound(Exception):
    pass


class RoomNotFound(Exception):
    pass


class PermissionDenied(Exception):
    pass


class StatusTooLong(Exception):
    pass


class InviteNotFound(Exception):
    pass


def now_ts():
    return int(time.time())


def now_ms():
    return int(time.time() * 1000)


def ts_ms_to_iso(timestamp_ms):
    return datetime.fromtimestamp(
        int(timestamp_ms) / 1000,
        timezone.utc,
    ).isoformat(timespec='milliseconds')


def ts_to_iso(timestamp):
    return ts_ms_to_iso(int(timestamp) * 1000)


def normalize_username(username):
    return username.strip().lower()


def avatar_url(user_id, avatar_version):
    return f'/api/users/avatar/{user_id}?v={avatar_version}'


def room_bool(value):
    return value in {'1', 'true', 'True', True}


def normalize_status(status):
    normalized = ' '.join(status.split())
    if len(normalized) > MAX_STATUS_LENGTH:
        raise StatusTooLong()
    return normalized


class RedisStore:
    def __init__(self, redis, redis_bytes):
        self.redis = redis
        self.redis_bytes = redis_bytes

    @classmethod
    async def create(cls, redis_url):
        redis_client = redis.from_url(redis_url, decode_responses=True)
        redis_bytes_client = redis.from_url(redis_url, decode_responses=False)
        return cls(redis_client, redis_bytes_client)

    async def close(self):
        await self.redis.aclose()
        await self.redis_bytes.aclose()

    def _user_key(self, user_id):
        return f'user:{{{user_id}}}:profile'

    def _user_avatar_key(self, user_id):
        return f'user:{{{user_id}}}:avatar'

    def _user_rooms_key(self, user_id):
        return f'user:{{{user_id}}}:rooms'

    def _room_meta_key(self, room_id):
        return f'room:{{{room_id}}}:meta'

    def _room_members_key(self, room_id):
        return f'room:{{{room_id}}}:members'

    def _room_messages_key(self, room_id):
        return f'room:{{{room_id}}}:messages'

    def _user_push_subscriptions_key(self, user_id):
        return f'user:{{{user_id}}}:push_subscriptions'

    def _user_room_prefs_key(self, user_id):
        return f'user:{{{user_id}}}:room_prefs'

    def _user_websocket_presence_key(self, user_id):
        return f'user:{{{user_id}}}:websocket_presence'

    def _user_client_websocket_presence_key(self, user_id, client_id):
        client_hash = hashlib.sha256(client_id.encode('utf-8')).hexdigest()
        return f'user:{{{user_id}}}:websocket_presence:{client_hash}'

    def _push_subscription_key(self, subscription_id):
        return f'push_subscription:{subscription_id}'

    def _push_subscription_id(self, endpoint):
        return hashlib.sha256(endpoint.encode('utf-8')).hexdigest()

    def _invite_key(self, token):
        return f'invite:{token}'

    def _username_index_key(self, username):
        return f'idx:username:{normalize_username(username)}'

    def _dm_key(self, user_a, user_b):
        low, high = sorted([int(user_a), int(user_b)])
        return f'dm:{low}:{high}'

    async def _next_user_id(self):
        return int(await self.redis.incr('seq:users'))

    async def _next_room_id(self):
        return int(await self.redis.incr('seq:rooms'))

    async def _load_user_hash(self, user_id):
        data = await self.redis.hgetall(self._user_key(user_id))
        return data or None

    async def _load_room_meta(self, room_id):
        data = await self.redis.hgetall(self._room_meta_key(room_id))
        return data or None

    async def _resolve_username_id(self, username):
        username_key = self._username_index_key(username)
        user_id = await self.redis.get(username_key)
        if user_id is None:
            return None

        raw_user = await self._load_user_hash(user_id)
        if raw_user is None or raw_user.get('username_normalized') != normalize_username(username):
            await self.redis.delete(username_key)
            return None
        return int(user_id)

    def _serialize_user(self, raw_user, *, authenticated):
        if raw_user is None:
            return None
        user_id = int(raw_user['id'])
        avatar_version = int(raw_user.get('avatar_version', 0))
        password_hash = raw_user.get('password_hash') or None
        return {
            'id': user_id,
            'username': raw_user['username'],
            'status': raw_user.get('status') or raw_user.get('about_me') or None,
            'picture': avatar_url(user_id, avatar_version),
            'has_password': password_hash is not None,
            'authenticated': authenticated,
        }

    def _serialize_nearby_user(self, raw_user, distance_meters):
        user = self._serialize_user(raw_user, authenticated=False)
        user['last_seen'] = ts_to_iso(raw_user['last_seen'])
        user['distance'] = round(distance_meters, -1)
        return user

    async def get_public_user(self, user_id):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            return None
        return self._serialize_user(raw_user, authenticated=False)

    async def get_authenticated_user(self, user_id):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            return None
        return self._serialize_user(raw_user, authenticated=True)

    async def get_room(self, room_id):
        return await self._serialize_room(room_id)

    async def get_room_for_user(self, room_id, user_id):
        return await self._serialize_room(room_id, viewer_user_id=user_id)

    async def create_guest_user(self, username):
        username = username.strip()
        if not username:
            raise ValueError('Username cannot be empty')

        username_key = self._username_index_key(username)
        user_id = await self._next_user_id()
        timestamp = now_ts()
        profile = {
            'id': user_id,
            'username': username,
            'username_normalized': normalize_username(username),
            'status': '',
            'password_hash': '',
            'avatar_seed': secrets.token_hex(16),
            'avatar_version': timestamp,
            'created_at': timestamp,
        }

        if not await self.redis.set(username_key, user_id, nx=True):
            raise UsernameAlreadyExists()

        await self.redis.hset(self._user_key(user_id), mapping=profile)
        return await self.get_authenticated_user(user_id)

    async def authenticate(self, username, password):
        username = username.strip()
        user_id = await self._resolve_username_id(username)
        if user_id is None:
            return None

        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            return None

        password_hash = raw_user.get('password_hash') or None
        if password_hash is None or not check_password_hash(password_hash, password):
            return False
        return self._serialize_user(raw_user, authenticated=True)

    async def update_user(self, user_id, *, username=None, password=None, status=None):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            raise UserNotFound()

        updates = {}
        remove_legacy_about_me = False
        remove_legacy_phone = 'phone' in raw_user
        if username is not None:
            username = username.strip()
            if not username:
                raise ValueError('Username cannot be empty')
            if normalize_username(username) != raw_user['username_normalized']:
                await self._replace_username(user_id, raw_user['username'], username)
                updates['username'] = username
                updates['username_normalized'] = normalize_username(username)
        if password is not None:
            updates['password_hash'] = generate_password_hash(password)
        if status is not None:
            updates['status'] = normalize_status(status)
            remove_legacy_about_me = True

        if updates:
            await self.redis.hset(self._user_key(user_id), mapping=updates)
        if remove_legacy_about_me:
            await self.redis.hdel(self._user_key(user_id), 'about_me')
        if remove_legacy_phone:
            await self.redis.hdel(self._user_key(user_id), 'phone')
        return await self.get_authenticated_user(user_id)

    async def _replace_username(self, user_id, old_username, new_username):
        old_key = self._username_index_key(old_username)
        new_key = self._username_index_key(new_username)
        existing_user_id = await self._resolve_username_id(new_username)
        if existing_user_id is not None and int(existing_user_id) != int(user_id):
            raise UsernameAlreadyExists()
        if not await self.redis.set(new_key, user_id, nx=True):
            existing_user_id = await self._resolve_username_id(new_username)
            if existing_user_id is not None and int(existing_user_id) != int(user_id):
                raise UsernameAlreadyExists()
            await self.redis.set(new_key, user_id)
        await self.redis.delete(old_key)

    async def normalize_and_store_avatar(self, user_id, raw_bytes):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            raise UserNotFound()
        if len(raw_bytes) > MAX_AVATAR_BYTES:
            raise ValueError('Avatar file is too large')

        normalized = self._normalize_avatar(raw_bytes)
        version = now_ts()
        await self.redis_bytes.set(self._user_avatar_key(user_id), normalized)
        await self.redis.hset(self._user_key(user_id), mapping={
            'avatar_version': version,
        })
        return avatar_url(user_id, version)

    def _normalize_avatar(self, raw_bytes):
        try:
            with Image.open(BytesIO(raw_bytes)) as image:
                width, height = image.size
                if width * height > MAX_AVATAR_PIXELS:
                    raise ValueError('Avatar image is too large')
                image = image.convert('RGBA')
                crop = min(width, height)
                left = (width - crop) // 2
                top = (height - crop) // 2
                image = image.crop((left, top, left + crop, top + crop))
                image = image.resize((AVATAR_SIZE, AVATAR_SIZE))
                output = BytesIO()
                image.save(output, format='PNG', optimize=True)
                return output.getvalue()
        except (UnidentifiedImageError, OSError, Image.DecompressionBombError):
            raise ValueError('Invalid image file')

    async def get_avatar(self, user_id):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            raise UserNotFound()

        data = await self.redis_bytes.get(self._user_avatar_key(user_id))
        if data is not None:
            return data, 'image/png'

        avatar = create_random_avatar(seed=raw_user['avatar_seed']).getvalue()
        return avatar, 'image/png'

    async def checkin(self, user_id, *, lat, lon):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            raise UserNotFound()

        timestamp = now_ts()
        await self.redis.execute_command('GEOADD', 'geo:active_users', lon, lat, user_id)
        await self.redis.zadd('z:user:last_seen', {user_id: timestamp})
        await self.redis.hset(self._user_key(user_id), mapping={'last_seen': timestamp})

        excluded_user_ids = await self._shared_room_user_ids(user_id)
        cutoff = timestamp - ACTIVE_WINDOW_SECONDS
        result = await self.redis.georadius(
            'geo:active_users',
            lon,
            lat,
            20000,
            unit='km',
            withdist=True,
            count=MAX_GEO_RESULTS,
            sort='ASC',
            store=None,
            store_dist=None,
        )
        nearby = []
        for item in result:
            candidate_id = int(item[0])
            if candidate_id == int(user_id) or candidate_id in excluded_user_ids:
                continue
            candidate = await self._load_user_hash(candidate_id)
            if candidate is None:
                continue
            last_seen = int(candidate.get('last_seen', 0) or 0)
            if last_seen < cutoff:
                continue
            distance_meters = float(item[1]) * 1000
            nearby.append(self._serialize_nearby_user(candidate, distance_meters))
            if len(nearby) >= MAX_NEARBY_RESULTS:
                break
        return {'nearby_users': nearby}

    async def _shared_room_user_ids(self, user_id):
        room_ids = await self.redis.zrange(self._user_rooms_key(user_id), 0, -1)
        excluded = set()
        for room_id in room_ids:
            members = await self.redis.smembers(self._room_members_key(room_id))
            excluded.update(int(member) for member in members)
        excluded.discard(int(user_id))
        return excluded

    async def join_user(self, user_id, other_user_id):
        other_user_id = int(other_user_id)
        if int(user_id) == other_user_id:
            raise ValueError('Cannot start a room with yourself')
        if await self._load_user_hash(other_user_id) is None:
            raise UserNotFound()

        dm_key = self._dm_key(user_id, other_user_id)
        existing_room_id = await self.redis.get(dm_key)
        if existing_room_id is not None:
            return {'id': int(existing_room_id), 'created': False}

        room_id = await self._next_room_id()
        members = sorted([int(user_id), other_user_id])
        created = True
        if not await self.redis.set(dm_key, room_id, nx=True):
            existing_room_id = await self.redis.get(dm_key)
            room_id = int(existing_room_id)
            created = False

        await self._ensure_dm_room(room_id, dm_key, members)
        return {'id': int(room_id), 'created': created}

    async def _ensure_dm_room(self, room_id, dm_key, members):
        timestamp_ms = now_ms()
        room_meta_key = self._room_meta_key(room_id)
        await self.redis.hsetnx(room_meta_key, 'id', room_id)
        await self.redis.hsetnx(room_meta_key, 'name', '')
        await self.redis.hsetnx(room_meta_key, 'picture', '')
        await self.redis.hsetnx(room_meta_key, 'is_group', '0')
        await self.redis.hsetnx(room_meta_key, 'is_public', '0')
        await self.redis.hsetnx(room_meta_key, 'updated_at', timestamp_ms)
        await self.redis.hsetnx(room_meta_key, 'last_message', '')
        await self.redis.hsetnx(room_meta_key, 'dm_key', dm_key)
        for member in members:
            await self.redis.sadd(self._room_members_key(room_id), member)
            await self.redis.zadd(self._user_rooms_key(member), {room_id: timestamp_ms})

    async def create_group_room(self, owner_id, *, name, user_ids):
        member_ids = sorted({int(owner_id), *[int(user_id) for user_id in user_ids]})
        if len(member_ids) < 2:
            raise ValueError('A room needs at least two participants')
        for member_id in member_ids:
            if await self._load_user_hash(member_id) is None:
                raise UserNotFound()

        room_id = await self._next_room_id()
        timestamp_ms = now_ms()
        await self.redis.hset(self._room_meta_key(room_id), mapping={
            'id': room_id,
            'name': name.strip(),
            'picture': '',
            'is_group': '1',
            'is_public': '0',
            'updated_at': timestamp_ms,
            'last_message': '',
            'dm_key': '',
        })
        for member_id in member_ids:
            await self.redis.sadd(self._room_members_key(room_id), member_id)
            await self.redis.zadd(self._user_rooms_key(member_id), {room_id: timestamp_ms})
        return {'id': room_id}

    async def create_invite(self, inviter_id, *, room_id=None):
        if await self._load_user_hash(inviter_id) is None:
            raise UserNotFound()

        payload = {
            'inviter_id': int(inviter_id),
            'created_at': now_ts(),
        }
        if room_id is None:
            payload['target'] = 'user'
        else:
            room_id = int(room_id)
            meta = await self._load_room_meta(room_id)
            if meta is None:
                raise RoomNotFound()
            if not await self.user_in_room(inviter_id, room_id):
                raise PermissionDenied()
            payload['target'] = 'room'
            payload['room_id'] = room_id

        token = secrets.token_urlsafe(18)
        await self.redis.set(
            self._invite_key(token),
            json.dumps(payload),
            ex=INVITE_TTL_SECONDS,
        )
        return {
            'token': token,
            'expires_at': ts_to_iso(payload['created_at'] + INVITE_TTL_SECONDS),
            'room_id': payload.get('room_id'),
        }

    async def accept_invite(self, user_id, token):
        invite_json = await self.redis.get(self._invite_key(token))
        if invite_json is None:
            raise InviteNotFound()

        invite = json.loads(invite_json)
        inviter_id = int(invite['inviter_id'])
        if await self._load_user_hash(user_id) is None or await self._load_user_hash(inviter_id) is None:
            raise InviteNotFound()

        if invite['target'] == 'room':
            room_id = int(invite['room_id'])
            return await self._add_user_to_room(
                room_id,
                user_id,
                inviter_id=inviter_id,
            )

        if int(user_id) == inviter_id:
            raise PermissionDenied()
        room_data = await self.join_user(inviter_id, user_id)
        room = await self._serialize_room(room_data['id'])
        if room is None:
            raise RoomNotFound()
        return {
            'room': room,
            'membership_changed': room_data.get('created') is True,
        }

    async def user_in_room(self, user_id, room_id):
        return bool(await self.redis.sismember(self._room_members_key(room_id), user_id))

    async def send_message(self, sender_id, room_id, body):
        room_id = int(room_id)
        if not await self.user_in_room(sender_id, room_id):
            raise PermissionDenied()
        body = body.strip()
        if not body:
            raise ValueError('Empty message body')

        timestamp_ms = now_ms()
        message = {
            'id': f'{timestamp_ms}-{secrets.token_hex(4)}',
            'body': body,
            'sender_id': int(sender_id),
            'timestamp': ts_ms_to_iso(timestamp_ms),
        }
        encoded = json.dumps(message)
        cutoff_ms = timestamp_ms - (MESSAGE_TTL_SECONDS * 1000)
        room_messages_key = self._room_messages_key(room_id)
        await self.redis.zadd(room_messages_key, {encoded: timestamp_ms})
        await self.redis.zremrangebyscore(room_messages_key, '-inf', cutoff_ms)

        last_message = {
            'body': body,
            'sender_id': int(sender_id),
            'timestamp': ts_ms_to_iso(timestamp_ms),
        }
        room_meta_key = self._room_meta_key(room_id)
        await self.redis.hset(room_meta_key, mapping={
            'updated_at': timestamp_ms,
            'last_message': json.dumps(last_message),
        })

        members = await self.redis.smembers(self._room_members_key(room_id))
        for member in members:
            await self.redis.zadd(self._user_rooms_key(member), {room_id: timestamp_ms})

        return message

    async def publish_room_message(self, room_id, message):
        payload = json.dumps({
            'type': 'new-messages',
            'room_id': int(room_id),
            'messages': [message],
        })
        await self.redis.publish(f'room:{room_id}', payload)

    async def publish_signout(self, user_id):
        await self.redis.publish(f'user:{user_id}', json.dumps({'type': 'signout'}))

    async def publish_rooms_changed(self, user_ids):
        for user_id in {int(user_id) for user_id in user_ids}:
            await self.redis.publish(f'user:{user_id}', json.dumps({'type': 'rooms-changed'}))

    async def publish_room_deleted(self, room_id):
        await self.redis.publish(f'room:{room_id}', json.dumps({
            'type': 'room-deleted',
            'room_id': int(room_id),
        }))

    async def upsert_push_subscription(self, user_id, subscription, *, user_agent='', client_id=None):
        endpoint = subscription['endpoint']
        subscription_id = self._push_subscription_id(endpoint)
        key = self._push_subscription_key(subscription_id)
        existing_user_id = await self.redis.hget(key, 'user_id')
        if existing_user_id is not None and int(existing_user_id) != int(user_id):
            await self.redis.srem(self._user_push_subscriptions_key(int(existing_user_id)), subscription_id)

        timestamp = now_ts()
        await self.redis.hset(key, mapping={
            'id': subscription_id,
            'user_id': int(user_id),
            'endpoint': endpoint,
            'p256dh': subscription['keys']['p256dh'],
            'auth': subscription['keys']['auth'],
            'expiration_time': '' if subscription.get('expirationTime') is None else int(subscription['expirationTime']),
            'user_agent': user_agent,
            'client_id': client_id or '',
            'created_at': int(await self.redis.hget(key, 'created_at') or timestamp),
            'updated_at': timestamp,
        })
        await self.redis.sadd(self._user_push_subscriptions_key(user_id), subscription_id)
        return subscription_id

    async def remove_push_subscription(self, user_id, endpoint):
        subscription_id = self._push_subscription_id(endpoint)
        key = self._push_subscription_key(subscription_id)
        existing_user_id = await self.redis.hget(key, 'user_id')
        if existing_user_id is None or int(existing_user_id) != int(user_id):
            return False
        await self.redis.delete(key)
        await self.redis.srem(self._user_push_subscriptions_key(user_id), subscription_id)
        return True

    async def remove_push_subscription_by_id(self, subscription_id):
        key = self._push_subscription_key(subscription_id)
        user_id = await self.redis.hget(key, 'user_id')
        if user_id is None:
            return False
        await self.redis.delete(key)
        await self.redis.srem(self._user_push_subscriptions_key(int(user_id)), subscription_id)
        return True

    async def remove_push_subscriptions_for_user(self, user_id):
        subscription_ids = await self.redis.smembers(self._user_push_subscriptions_key(user_id))
        if subscription_ids:
            await self.redis.delete(*(self._push_subscription_key(subscription_id) for subscription_id in subscription_ids))
        await self.redis.delete(self._user_push_subscriptions_key(user_id))

    async def get_push_subscriptions_for_users(self, user_ids):
        subscriptions = []
        seen_subscription_ids = set()
        for user_id in {int(candidate) for candidate in user_ids}:
            subscription_ids = await self.redis.smembers(self._user_push_subscriptions_key(user_id))
            for subscription_id in subscription_ids:
                if subscription_id in seen_subscription_ids:
                    continue
                seen_subscription_ids.add(subscription_id)
                data = await self.redis.hgetall(self._push_subscription_key(subscription_id))
                if not data:
                    await self.redis.srem(self._user_push_subscriptions_key(user_id), subscription_id)
                    continue
                subscriptions.append({
                    'id': data['id'],
                    'user_id': int(data['user_id']),
                    'endpoint': data['endpoint'],
                    'keys': {
                        'p256dh': data['p256dh'],
                        'auth': data['auth'],
                    },
                    'expirationTime': int(data['expiration_time']) if data.get('expiration_time') else None,
                    'user_agent': data.get('user_agent') or '',
                    'client_id': data.get('client_id') or None,
                })
        return subscriptions

    async def get_room_push_muted(self, user_id, room_id):
        value = await self.redis.hget(self._user_room_prefs_key(user_id), int(room_id))
        return room_bool(value)

    async def set_room_push_muted(self, user_id, room_id, *, push_muted):
        room_id = int(room_id)
        if not await self.user_in_room(user_id, room_id):
            raise PermissionDenied()
        prefs_key = self._user_room_prefs_key(user_id)
        if push_muted:
            await self.redis.hset(prefs_key, room_id, '1')
        else:
            await self.redis.hdel(prefs_key, room_id)
        return await self._serialize_room(room_id, viewer_user_id=user_id)

    async def mark_active_websocket(self, user_id, connection_id, *, client_id=None):
        key = (
            self._user_client_websocket_presence_key(user_id, client_id)
            if client_id else self._user_websocket_presence_key(user_id)
        )
        now = now_ts()
        expires_at = now + WEBSOCKET_PRESENCE_TTL_SECONDS
        await self.redis.zremrangebyscore(key, '-inf', now)
        await self.redis.zadd(key, {connection_id: expires_at})
        return expires_at

    async def clear_active_websocket(self, user_id, connection_id, *, client_id=None):
        key = (
            self._user_client_websocket_presence_key(user_id, client_id)
            if client_id else self._user_websocket_presence_key(user_id)
        )
        await self.redis.zrem(key, connection_id)

    async def has_active_websocket(self, user_id, *, client_id=None):
        key = (
            self._user_client_websocket_presence_key(user_id, client_id)
            if client_id else self._user_websocket_presence_key(user_id)
        )
        now = now_ts()
        await self.redis.zremrangebyscore(key, '-inf', now)
        return int(await self.redis.zcard(key)) > 0

    async def get_room_members(self, room_id):
        return sorted(int(member) for member in await self.redis.smembers(self._room_members_key(room_id)))

    async def _add_user_to_room(self, room_id, user_id, *, inviter_id):
        room_id = int(room_id)
        user_id = int(user_id)
        inviter_id = int(inviter_id)

        meta_key = self._room_meta_key(room_id)
        meta = await self.redis.hgetall(meta_key)
        if not meta:
            raise RoomNotFound()
        if await self._load_user_hash(user_id) is None:
            raise UserNotFound()

        members_key = self._room_members_key(room_id)
        if not await self.redis.sismember(members_key, inviter_id):
            raise PermissionDenied()
        if await self.redis.sismember(members_key, user_id):
            room = await self._serialize_room(room_id, viewer_user_id=user_id)
            if room is None:
                raise RoomNotFound()
            return {
                'room': room,
                'membership_changed': False,
            }

        timestamp_ms = now_ms()
        existing_members = sorted(
            int(member)
            for member in await self.redis.smembers(members_key)
        )
        if not room_bool(meta.get('is_group')) and len(existing_members) >= 2:
            dm_key = meta.get('dm_key') or ''
            if dm_key:
                await self.redis.delete(dm_key)
            await self.redis.hset(meta_key, mapping={
                'is_group': '1',
                'dm_key': '',
            })

        all_members = sorted({*existing_members, user_id})
        await self.redis.sadd(members_key, user_id)
        await self.redis.hset(meta_key, mapping={'updated_at': timestamp_ms})
        for member_id in all_members:
            await self.redis.zadd(self._user_rooms_key(member_id), {room_id: timestamp_ms})

        room = await self._serialize_room(room_id, viewer_user_id=user_id)
        if room is None:
            raise RoomNotFound()
        return {
            'room': room,
            'membership_changed': True,
        }

    async def get_rooms(self, user_id):
        room_ids = await self.redis.zrevrange(self._user_rooms_key(user_id), 0, MAX_ROOM_RESULTS - 1)
        rooms = []
        for room_id in room_ids:
            room = await self._serialize_room(room_id, viewer_user_id=user_id)
            if room is not None:
                rooms.append(room)
        return rooms

    async def _serialize_room(self, room_id, *, viewer_user_id=None):
        meta = await self.redis.hgetall(self._room_meta_key(room_id))
        if not meta:
            return None
        room_id = int(meta['id'])
        member_ids = sorted(int(member) for member in await self.redis.smembers(self._room_members_key(room_id)))
        participants = []
        for member_id in member_ids:
            raw_user = await self._load_user_hash(member_id)
            if raw_user is None:
                continue
            participants.append({
                'id': member_id,
                'username': raw_user['username'],
                'picture': avatar_url(member_id, int(raw_user.get('avatar_version', 0))),
            })
        last_message = meta.get('last_message') or ''
        return {
            'id': room_id,
            'name': meta.get('name') or None,
            'last_message': json.loads(last_message) if last_message else None,
            'updated_at': ts_ms_to_iso(meta.get('updated_at', 0) or 0),
            'picture': meta.get('picture') or None,
            'is_group': room_bool(meta.get('is_group')),
            'is_public': room_bool(meta.get('is_public')),
            'push_muted': await self.get_room_push_muted(viewer_user_id, room_id)
            if viewer_user_id is not None else False,
            'participants': participants,
        }

    async def get_messages(self, user_id, room_id):
        room_id = int(room_id)
        if not await self.user_in_room(user_id, room_id):
            raise PermissionDenied()
        cutoff_ms = now_ms() - (MESSAGE_TTL_SECONDS * 1000)
        room_messages_key = self._room_messages_key(room_id)
        await self.redis.zremrangebyscore(room_messages_key, '-inf', cutoff_ms)
        messages = await self.redis.zrevrange(room_messages_key, 0, MAX_MESSAGE_RESULTS - 1)
        return [json.loads(message) for message in messages]

    async def delete_account(self, user_id):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            return False

        room_ids = await self.redis.zrange(self._user_rooms_key(user_id), 0, -1)
        for room_id in room_ids:
            await self._remove_user_from_room(user_id, int(room_id))

        await self.redis.delete(self._user_rooms_key(user_id))
        await self.redis.delete(self._user_key(user_id))
        await self.redis.delete(self._username_index_key(raw_user['username']))
        await self.redis.zrem('z:user:last_seen', user_id)
        await self.redis.execute_command('ZREM', 'geo:active_users', user_id)
        await self.redis_bytes.delete(self._user_avatar_key(user_id))
        await self.redis.delete(self._user_room_prefs_key(user_id))
        websocket_keys = [self._user_websocket_presence_key(user_id)]
        websocket_keys.extend(
            await self.redis.keys(f'user:{{{user_id}}}:websocket_presence:*')
        )
        if websocket_keys:
            await self.redis.delete(*set(websocket_keys))
        await self.remove_push_subscriptions_for_user(user_id)
        return True

    async def _remove_user_from_room(self, user_id, room_id):
        meta_key = self._room_meta_key(room_id)
        meta = await self.redis.hgetall(meta_key)
        if not meta:
            return

        members_key = self._room_members_key(room_id)
        await self.redis.srem(members_key, user_id)
        await self.redis.zrem(self._user_rooms_key(user_id), room_id)
        await self.redis.hdel(self._user_room_prefs_key(user_id), room_id)
        remaining_members = sorted(int(member) for member in await self.redis.smembers(members_key))

        should_delete_room = False
        if room_bool(meta.get('is_group')):
            should_delete_room = len(remaining_members) == 0
        else:
            should_delete_room = len(remaining_members) < 2

        if should_delete_room:
            await self.publish_room_deleted(room_id)
            await self.publish_rooms_changed(remaining_members)
            for member in remaining_members:
                await self.redis.zrem(self._user_rooms_key(member), room_id)
                await self.redis.hdel(self._user_room_prefs_key(member), room_id)
            if meta.get('dm_key'):
                await self.redis.delete(meta['dm_key'])
            await self.redis.delete(meta_key)
            await self.redis.delete(members_key)
            await self.redis.delete(self._room_messages_key(room_id))
