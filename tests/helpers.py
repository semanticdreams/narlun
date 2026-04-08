import io
import time

from PIL import Image


BERLIN = (52.52437, 13.41053)
HAMBURG = (53.57532, 10.01534)
MADRID = (40.2085, -3.713)


def random_username():
    return f'test-{time.time_ns()}'


def create_avatar_bytes(color=(0, 128, 255, 255), size=(640, 480)):
    image = Image.new('RGBA', size, color)
    buffer = io.BytesIO()
    image.save(buffer, format='PNG')
    return buffer.getvalue()


async def signup(cli, username=None):
    username = username or random_username()
    response = await cli.post('/api/users/signup', json={'username': username})
    assert response.status == 200
    body = await response.json()
    return {
        'user': body,
        'username': username,
        'jwt': response.cookies['jwt'].value,
    }


def auth_headers(jwt):
    return {'Cookie': f'jwt={jwt}'}


async def signin(cli, username, password):
    response = await cli.post(
        '/api/users/signin',
        json={'username': username, 'password': password},
    )
    return response


async def update_profile(cli, jwt, **payload):
    response = await cli.post(
        '/api/users/update-profile',
        json=payload,
        headers=auth_headers(jwt),
    )
    return response


async def upload_avatar(cli, jwt, avatar_bytes):
    data = {'file': io.BytesIO(avatar_bytes)}
    response = await cli.post(
        '/api/users/upload-profile-picture',
        data=data,
        headers=auth_headers(jwt),
    )
    return response


async def checkin(cli, jwt, location):
    response = await cli.post(
        '/api/social/checkin',
        json={'lat': location[0], 'lon': location[1]},
        headers=auth_headers(jwt),
    )
    assert response.status == 200
    return await response.json()


async def join_user(cli, jwt, user_id):
    response = await cli.post(
        '/api/social/create-room',
        json={'name': '', 'user_ids': [user_id]},
        headers=auth_headers(jwt),
    )
    assert response.status == 200
    return await response.json()


async def create_group_room(cli, jwt, name, user_ids):
    response = await cli.post(
        '/api/social/create-room',
        json={'name': name, 'user_ids': user_ids},
        headers=auth_headers(jwt),
    )
    assert response.status == 200
    return await response.json()


async def create_invite(cli, jwt, room_id):
    response = await cli.post(
        '/api/social/create-invite',
        json={'room_id': room_id},
        headers=auth_headers(jwt),
    )
    assert response.status == 200
    return await response.json()


async def accept_invite(cli, jwt, token):
    response = await cli.post(
        '/api/social/accept-invite',
        json={'token': token},
        headers=auth_headers(jwt),
    )
    return response


async def request_room_join(cli, jwt, room_id):
    response = await cli.post(
        '/api/social/request-room-join',
        json={'room_id': room_id},
        headers=auth_headers(jwt),
    )
    return response


async def get_room_requests(cli, jwt, room_id):
    response = await cli.get(
        f'/api/social/get-room-requests?room_id={room_id}',
        headers=auth_headers(jwt),
    )
    return response


async def approve_room_request(cli, jwt, room_id, user_id):
    response = await cli.post(
        '/api/social/approve-room-request',
        json={'room_id': room_id, 'user_id': user_id},
        headers=auth_headers(jwt),
    )
    return response


async def reject_room_request(cli, jwt, room_id, user_id):
    response = await cli.post(
        '/api/social/reject-room-request',
        json={'room_id': room_id, 'user_id': user_id},
        headers=auth_headers(jwt),
    )
    return response


async def leave_room(cli, jwt, room_id):
    response = await cli.post(
        '/api/social/leave-room',
        json={'room_id': room_id},
        headers=auth_headers(jwt),
    )
    return response


async def send_message(cli, jwt, room_id, body):
    response = await cli.post(
        '/api/social/send-message',
        json={'room_id': room_id, 'body': body},
        headers=auth_headers(jwt),
    )
    assert response.status == 200
    return await response.json()


async def get_rooms(cli, jwt):
    response = await cli.get('/api/social/get-rooms', headers=auth_headers(jwt))
    assert response.status == 200
    return await response.json()


async def get_messages(cli, jwt, room_id):
    response = await cli.post(
        '/api/social/get-messages',
        json={'room_id': room_id},
        headers=auth_headers(jwt),
    )
    return response


async def mark_room_read(cli, jwt, room_id, message_id=None):
    payload = {'room_id': room_id}
    if message_id is not None:
        payload['message_id'] = message_id
    response = await cli.post(
        '/api/social/mark-room-read',
        json=payload,
        headers=auth_headers(jwt),
    )
    return response
