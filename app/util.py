import datetime
import io
import json
import random
from functools import wraps

import aiohttp
import jwt
import py_avataaars

import config


def jsonify(data):
    return aiohttp.web.json_response(text=json.dumps(data, cls=JSONEncoder))


def no_content():
    return aiohttp.web.Response(status=204)


def anonymous_user():
    return {
        'authenticated': False,
        'has_password': False,
    }


def create_random_avatar(seed=None):
    if seed is not None:
        random.seed(seed)

    bytes_io = io.BytesIO()

    def choose(enum_):
        return random.choice(list(enum_))

    avatar = py_avataaars.PyAvataaar(
        style=py_avataaars.AvatarStyle.CIRCLE,
        skin_color=choose(py_avataaars.SkinColor),
        hair_color=choose(py_avataaars.HairColor),
        facial_hair_type=choose(py_avataaars.FacialHairType),
        facial_hair_color=choose(py_avataaars.HairColor),
        top_type=choose(py_avataaars.TopType),
        hat_color=choose(py_avataaars.Color),
        mouth_type=choose(py_avataaars.MouthType),
        eye_type=choose(py_avataaars.EyesType),
        eyebrow_type=choose(py_avataaars.EyebrowType),
        nose_type=choose(py_avataaars.NoseType),
        accessories_type=choose(py_avataaars.AccessoriesType),
        clothe_type=choose(py_avataaars.ClotheType),
        clothe_color=choose(py_avataaars.Color),
        clothe_graphic_type=choose(py_avataaars.ClotheGraphicType),
    )
    avatar.render_png_file(bytes_io)
    bytes_io.seek(0)
    return bytes_io


def is_request_secure(req):
    forwarded_proto = req.headers.get('X-Forwarded-Proto', '')
    return req.secure or forwarded_proto == 'https'


def get_token_from_request(req):
    auth_header = req.headers.get('Authorization', '')
    if auth_header.startswith('Bearer '):
        return auth_header.split(' ', 1)[1]

    token = req.query.get('token')
    if token:
        return token

    return req.cookies.get('jwt')


async def load_user_from_token(req):
    token = get_token_from_request(req)
    if token is None:
        return anonymous_user()

    try:
        jwt_data = jwt.decode(token, config.SECRET_KEY, algorithms=['HS256'])
    except jwt.PyJWTError:
        return anonymous_user()

    user_id = jwt_data.get('sub')
    if user_id is None:
        return anonymous_user()

    user = await req.store.get_authenticated_user(int(user_id))
    if user is None:
        return anonymous_user()
    return user


class InvalidUsageCodeExistsError(Exception):
    pass


class InvalidUsageMeta(type):
    subclasses = set()

    def __init__(cls, name, bases, namespace):
        super().__init__(name, bases, namespace)
        cls.subclasses.add(cls)
        cls.check_codes()

    def check_codes(cls):
        if len(set(subclass.code for subclass in cls.subclasses)) < len(cls.subclasses):
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
    @wraps(func)
    async def wrapped(req):
        if req.user.get('authenticated') is not True:
            raise Unauthorized()
        return await func(req)

    return wrapped


class JSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime.datetime):
            return obj.isoformat()
        return super().default(obj)
