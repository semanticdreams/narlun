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
        cookies={'jwt': jwt},
    )
    return response


async def upload_avatar(cli, jwt, avatar_bytes):
    data = {'file': avatar_bytes}
    response = await cli.post(
        '/api/users/upload-profile-picture',
        data=data,
        cookies={'jwt': jwt},
    )
    return response


async def checkin(cli, jwt, location):
    response = await cli.post(
        '/api/social/checkin',
        json={'lat': location[0], 'lon': location[1]},
        cookies={'jwt': jwt},
    )
    assert response.status == 200
    return await response.json()


async def join_user(cli, jwt, user_id):
    response = await cli.post(
        '/api/social/join-user',
        json={'user_id': user_id},
        cookies={'jwt': jwt},
    )
    assert response.status == 200
    return await response.json()


async def create_group_room(cli, jwt, name, user_ids):
    response = await cli.post(
        '/api/social/create-room',
        json={'name': name, 'user_ids': user_ids},
        cookies={'jwt': jwt},
    )
    assert response.status == 200
    return await response.json()


async def send_message(cli, jwt, room_id, body):
    response = await cli.post(
        '/api/social/send-message',
        json={'room_id': room_id, 'body': body},
        cookies={'jwt': jwt},
    )
    assert response.status == 200
    return await response.json()


async def get_rooms(cli, jwt):
    response = await cli.get('/api/social/get-rooms', cookies={'jwt': jwt})
    assert response.status == 200
    return await response.json()


async def get_messages(cli, jwt, room_id):
    response = await cli.post(
        '/api/social/get-messages',
        json={'room_id': room_id},
        cookies={'jwt': jwt},
    )
    return response
