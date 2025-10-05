import json
import jwt
import uuid
import io
import aiobotocore
from functools import partial
from asyncpg import Record
from itsdangerous import URLSafeTimedSerializer
from itsdangerous.exc import SignatureExpired, BadTimeSignature, BadSignature
import datetime
import config
import aiohttp

from app.log import get_logger


logger = get_logger()


def jsonify(data):
    return aiohttp.web.json_response(text=json.dumps(data, cls=JSONEncoder))


def no_content():
    return aiohttp.web.Response(status=204)


def one_or_none(x):
    return x[0] if x else None


def get_aws_client(service):
    session = aiobotocore.get_session()
    return session.create_client(service,
                                 region_name=config.AWS_REGION,
                                 aws_access_key_id=config.AWS_ACCESS_KEY,
                                 aws_secret_access_key=config.AWS_SECRET_KEY)


async def upload_fileobj_to_s3(fileobj):
    key = str(uuid.uuid4())
    bucket = 'narlun'
    async with get_aws_client('s3') as client:
        await client.put_object(Bucket=bucket, Key=key, Body=fileobj)
    url = f'https://s3.eu-central-1.amazonaws.com/{bucket}/{key}'
    return url


def create_random_avatar(seed=None):
    import py_avataaars
    import random

    if seed is not None:
        random.seed(seed)

    bytes = io.BytesIO()

    def r(enum_):
        return random.choice(list(enum_))

    avatar = py_avataaars.PyAvataaar(
        style=py_avataaars.AvatarStyle.CIRCLE,
        # style=py_avataaars.AvatarStyle.TRANSPARENT,
        skin_color=r(py_avataaars.SkinColor),
        hair_color=r(py_avataaars.HairColor),
        facial_hair_type=r(py_avataaars.FacialHairType),
        facial_hair_color=r(py_avataaars.HairColor),
        top_type=r(py_avataaars.TopType),
        hat_color=r(py_avataaars.Color),
        mouth_type=r(py_avataaars.MouthType),
        eye_type=r(py_avataaars.EyesType),
        eyebrow_type=r(py_avataaars.EyebrowType),
        nose_type=r(py_avataaars.NoseType),
        accessories_type=r(py_avataaars.AccessoriesType),
        clothe_type=r(py_avataaars.ClotheType),
        clothe_color=r(py_avataaars.Color),
        clothe_graphic_type=r(py_avataaars.ClotheGraphicType),
    )
    avatar.render_png_file(bytes)
    bytes.seek(0)
    return bytes


class InvalidUserIdError(Exception):
    """No user with such id."""

async def create_user(redis, user_id, username, picture):
    """ Create a new user in Redis. """
    current_time = int(time.time())
    user_key = f"user:{user_id}"
    if await redis.hexists(user_key, "id"):
        raise Exception(f"User with id {user_id} already exists.")
    user_data = {
        "id": user_id,
        "username": username,
        "picture": picture,
        "created_at": current_time,
        "last_activity": current_time
    }
    await redis.hmset_dict(user_key, user_data)

async def update_user(redis, user_id, username=None, picture=None):
    """ Update an existing user's username and/or picture. """
    user_key = f"user:{user_id}"
    if not await redis.hexists(user_key, "id"):
        raise Exception(f"User with id {user_id} does not exist.")

    updates = {"last_activity": int(time.time())}
    if username is not None:
        updates["username"] = username
    if picture is not None:
        updates["picture"] = picture

    await redis.hmset_dict(user_key, **updates)

async def delete_user(redis, user_id):
    """ Delete a user from Redis. """
    user_key = f"user:{user_id}"
    if not await redis.hexists(user_key, "id"):
        raise Exception(f"User with id {user_id} does not exist.")
    await redis.delete(user_key)

async def get_user(redis, user_id):
    """ Retrieve a user's data from Redis. """
    user_key = f"user:{user_id}"
    if not await redis.hexists(user_key, "id"):
        raise Exception(f"User with id {user_id} does not exist.")
    user_data = await redis.hgetall(user_key, encoding='utf-8')
    return user_data

async def expire_users(redis):
    """ Check and delete users who have been inactive for more than 48 hours. """
    current_time = int(time.time())
    keys = await redis.keys("user:*")
    for key in keys:
        last_activity = await redis.hget(key, "last_activity", encoding='utf-8')
        if last_activity and (current_time - int(last_activity)) > (48 * 60 * 60):
            user_id = key.decode('utf-8').split(":")[1]
            # TODO cleanup user resources
            await delete_user(redis, user_id)

async def scheduled_user_expiration_check(redis):
    """ Schedule the user expiration check to run every hour. """
    while True:
        await expire_users(redis)
        await asyncio.sleep(3600)  # Sleep for one hour


async def load_user_from_token(req):
    token = req.cookies['jwt']
    jwt_data = jwt.decode(token, config.SECRET_KEY,
                          algorithms=['HS256'])
    user_id = jwt_data['sub']
    return await get_user(req.redis, user_id)


class InvalidUsageCodeExistsError(Exception):
    """An InvalidUsage class with specified error code already exists."""


class InvalidUsageMeta(type):
    subclasses = set()  # type: set

    def __init__(cls, name, bases, dict):
        super(InvalidUsageMeta, cls).__init__(name, bases, dict)
        cls.subclasses.add(cls)
        cls.check_codes()

    def check_codes(cls):
        if len(set(x.code for x in cls.subclasses)) < len(cls.subclasses):
            raise InvalidUsageCodeExistsError()


class InvalidUsage(Exception, metaclass=InvalidUsageMeta):
    status = 400
    message = 'Invalid usage'
    code = 0
    payload = {}


class Unauthorized(InvalidUsage):
    status = 401
    message = 'Not authenticated'
    code = 1


def authenticated(func):
    async def f(req):
        if req.user['authenticated'] is not True:
            raise Unauthorized()
        return await func(req)
    return f


class JSONEncoder(json.JSONEncoder):
    def __init__(self, *args, date_only=False, **kwargs):
        self.date_only = date_only
        super().__init__(*args, **kwargs)

    def default(self, obj):
        if isinstance(obj, datetime.datetime):
            if self.date_only:
                return obj.strftime('%Y-%m-%d')
            return obj.isoformat()
        if isinstance(obj, Record):
            return dict(obj)
        return json.JSONEncoder.default(self, obj)


class Schema:
    def __init__(self, data):
        self.data = data

    def dump_self(self):
        return dict(self.data)

    @classmethod
    def dump(cls, items, many=False):
        if many:
            return [x.dump_self() for x in items]
        return items.dump_self()

    @classmethod
    def json(cls, items, many=False, date_only=False):
        return json.dumps(cls.dump(items, many=many),
                          cls=partial(JSONEncoder, date_only=date_only))


class TokenExpiredError(InvalidUsage):
    code = 101
    message = 'Token expired'


class TokenInvalidError(InvalidUsage):
    code = 102
    message = 'Token invalid'


def generate_confirmation_token(email, action):
    serializer = URLSafeTimedSerializer(config.SECRET_KEY)
    return serializer.dumps(
        email, salt=action)


def confirm_token(token, action, expiration=86400):
    serializer = URLSafeTimedSerializer(config.SECRET_KEY)

    try:
        email = serializer.loads(
            token,
            salt=action,
            max_age=expiration
        )
    except SignatureExpired:
        raise TokenExpiredError()
    except (BadSignature, BadTimeSignature):
        raise TokenInvalidError()

    return email


async def send_email(recipients, subject, html='', text='', sender=None):
    if sender is None:
        sender = config.EMAIL_SENDER

    async with get_aws_client('ses') as client:
        await client.send_email(
            Source=sender,
            Destination={'ToAddresses': recipients},
            Message={
                'Subject': {'Data': subject},
                'Body': {
                    'Text': {'Data': text},
                    'Html': {'Data': html}
                }
            }
        )
