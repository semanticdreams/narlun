import jwt
import datetime
import asyncpg
import json
from email_validator import validate_email, EmailNotValidError
from werkzeug.security import generate_password_hash, check_password_hash
from aiohttp import web

from app.util import authenticated, jsonify, no_content, \
        InvalidUsage, create_random_avatar, upload_fileobj_to_s3, \
        generate_confirmation_token, confirm_token, \
        send_email, JSONEncoder

import config


# logger = get_logger()

routes = web.RouteTableDef()


class UsernameExistsError(InvalidUsage):
    code = 2
    message = 'Username exists'


class PasswordTooShortError(InvalidUsage):
    code = 3
    message = 'Password must be at least 8 characters long'


class InvalidEmailError(InvalidUsage):
    code = 4

    def __init__(self, msg):
        self.message = 'Invalid email: ' + msg


class UnknownUserError(InvalidUsage):
    code = 5
    message = 'Unknown user'

    def __init__(self, **kwargs):
        self.payload = kwargs


class BadPasswordError(InvalidUsage):
    code = 6
    message = 'Bad password'


@routes.get('/me')
async def get_me(req):
    """Return authentication status and user data."""
    return jsonify(req.user)


@routes.post('/signup')
async def signup(req):
    try:
        user = dict(await req.db.fetchrow(
                'insert into users (username) values ($1)'
                ' returning id, username, email, picture, password_hash, about_me, phone',
                req.data['username']
                ))
    except asyncpg.exceptions.UniqueViolationError:
        raise UsernameExistsError()

    # Set random avatar
    url = await upload_fileobj_to_s3(create_random_avatar())
    await req.db.execute('update users set picture = $2 where id = $1',
                         user['id'], url)
    user['picture'] = url
    user['authenticated'] = True
    user['has_password'] = True if user.pop('password_hash') else False
    # TODO add roles

    token = jwt.encode(dict(
        sub=user['id'],
        iat=datetime.datetime.utcnow()
    ),
        config.SECRET_KEY
    )
    resp = jsonify(user)
    resp.set_cookie('jwt', token, path='/api', httponly=True,
                    samesite='Lax', secure=True)
    return resp


@routes.post('/signin')
async def signin(req):
    """Handle all types of signins: email, token and password."""
    if req.data['method'] == 'email':
        user = await req.db.fetchrow('select email from users where email = $1',
                                     req.data['email'])
        if user is None:
            raise UnknownUserError(email=req.data['email'])
        token = generate_confirmation_token(user['email'], 'signin')
        signin_url = config.DOMAIN + '/signin?token=' + token
        html = signin_url
        subject = 'Sign in to narlun'
        await send_email([req.data['email']], subject, html)
        return jsonify(dict(authenticated=False, email_sent=True))
    elif req.data['method'] == 'token':
        email = confirm_token(req.data['token'], 'signin')
        user = dict(await req.db.fetchrow(
            'select * from users where email = $1', email))
        if user is None:
            raise UnknownUserError(token=req.data['token'])
    else:
        assert req.data['method'] == 'password'
        user = dict(await req.db.fetchrow(
            'select * from users where username = $1', req.data['username']))
        if user is None:
            raise UnknownUserError(username=req.data['username'])
        if not check_password_hash(user['password_hash'], req.data['password']):
            raise BadPasswordError()
    user['authenticated'] = True
    user['has_password'] = True if user.pop('password_hash') else False
    # TODO add roles
    token = jwt.encode(dict(
        sub=user['id'],
        iat=datetime.datetime.utcnow()
    ),
        config.SECRET_KEY
    )
    resp = jsonify(user)
    resp.set_cookie('jwt', token, path='/api', httponly=True,
                    samesite='Lax', secure=True)
    return resp


@routes.post('/update-profile')
@authenticated
async def update_profile(req):
    """Update user data."""

    # Validate and update email
    if (email := req.data.get('email')) is not None:
        if email == '':
            email = None
        else:
            try:
                email = validate_email(
                    email,
                    check_deliverability=True).email
            except EmailNotValidError as e:
                raise InvalidEmailError(str(e))
        await req.db.execute('update users set email = $2 where id = $1',
                             req.user['id'], email)

    # Update username
    if (username := req.data.get('username')) is not None:
        # TODO should validate
        await req.db.execute('update users set username = $2 where id = $1',
                             req.user['id'], username)

    # Update password
    if (password := req.data.get('password')) is not None:
        if password == '':
            password_hash = None
        elif len(password) < 8:
            raise PasswordTooShortError()
        else:
            password_hash = generate_password_hash(password)
        await req.db.execute('update users set password_hash = $2 where id = $1',
                             req.user['id'], password_hash)

    # Update about_me
    if (about_me := req.data.get('about_me')) is not None:
        await req.db.execute('update users set about_me = $2 where id = $1',
                             req.user['id'], about_me)

    # Update phone
    if (phone := req.data.get('phone')) is not None:
        await req.db.execute('update users set phone = $2 where id = $1',
                             req.user['id'], phone)

    # Return updated user data
    return jsonify(await load_user_by_id(req.db, req.user['id']))


@routes.post('/upload-profile-picture')
@authenticated
async def upload_profile_picture(req):
    """Save uploaded picture and set as avatar."""
    data = await req.post()
    url = await upload_fileobj_to_s3(data['file'])
    await req.db.execute('update users set picture = $2 where id = $1',
                         req.user['id'], url)
    return jsonify({'picture': url})


@routes.post('/signout')
async def signout(req):
    """Remove jwt cookie and trigger ws disconnect through redis."""
    resp = no_content()
    resp.del_cookie('jwt', path='/api')
    if req.user['authenticated']:
        await req.redis.publish(f'narlun:users:{req.user["id"]}',
                                json.dumps(
                                    {'type': 'signout'},
                                    cls=JSONEncoder))
    return resp


def create_app():
    app = web.Application()
    app.add_routes(routes)
    return app
