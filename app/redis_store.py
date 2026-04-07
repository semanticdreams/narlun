import redis.asyncio as redis
import hashlib
import json
import logging
import secrets
import time
from datetime import datetime, timezone
from io import BytesIO

from PIL import Image, UnidentifiedImageError
from werkzeug.security import generate_password_hash, check_password_hash

from app.random_statuses import pick_random_status
from app.util import create_random_avatar


MESSAGE_TTL_SECONDS = 7 * 24 * 60 * 60
NEARBY_ACTIVITY_WINDOW_SECONDS = 2 * 60 * 60
NEARBY_ACTIVITY_WINDOW_MILLISECONDS = NEARBY_ACTIVITY_WINDOW_SECONDS * 1000
INACTIVE_USER_TTL_SECONDS = 4 * 7 * 24 * 60 * 60
INVITE_TTL_SECONDS = 24 * 60 * 60
JOIN_REQUEST_TTL_SECONDS = NEARBY_ACTIVITY_WINDOW_SECONDS
REJECTED_JOIN_REQUEST_TTL_SECONDS = 24 * 60 * 60
WEBSOCKET_PRESENCE_TTL_SECONDS = 45
CLEANUP_INTERVAL_SECONDS = 60 * 60
NEARBY_RADIUS_KM = 20000
MAX_NEARBY_RESULTS = 10
MAX_GEO_RESULTS = 50
MAX_ROOM_RESULTS = 30
MAX_MESSAGE_RESULTS = 20
AVATAR_SIZE = 256
MAX_AVATAR_BYTES = 2 * 1024 * 1024
MAX_AVATAR_PIXELS = 20_000_000
MAX_STATUS_LENGTH = 80
logger = logging.getLogger(__name__)


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


class JoinRequestNotFound(Exception):
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

    def _room_read_states_key(self, room_id):
        return f'room:{{{room_id}}}:read_states'

    def _room_join_requests_key(self, room_id):
        return f'room:{{{room_id}}}:join_requests'

    def _user_push_subscriptions_key(self, user_id):
        return f'user:{{{user_id}}}:push_subscriptions'

    def _user_room_prefs_key(self, user_id):
        return f'user:{{{user_id}}}:room_prefs'

    def _user_requested_rooms_key(self, user_id):
        return f'user:{{{user_id}}}:requested_rooms'

    def _user_rejected_rooms_key(self, user_id):
        return f'user:{{{user_id}}}:rejected_rooms'

    def _user_websocket_presence_key(self, user_id):
        return f'user:{{{user_id}}}:websocket_presence'

    def _user_client_websocket_presence_key(self, user_id, client_id):
        client_hash = hashlib.sha256(client_id.encode('utf-8')).hexdigest()
        return f'user:{{{user_id}}}:websocket_presence:{client_hash}'

    def _user_client_live_view_key(self, user_id, client_id, view_key):
        client_hash = hashlib.sha256(client_id.encode('utf-8')).hexdigest()
        view_hash = hashlib.sha256(view_key.encode('utf-8')).hexdigest()
        return f'user:{{{user_id}}}:live_view:{client_hash}:{view_hash}'

    def _push_subscription_key(self, subscription_id):
        return f'push_subscription:{subscription_id}'

    def _push_subscription_id(self, endpoint):
        return hashlib.sha256(endpoint.encode('utf-8')).hexdigest()

    def _invite_key(self, token):
        return f'invite:{token}'

    def _join_request_key(self, room_id, user_id):
        return f'join_request:{int(room_id)}:{int(user_id)}'

    def _username_index_key(self, username):
        return f'idx:username:{normalize_username(username)}'

    def _user_activity_index_backfill_key(self):
        return 'meta:user_last_active_backfilled'

    def _legacy_dm_key(self, user_a, user_b):
        # Backward compatibility for deployed pair-room mappings.
        low, high = sorted([int(user_a), int(user_b)])
        return f'dm:{low}:{high}'

    def _room_pair_key(self, user_a, user_b):
        low, high = sorted([int(user_a), int(user_b)])
        return f'room_pair:{low}:{high}'

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

    def _nearby_activity_cutoff_ts(self, *, current_ts=None):
        timestamp = now_ts() if current_ts is None else int(current_ts)
        return timestamp - NEARBY_ACTIVITY_WINDOW_SECONDS

    def _nearby_activity_cutoff_ms(self, *, current_ts_ms=None):
        timestamp_ms = now_ms() if current_ts_ms is None else int(current_ts_ms)
        return timestamp_ms - NEARBY_ACTIVITY_WINDOW_MILLISECONDS

    def _inactive_user_cutoff_ts(self, *, current_ts=None):
        timestamp = now_ts() if current_ts is None else int(current_ts)
        return timestamp - INACTIVE_USER_TTL_SECONDS

    def _room_meta_has_recent_nearby_activity(self, meta, *, current_ts_ms=None):
        if not meta:
            return False
        return int(meta.get('updated_at', 0) or 0) >= self._nearby_activity_cutoff_ms(
            current_ts_ms=current_ts_ms,
        )

    async def touch_user_activity(self, user_id, *, timestamp=None):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            return False
        activity_timestamp = now_ts() if timestamp is None else int(timestamp)
        user_id = int(user_id)
        await self.redis.zadd('z:user:last_active', {user_id: activity_timestamp})
        await self.redis.hset(
            self._user_key(user_id),
            mapping={'last_active': activity_timestamp},
        )
        return True

    async def _iter_user_ids(self):
        cursor = 0
        seen = set()
        while True:
            cursor, keys = await self.redis.scan(
                cursor=cursor,
                match='user:{*}:profile',
                count=100,
            )
            for key in keys:
                try:
                    user_id = int(key.split('{', 1)[1].split('}', 1)[0])
                except (IndexError, ValueError, TypeError):
                    continue
                if user_id in seen:
                    continue
                seen.add(user_id)
                yield user_id
            if cursor == 0:
                break

    async def _iter_room_ids(self):
        cursor = 0
        seen = set()
        while True:
            cursor, keys = await self.redis.scan(
                cursor=cursor,
                match='room:{*}:meta',
                count=100,
            )
            for key in keys:
                try:
                    room_id = int(key.split('{', 1)[1].split('}', 1)[0])
                except (IndexError, ValueError, TypeError):
                    continue
                if room_id in seen:
                    continue
                seen.add(room_id)
                yield room_id
            if cursor == 0:
                break

    async def _ensure_user_activity_index(self):
        if await self.redis.get(self._user_activity_index_backfill_key()) == '1':
            return
        for user_id in [user_id async for user_id in self._iter_user_ids()]:
            raw_user = await self._load_user_hash(user_id)
            if raw_user is None:
                continue
            last_active = int(
                raw_user.get('last_active')
                or raw_user.get('last_seen')
                or raw_user.get('created_at')
                or 0
            )
            if last_active <= 0:
                continue
            await self.redis.hset(
                self._user_key(user_id),
                mapping={'last_active': last_active},
            )
            await self.redis.zadd('z:user:last_active', {int(user_id): last_active})
        await self.redis.set(self._user_activity_index_backfill_key(), '1')

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

    def _serialize_room_participant(self, raw_user):
        user_id = int(raw_user['id'])
        return {
            'id': user_id,
            'username': raw_user['username'],
            'picture': avatar_url(user_id, int(raw_user.get('avatar_version', 0))),
        }

    def _default_room_name(self, raw_user, *, seed=None):
        status = normalize_status(raw_user.get('status') or raw_user.get('about_me') or '')
        if status:
            return status
        return pick_random_status(seed=seed)

    def _message_sort_key(self, message):
        message_id = str(message.get('id') or '')
        try:
            timestamp_ms = int(message_id.split('-', 1)[0])
        except (TypeError, ValueError, AttributeError):
            timestamp_ms = 0
        return timestamp_ms, message_id

    async def _get_room_participants_by_id(self, room_id):
        participant_ids = sorted(
            int(member)
            for member in await self.redis.smembers(self._room_members_key(room_id))
        )
        participants_by_id = {}
        for participant_id in participant_ids:
            raw_user = await self._load_user_hash(participant_id)
            if raw_user is None:
                continue
            participants_by_id[participant_id] = self._serialize_room_participant(raw_user)
        return participants_by_id

    async def _get_room_read_states(self, room_id):
        room_id = int(room_id)
        raw_states = await self.redis.hgetall(self._room_read_states_key(room_id))
        read_states = {}
        for user_id, payload in raw_states.items():
            try:
                parsed = json.loads(payload)
                message_id = str(parsed['message_id'])
            except (TypeError, ValueError, KeyError, json.JSONDecodeError):
                continue
            read_states[int(user_id)] = {
                'user_id': int(user_id),
                'message_id': message_id,
                'read_at': parsed.get('read_at'),
            }
        return read_states

    def _serialize_message_with_state(self, message, *, participants_by_id, read_states):
        sender_id = int(message['sender_id'])
        sender = participants_by_id.get(sender_id) or {
            'id': sender_id,
            'username': 'Unknown user',
            'picture': None,
        }
        message_sort_key = self._message_sort_key(message)
        read_by_users = []
        for user_id, read_state in read_states.items():
            if self._message_sort_key({'id': read_state['message_id']}) < message_sort_key:
                continue
            participant = participants_by_id.get(user_id)
            if participant is not None:
                read_by_users.append(participant)
        read_by_users.sort(key=lambda participant: participant['username'])
        return {
            **message,
            'sender': sender,
            'read_by_users': read_by_users,
        }

    async def _delete_join_request(self, room_id, user_id):
        room_id = int(room_id)
        user_id = int(user_id)
        await self.redis.delete(self._join_request_key(room_id, user_id))
        await self.redis.zrem(self._room_join_requests_key(room_id), user_id)
        await self.redis.zrem(self._user_requested_rooms_key(user_id), room_id)

    async def _prune_expired_user_join_requests(self, user_id):
        user_id = int(user_id)
        expired_room_ids = await self.redis.zrangebyscore(
            self._user_requested_rooms_key(user_id),
            '-inf',
            now_ts(),
        )
        for room_id in expired_room_ids:
            await self._delete_join_request(room_id, user_id)

    async def _prune_expired_room_join_requests(self, room_id):
        room_id = int(room_id)
        expired_user_ids = await self.redis.zrangebyscore(
            self._room_join_requests_key(room_id),
            '-inf',
            now_ts(),
        )
        for user_id in expired_user_ids:
            await self._delete_join_request(room_id, user_id)

    async def _prune_expired_rejected_rooms(self, user_id):
        await self.redis.zremrangebyscore(
            self._user_rejected_rooms_key(user_id),
            '-inf',
            now_ts(),
        )

    async def _clear_join_requests_for_room(self, room_id):
        room_id = int(room_id)
        await self._prune_expired_room_join_requests(room_id)
        requester_ids = [
            int(user_id)
            for user_id in await self.redis.zrange(self._room_join_requests_key(room_id), 0, -1)
        ]
        for requester_id in requester_ids:
            await self._delete_join_request(room_id, requester_id)
        return requester_ids

    async def _clear_join_requests_for_user(self, user_id):
        user_id = int(user_id)
        await self._prune_expired_user_join_requests(user_id)
        room_ids = [
            int(room_id)
            for room_id in await self.redis.zrange(self._user_requested_rooms_key(user_id), 0, -1)
        ]
        for room_id in room_ids:
            await self._delete_join_request(room_id, user_id)
        return room_ids

    async def _serialize_join_request(self, room_id, requester_id):
        raw_request = await self.redis.hgetall(self._join_request_key(room_id, requester_id))
        if not raw_request:
            return None
        raw_user = await self._load_user_hash(requester_id)
        if raw_user is None:
            await self._delete_join_request(room_id, requester_id)
            return None
        return {
            'user': self._serialize_user(raw_user, authenticated=False),
            'created_at': ts_to_iso(raw_request.get('created_at', 0) or 0),
            'expires_at': ts_to_iso(raw_request.get('expires_at', 0) or 0),
        }

    async def _serialize_nearby_room(
        self,
        room_id,
        *,
        distance_meters=None,
        join_requested=False,
        require_recent_activity=True,
    ):
        meta = await self._load_room_meta(room_id)
        if meta is None:
            return None
        if require_recent_activity and not self._room_meta_has_recent_nearby_activity(meta):
            return None
        room = await self._serialize_room(room_id)
        if room is None:
            return None
        room['member_count'] = len(room['participants'])
        room['join_requested'] = join_requested
        if not room.get('name'):
            room['name'] = pick_random_status(seed=room['id'])
        return {
            'type': 'room',
            'distance': round(distance_meters, -1) if distance_meters is not None else None,
            'room': room,
        }

    async def get_room_join_request_count(self, room_id):
        room_id = int(room_id)
        await self._prune_expired_room_join_requests(room_id)
        return int(await self.redis.zcard(self._room_join_requests_key(room_id)))

    async def get_room_join_requester_ids(self, room_id):
        room_id = int(room_id)
        await self._prune_expired_room_join_requests(room_id)
        return [
            int(requester_id)
            for requester_id in await self.redis.zrange(self._room_join_requests_key(room_id), 0, -1)
        ]

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
            'last_active': timestamp,
        }

        if not await self.redis.set(username_key, user_id, nx=True):
            raise UsernameAlreadyExists()

        await self.redis.hset(self._user_key(user_id), mapping=profile)
        await self.redis.zadd('z:user:last_active', {user_id: timestamp})
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
        await self.touch_user_activity(user_id)
        return await self.get_authenticated_user(user_id)

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

        user_id = int(user_id)
        timestamp = now_ts()
        await self.redis.execute_command('GEOADD', 'geo:active_users', lon, lat, user_id)
        await self.redis.zadd('z:user:last_seen', {user_id: timestamp})
        await self.redis.hset(self._user_key(user_id), mapping={'last_seen': timestamp})

        excluded_user_ids = await self._shared_room_user_ids(user_id)
        joined_room_ids = await self._shared_room_ids(user_id)
        requested_room_ids = set(await self.get_requested_room_ids(user_id))
        rejected_room_ids = set(await self.get_rejected_room_ids(user_id))
        cutoff = self._nearby_activity_cutoff_ts(current_ts=timestamp)
        result = await self.redis.georadius(
            'geo:active_users',
            lon,
            lat,
            NEARBY_RADIUS_KM,
            unit='km',
            withdist=True,
            count=MAX_GEO_RESULTS,
            sort='ASC',
            store=None,
            store_dist=None,
        )
        nearby_users = []
        nearby_room_distances = {}
        for item in result:
            candidate_id = int(item[0])
            candidate = await self._load_user_hash(candidate_id)
            if candidate is None:
                continue
            last_seen = int(candidate.get('last_seen', 0) or 0)
            if last_seen < cutoff:
                continue
            distance_meters = float(item[1]) * 1000
            if candidate_id != user_id:
                room_ids = await self.redis.zrange(
                    self._user_rooms_key(candidate_id),
                    0,
                    MAX_ROOM_RESULTS - 1,
                )
                for room_id in room_ids:
                    normalized_room_id = int(room_id)
                    if (
                        normalized_room_id in joined_room_ids or
                        normalized_room_id in rejected_room_ids
                    ):
                        continue
                    existing_distance = nearby_room_distances.get(normalized_room_id)
                    if existing_distance is None or distance_meters < existing_distance:
                        nearby_room_distances[normalized_room_id] = distance_meters
            if candidate_id == user_id or candidate_id in excluded_user_ids:
                continue
            nearby_users.append({
                'type': 'user',
                'distance': round(distance_meters, -1),
                'user': self._serialize_nearby_user(candidate, distance_meters),
            })

        sorted_nearby_users = sorted(
            nearby_users,
            key=lambda item: (item['distance'], item['user']['username']),
        )

        nearby_rooms = []
        for room_id, distance_meters in nearby_room_distances.items():
            if room_id in requested_room_ids:
                continue
            serialized_room = await self._serialize_nearby_room(
                room_id,
                distance_meters=distance_meters,
                join_requested=False,
            )
            if serialized_room is not None:
                nearby_rooms.append(serialized_room)

        pinned_requested_rooms = []
        for room_id in requested_room_ids:
            serialized_room = await self._serialize_nearby_room(
                room_id,
                distance_meters=nearby_room_distances.get(room_id),
                join_requested=True,
            )
            if serialized_room is not None and not await self.user_in_room(user_id, room_id):
                pinned_requested_rooms.append(serialized_room)

        nearby = [
            *sorted_nearby_users,
            *sorted(
                nearby_rooms,
                key=lambda item: (
                    item['distance'] if item['distance'] is not None else 10**12,
                    item['room']['name'] or '',
                ),
            ),
        ]
        nearby.sort(key=lambda item: (
            item['distance'] if item['distance'] is not None else 10**12,
            0 if item['type'] == 'user' else 1,
        ))
        pinned_requested_rooms = sorted(
            pinned_requested_rooms,
            key=lambda item: (
                item['distance'] if item['distance'] is not None else 10**12,
                item['room']['name'] or '',
            ),
        )
        response = {
            'nearby': [*nearby[:MAX_NEARBY_RESULTS], *pinned_requested_rooms],
            'nearby_users': [
                item['user']
                for item in sorted_nearby_users[:MAX_NEARBY_RESULTS]
            ],
        }
        logger.info(
            'Computed nearby checkin result',
            extra={
                'user_id': user_id,
                'lat_rounded': round(float(lat), 4),
                'lon_rounded': round(float(lon), 4),
                'geo_candidate_count': len(result),
                'excluded_user_count': len(excluded_user_ids),
                'joined_room_count': len(joined_room_ids),
                'requested_room_count': len(requested_room_ids),
                'rejected_room_count': len(rejected_room_ids),
                'returned_item_count': len(response['nearby']),
                'returned_user_ids': self._sample_ids(
                    item['user']['id']
                    for item in response['nearby']
                    if item['type'] == 'user'
                ),
                'returned_room_ids': self._sample_ids(
                    item['room']['id']
                    for item in response['nearby']
                    if item['type'] == 'room'
                ),
                'pinned_requested_room_ids': self._sample_ids(
                    item['room']['id'] for item in pinned_requested_rooms
                ),
            },
        )
        return response

    async def _shared_room_user_ids(self, user_id):
        room_ids = await self.redis.zrange(self._user_rooms_key(user_id), 0, -1)
        excluded = set()
        for room_id in room_ids:
            members = await self.redis.smembers(self._room_members_key(room_id))
            excluded.update(int(member) for member in members)
        excluded.discard(int(user_id))
        return excluded

    async def _shared_room_ids(self, user_id):
        return {
            int(room_id)
            for room_id in await self.redis.zrange(self._user_rooms_key(user_id), 0, -1)
        }

    async def _active_nearby_audience_user_ids(self, user_id):
        user_id = int(user_id)
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            return set()

        cutoff = self._nearby_activity_cutoff_ts()
        last_seen = int(raw_user.get('last_seen', 0) or 0)
        if last_seen < cutoff:
            return set()

        positions = await self.redis.execute_command('GEOPOS', 'geo:active_users', user_id)
        if not positions or not positions[0]:
            return set()

        lon, lat = positions[0]
        result = await self.redis.georadius(
            'geo:active_users',
            float(lon),
            float(lat),
            NEARBY_RADIUS_KM,
            unit='km',
            withdist=True,
            sort='ASC',
            store=None,
            store_dist=None,
        )
        audience = set()
        for item in result:
            candidate_id = int(item[0])
            if candidate_id == user_id:
                continue
            candidate = await self._load_user_hash(candidate_id)
            if candidate is None:
                continue
            candidate_last_seen = int(candidate.get('last_seen', 0) or 0)
            if candidate_last_seen < cutoff:
                continue
            audience.add(candidate_id)
        return audience

    async def get_public_profile_update_targets(self, user_id, *, include_room_nearby_viewers=False):
        user_id = int(user_id)
        room_member_ids = await self._shared_room_user_ids(user_id)
        pending_request_room_ids = await self.get_requested_room_ids(user_id)
        nearby_viewer_ids = await self._active_nearby_audience_user_ids(user_id)
        if include_room_nearby_viewers:
            for room_id in await self._shared_room_ids(user_id):
                nearby_viewer_ids.update(await self.get_room_nearby_update_targets(room_id))
        nearby_viewer_ids.discard(user_id)

        return {
            'room_member_ids': sorted(room_member_ids),
            'nearby_viewer_ids': sorted(nearby_viewer_ids),
            'pending_request_room_ids': sorted(int(room_id) for room_id in pending_request_room_ids),
        }

    async def get_room_nearby_update_targets(self, room_id):
        room_id = int(room_id)
        room_member_ids = set(await self.get_room_members(room_id))
        nearby_viewer_ids = set(await self.get_room_join_requester_ids(room_id))
        for member_id in room_member_ids:
            nearby_viewer_ids.update(await self._active_nearby_audience_user_ids(member_id))
        nearby_viewer_ids.difference_update(room_member_ids)
        return sorted(nearby_viewer_ids)

    async def join_user(self, user_id, other_user_id):
        user_id = int(user_id)
        other_user_id = int(other_user_id)
        if user_id == other_user_id:
            raise ValueError('Cannot start a room with yourself')
        if await self._load_user_hash(other_user_id) is None:
            raise UserNotFound()
        owner = await self._load_user_hash(user_id)

        pair_key = self._room_pair_key(user_id, other_user_id)
        legacy_dm_key = self._legacy_dm_key(user_id, other_user_id)
        existing_room_id = await self.redis.get(pair_key)
        if existing_room_id is None:
            existing_room_id = await self.redis.get(legacy_dm_key)
            if existing_room_id is not None:
                await self.redis.set(pair_key, existing_room_id)
        if existing_room_id is not None:
            return {'id': int(existing_room_id), 'created': False}

        room_id = await self._next_room_id()
        members = sorted([int(user_id), other_user_id])
        created = True
        if not await self.redis.set(pair_key, room_id, nx=True):
            existing_room_id = await self.redis.get(pair_key)
            room_id = int(existing_room_id)
            created = False

        await self._ensure_pair_room(
            room_id,
            pair_key,
            members,
            name=self._default_room_name(owner, seed=room_id),
        )
        return {'id': int(room_id), 'created': created}

    async def _ensure_pair_room(self, room_id, pair_key, members, *, name):
        timestamp_ms = now_ms()
        room_meta_key = self._room_meta_key(room_id)
        await self.redis.hsetnx(room_meta_key, 'id', room_id)
        await self.redis.hsetnx(room_meta_key, 'name', name)
        await self.redis.hsetnx(room_meta_key, 'picture', '')
        await self.redis.hsetnx(room_meta_key, 'is_public', '0')
        await self.redis.hsetnx(room_meta_key, 'updated_at', timestamp_ms)
        await self.redis.hsetnx(room_meta_key, 'last_message', '')
        await self.redis.hsetnx(room_meta_key, 'pair_key', pair_key)
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
        owner = await self._load_user_hash(owner_id)
        resolved_name = name.strip()
        if not resolved_name:
            resolved_name = self._default_room_name(owner, seed=room_id)
        timestamp_ms = now_ms()
        await self.redis.hset(self._room_meta_key(room_id), mapping={
            'id': room_id,
            'name': resolved_name,
            'picture': '',
            'is_public': '0',
            'updated_at': timestamp_ms,
            'last_message': '',
        })
        for member_id in member_ids:
            await self.redis.sadd(self._room_members_key(room_id), member_id)
            await self.redis.zadd(self._user_rooms_key(member_id), {room_id: timestamp_ms})
        return {'id': room_id}

    async def get_requested_room_ids(self, user_id):
        await self._prune_expired_user_join_requests(user_id)
        return [
            int(room_id)
            for room_id in await self.redis.zrange(self._user_requested_rooms_key(user_id), 0, -1)
        ]

    async def get_rejected_room_ids(self, user_id):
        await self._prune_expired_rejected_rooms(user_id)
        return [
            int(room_id)
            for room_id in await self.redis.zrange(self._user_rejected_rooms_key(user_id), 0, -1)
        ]

    async def request_join_room(self, user_id, room_id):
        room_id = int(room_id)
        user_id = int(user_id)
        meta = await self._load_room_meta(room_id)
        if meta is None:
            raise RoomNotFound()
        if not self._room_meta_has_recent_nearby_activity(meta):
            raise RoomNotFound()
        if await self.user_in_room(user_id, room_id):
            raise PermissionDenied()

        await self._prune_expired_user_join_requests(user_id)
        await self._prune_expired_room_join_requests(room_id)
        await self.redis.zrem(self._user_rejected_rooms_key(user_id), room_id)
        request_key = self._join_request_key(room_id, user_id)
        if await self.redis.exists(request_key):
            room = await self._serialize_nearby_room(
                room_id,
                join_requested=True,
                require_recent_activity=False,
            )
            if room is None:
                raise RoomNotFound()
            return {'room': room['room'], 'created': False}

        created_at = now_ts()
        expires_at = created_at + JOIN_REQUEST_TTL_SECONDS
        await self.redis.hset(request_key, mapping={
            'room_id': room_id,
            'user_id': user_id,
            'created_at': created_at,
            'expires_at': expires_at,
        })
        await self.redis.zadd(self._room_join_requests_key(room_id), {user_id: expires_at})
        await self.redis.zadd(self._user_requested_rooms_key(user_id), {room_id: expires_at})
        room = await self._serialize_nearby_room(
            room_id,
            join_requested=True,
            require_recent_activity=False,
        )
        if room is None:
            raise RoomNotFound()
        return {'room': room['room'], 'created': True}

    async def get_room_join_requests(self, user_id, room_id):
        room_id = int(room_id)
        if not await self.user_in_room(user_id, room_id):
            raise PermissionDenied()
        await self._prune_expired_room_join_requests(room_id)
        requester_ids = [
            int(requester_id)
            for requester_id in await self.redis.zrange(self._room_join_requests_key(room_id), 0, -1)
        ]
        requests = []
        for requester_id in requester_ids:
            request = await self._serialize_join_request(room_id, requester_id)
            if request is not None:
                requests.append(request)
        return requests

    async def approve_room_join_request(self, approver_id, room_id, requester_id):
        room_id = int(room_id)
        requester_id = int(requester_id)
        if not await self.user_in_room(approver_id, room_id):
            raise PermissionDenied()
        await self._prune_expired_room_join_requests(room_id)
        if not await self.redis.exists(self._join_request_key(room_id, requester_id)):
            raise JoinRequestNotFound()
        await self._delete_join_request(room_id, requester_id)
        return await self._add_user_to_room(room_id, requester_id, inviter_id=approver_id)

    async def reject_room_join_request(self, approver_id, room_id, requester_id):
        room_id = int(room_id)
        requester_id = int(requester_id)
        if not await self.user_in_room(approver_id, room_id):
            raise PermissionDenied()
        await self._prune_expired_room_join_requests(room_id)
        if not await self.redis.exists(self._join_request_key(room_id, requester_id)):
            raise JoinRequestNotFound()
        await self._delete_join_request(room_id, requester_id)
        await self.redis.zadd(
            self._user_rejected_rooms_key(requester_id),
            {room_id: now_ts() + REJECTED_JOIN_REQUEST_TTL_SECONDS},
        )
        return True

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
        raw_sender = await self._load_user_hash(sender_id)
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
            'sender_username': raw_sender['username'] if raw_sender is not None else None,
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

        await self.mark_room_read(sender_id, room_id, message_id=message['id'])

        participants_by_id = await self._get_room_participants_by_id(room_id)
        read_states = await self._get_room_read_states(room_id)
        return self._serialize_message_with_state(
            message,
            participants_by_id=participants_by_id,
            read_states=read_states,
        )

    async def publish_room_message(self, room_id, message):
        payload = json.dumps({
            'type': 'new-messages',
            'room_id': int(room_id),
            'messages': [message],
        })
        await self.redis.publish(f'room:{room_id}', payload)
        logger.debug(
            'Published room message event',
            extra={
                'room_id': int(room_id),
                'message_id': message.get('id'),
            },
        )

    async def publish_room_read(self, room_id, read_state):
        payload = json.dumps({
            'type': 'room-read',
            'room_id': int(room_id),
            **read_state,
        })
        await self.redis.publish(f'room:{room_id}', payload)
        logger.debug(
            'Published room read event',
            extra={
                'room_id': int(room_id),
                'user_id': read_state.get('user_id'),
                'message_id': read_state.get('message_id'),
            },
        )

    async def publish_room_typing(self, room_id, user_id, *, is_typing):
        participants_by_id = await self._get_room_participants_by_id(room_id)
        payload = json.dumps({
            'type': 'typing-state',
            'room_id': int(room_id),
            'user_id': int(user_id),
            'is_typing': bool(is_typing),
            'user': participants_by_id.get(int(user_id)) or {
                'id': int(user_id),
                'username': 'Unknown user',
                'picture': None,
            },
        })
        await self.redis.publish(f'room:{room_id}', payload)
        logger.debug(
            'Published room typing event',
            extra={
                'room_id': int(room_id),
                'user_id': int(user_id),
                'is_typing': bool(is_typing),
            },
        )

    async def publish_signout(self, user_id):
        await self.redis.publish(f'user:{user_id}', json.dumps({'type': 'signout'}))
        logger.debug('Published signout event', extra={'user_id': int(user_id)})

    async def publish_rooms_changed(self, user_ids):
        normalized_user_ids = sorted({int(user_id) for user_id in user_ids})
        for user_id in normalized_user_ids:
            await self.redis.publish(f'user:{user_id}', json.dumps({'type': 'rooms-changed'}))
        logger.debug(
            'Published rooms changed event',
            extra={
                'target_user_count': len(normalized_user_ids),
                'target_user_ids': self._sample_ids(normalized_user_ids),
            },
        )

    async def publish_nearby_changed(self, user_ids):
        normalized_user_ids = sorted({int(user_id) for user_id in user_ids})
        for user_id in normalized_user_ids:
            await self.redis.publish(f'user:{user_id}', json.dumps({'type': 'nearby-changed'}))
        logger.debug(
            'Published nearby changed event',
            extra={
                'target_user_count': len(normalized_user_ids),
                'target_user_ids': self._sample_ids(normalized_user_ids),
            },
        )

    async def publish_room_deleted(self, room_id):
        await self.redis.publish(f'room:{room_id}', json.dumps({
            'type': 'room-deleted',
            'room_id': int(room_id),
        }))
        logger.debug('Published room deleted event', extra={'room_id': int(room_id)})

    async def publish_room_requests_changed(self, room_id):
        await self.redis.publish(f'room:{room_id}', json.dumps({
            'type': 'room-requests-changed',
            'room_id': int(room_id),
        }))
        logger.debug(
            'Published room requests changed event',
            extra={'room_id': int(room_id)},
        )

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
        logger.debug(
            'Marked active websocket presence',
            extra={
                'user_id': int(user_id),
                'connection_id': connection_id,
                'client_id': client_id,
                'expires_at': expires_at,
            },
        )
        return expires_at

    async def clear_active_websocket(self, user_id, connection_id, *, client_id=None):
        key = (
            self._user_client_websocket_presence_key(user_id, client_id)
            if client_id else self._user_websocket_presence_key(user_id)
        )
        await self.redis.zrem(key, connection_id)
        logger.debug(
            'Cleared active websocket presence',
            extra={
                'user_id': int(user_id),
                'connection_id': connection_id,
                'client_id': client_id,
            },
        )

    async def has_active_websocket(self, user_id, *, client_id=None):
        key = (
            self._user_client_websocket_presence_key(user_id, client_id)
            if client_id else self._user_websocket_presence_key(user_id)
        )
        now = now_ts()
        await self.redis.zremrangebyscore(key, '-inf', now)
        return int(await self.redis.zcard(key)) > 0

    async def mark_live_view(self, user_id, connection_id, *, client_id, view_key):
        key = self._user_client_live_view_key(user_id, client_id, view_key)
        now = now_ts()
        expires_at = now + WEBSOCKET_PRESENCE_TTL_SECONDS
        await self.redis.zremrangebyscore(key, '-inf', now)
        await self.redis.zadd(key, {connection_id: expires_at})
        logger.debug(
            'Marked live view presence',
            extra={
                'user_id': int(user_id),
                'connection_id': connection_id,
                'client_id': client_id,
                'view_key': view_key,
                'expires_at': expires_at,
            },
        )
        return expires_at

    async def clear_live_view(self, user_id, connection_id, *, client_id, view_key):
        key = self._user_client_live_view_key(user_id, client_id, view_key)
        await self.redis.zrem(key, connection_id)
        logger.debug(
            'Cleared live view presence',
            extra={
                'user_id': int(user_id),
                'connection_id': connection_id,
                'client_id': client_id,
                'view_key': view_key,
            },
        )

    async def has_live_view(self, user_id, *, client_id, view_key):
        key = self._user_client_live_view_key(user_id, client_id, view_key)
        now = now_ts()
        await self.redis.zremrangebyscore(key, '-inf', now)
        return int(await self.redis.zcard(key)) > 0

    async def get_room_members(self, room_id):
        return sorted(int(member) for member in await self.redis.smembers(self._room_members_key(room_id)))

    async def _delete_room(self, room_id, *, meta, remaining_members, nearby_viewer_ids):
        requester_ids = await self._clear_join_requests_for_room(room_id)
        nearby_viewer_ids.update(requester_ids)
        await self.publish_room_deleted(room_id)
        for member in remaining_members:
            await self.redis.zrem(self._user_rooms_key(member), room_id)
            await self.redis.hdel(self._user_room_prefs_key(member), room_id)
        pair_key = meta.get('pair_key') or meta.get('dm_key')
        if pair_key:
            await self.redis.delete(pair_key)
        await self.redis.delete(self._room_meta_key(room_id))
        await self.redis.delete(self._room_members_key(room_id))
        await self.redis.delete(self._room_messages_key(room_id))
        await self.redis.delete(self._room_read_states_key(room_id))
        return {
            'room_deleted': True,
            'remaining_member_ids': [],
            'nearby_viewer_ids': sorted(int(viewer_id) for viewer_id in nearby_viewer_ids),
        }

    async def prune_underpopulated_rooms(self):
        deleted_room_ids = []
        notified_user_ids = set()
        for room_id in [room_id async for room_id in self._iter_room_ids()]:
            meta = await self._load_room_meta(room_id)
            if meta is None:
                continue
            member_ids = await self.get_room_members(room_id)
            valid_member_ids = []
            stale_member_ids = []
            for member_id in member_ids:
                if await self._load_user_hash(member_id) is None:
                    stale_member_ids.append(member_id)
                else:
                    valid_member_ids.append(member_id)
            if stale_member_ids:
                if valid_member_ids:
                    await self.publish_rooms_changed(valid_member_ids)
                await self.redis.srem(self._room_members_key(room_id), *stale_member_ids)
            if len(valid_member_ids) >= 2:
                continue
            nearby_viewer_ids = set(await self.get_room_nearby_update_targets(room_id))
            nearby_viewer_ids.update(stale_member_ids)
            delete_result = await self._delete_room(
                room_id,
                meta=meta,
                remaining_members=valid_member_ids,
                nearby_viewer_ids=nearby_viewer_ids,
            )
            deleted_room_ids.append(int(room_id))
            notified_user_ids.update(delete_result['nearby_viewer_ids'])
        if notified_user_ids:
            await self.publish_nearby_changed(notified_user_ids)
        return deleted_room_ids

    async def cleanup_inactive_data(self, *, current_ts=None):
        await self._ensure_user_activity_index()
        cutoff = self._inactive_user_cutoff_ts(current_ts=current_ts)
        inactive_user_ids = sorted(
            int(user_id)
            for user_id in await self.redis.zrangebyscore(
                'z:user:last_active',
                '-inf',
                cutoff,
            )
        )
        deleted_user_ids = []
        deleted_room_ids = set()
        for user_id in inactive_user_ids:
            if await self._load_user_hash(user_id) is None:
                await self.redis.zrem('z:user:last_active', user_id)
                continue
            room_ids = [
                int(room_id)
                for room_id in await self.redis.zrange(self._user_rooms_key(user_id), 0, -1)
            ]
            if await self.delete_account(user_id):
                deleted_user_ids.append(int(user_id))
                for room_id in room_ids:
                    if await self._load_room_meta(room_id) is None:
                        deleted_room_ids.add(int(room_id))
        deleted_room_ids.update(await self.prune_underpopulated_rooms())
        return {
            'deleted_user_ids': deleted_user_ids,
            'deleted_room_ids': sorted(deleted_room_ids),
        }

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
        pair_key = meta.get('pair_key') or meta.get('dm_key') or ''
        if pair_key:
            await self.redis.delete(pair_key)
            await self.redis.hdel(meta_key, 'pair_key', 'dm_key', 'is_group')

        all_members = sorted({*existing_members, user_id})
        await self._delete_join_request(room_id, user_id)
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
        logger.info(
            'Built room summaries',
            extra={
                'user_id': int(user_id),
                'room_count': len(rooms),
                'room_ids': self._sample_ids(room['id'] for room in rooms),
            },
        )
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
            'is_public': room_bool(meta.get('is_public')),
            'pending_join_request_count': await self.get_room_join_request_count(room_id),
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
        raw_messages = [
            json.loads(message)
            for message in await self.redis.zrevrange(room_messages_key, 0, MAX_MESSAGE_RESULTS - 1)
        ]
        participants_by_id = await self._get_room_participants_by_id(room_id)
        read_states = await self._get_room_read_states(room_id)
        return [
            self._serialize_message_with_state(
                message,
                participants_by_id=participants_by_id,
                read_states=read_states,
            )
            for message in raw_messages
        ]

    async def mark_room_read(self, user_id, room_id, *, message_id=None):
        room_id = int(room_id)
        user_id = int(user_id)
        if not await self.user_in_room(user_id, room_id):
            raise PermissionDenied()

        room_messages_key = self._room_messages_key(room_id)
        if message_id is None:
            latest_messages = await self.redis.zrevrange(room_messages_key, 0, 0)
            if not latest_messages:
                return None
            target_message = json.loads(latest_messages[0])
        else:
            target_message = None
            messages = await self.redis.zrevrange(room_messages_key, 0, -1)
            for encoded_message in messages:
                candidate = json.loads(encoded_message)
                if str(candidate.get('id')) == str(message_id):
                    target_message = candidate
                    break
            if target_message is None:
                raise RoomNotFound()

        next_state = {
            'user_id': user_id,
            'message_id': str(target_message['id']),
            'read_at': ts_ms_to_iso(now_ms()),
        }
        existing_payload = await self.redis.hget(self._room_read_states_key(room_id), user_id)
        if existing_payload:
            try:
                existing_state = json.loads(existing_payload)
            except (TypeError, ValueError, json.JSONDecodeError):
                existing_state = None
            if existing_state is not None:
                existing_sort_key = self._message_sort_key({'id': existing_state.get('message_id')})
                next_sort_key = self._message_sort_key({'id': next_state['message_id']})
                if existing_sort_key >= next_sort_key:
                    return {
                        'user_id': user_id,
                        'message_id': str(existing_state.get('message_id')),
                        'read_at': existing_state.get('read_at'),
                    }

        await self.redis.hset(
            self._room_read_states_key(room_id),
            user_id,
            json.dumps(next_state),
        )
        return next_state

    async def delete_account(self, user_id):
        raw_user = await self._load_user_hash(user_id)
        if raw_user is None:
            return False

        requested_room_ids = await self._clear_join_requests_for_user(user_id)
        room_ids = await self.redis.zrange(self._user_rooms_key(user_id), 0, -1)
        for room_id in room_ids:
            result = await self._remove_user_from_room(user_id, int(room_id))
            if result['remaining_member_ids']:
                await self.publish_rooms_changed(result['remaining_member_ids'])

        await self.redis.delete(self._user_rooms_key(user_id))
        await self.redis.delete(self._user_key(user_id))
        await self.redis.delete(self._username_index_key(raw_user['username']))
        await self.redis.zrem('z:user:last_active', user_id)
        await self.redis.zrem('z:user:last_seen', user_id)
        await self.redis.execute_command('ZREM', 'geo:active_users', user_id)
        await self.redis_bytes.delete(self._user_avatar_key(user_id))
        await self.redis.delete(self._user_room_prefs_key(user_id))
        await self.redis.delete(self._user_rejected_rooms_key(user_id))
        websocket_keys = [self._user_websocket_presence_key(user_id)]
        websocket_keys.extend(
            await self.redis.keys(f'user:{{{user_id}}}:websocket_presence:*')
        )
        if websocket_keys:
            await self.redis.delete(*set(websocket_keys))
        await self.remove_push_subscriptions_for_user(user_id)
        if requested_room_ids:
            for room_id in requested_room_ids:
                await self.publish_room_requests_changed(room_id)
                room_members = await self.get_room_members(room_id)
                if room_members:
                    await self.publish_rooms_changed(room_members)
            await self.publish_nearby_changed([user_id])
        return True

    async def leave_room(self, user_id, room_id):
        room_id = int(room_id)
        user_id = int(user_id)
        if not await self.user_in_room(user_id, room_id):
            raise PermissionDenied()
        return await self._remove_user_from_room(user_id, room_id)

    async def _remove_user_from_room(self, user_id, room_id):
        meta_key = self._room_meta_key(room_id)
        meta = await self.redis.hgetall(meta_key)
        if not meta:
            return {
                'room_deleted': True,
                'remaining_member_ids': [],
            }

        nearby_viewer_ids = set(await self.get_room_nearby_update_targets(room_id))
        nearby_viewer_ids.add(int(user_id))
        members_key = self._room_members_key(room_id)
        await self.redis.srem(members_key, user_id)
        await self.redis.zrem(self._user_rooms_key(user_id), room_id)
        await self.redis.hdel(self._user_room_prefs_key(user_id), room_id)
        await self.redis.hdel(self._room_read_states_key(room_id), user_id)
        remaining_members = sorted(int(member) for member in await self.redis.smembers(members_key))

        should_delete_room = len(remaining_members) < 2

        if should_delete_room:
            delete_result = await self._delete_room(
                room_id,
                meta=meta,
                remaining_members=remaining_members,
                nearby_viewer_ids=nearby_viewer_ids,
            )
            nearby_viewer_ids = set(delete_result['nearby_viewer_ids'])
        if nearby_viewer_ids:
            await self.publish_nearby_changed(nearby_viewer_ids)
        return {
            'room_deleted': should_delete_room,
            'remaining_member_ids': remaining_members,
        }

    def _sample_ids(self, values, *, limit=10):
        return [int(value) for value in list(values)[:limit]]
