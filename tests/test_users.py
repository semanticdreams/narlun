from tests.helpers import create_avatar_bytes, random_username, signin, signup, update_profile


async def test_guest_signup_password_upgrade_and_signin(cli):
    response = await cli.get('/api/users/me')
    assert response.status == 200
    body = await response.json()
    assert body['authenticated'] is False

    created = await signup(cli)
    assert created['user']['authenticated'] is True
    assert created['user']['has_password'] is False
    assert created['user']['picture'].startswith('/api/users/avatar/')

    response = await update_profile(
        cli,
        created['jwt'],
        password='correct horse battery',
        about_me='hello',
        phone='123',
    )
    assert response.status == 200
    me = await response.json()
    assert me['has_password'] is True
    assert me['about_me'] == 'hello'
    assert me['phone'] == '123'

    await cli.post('/api/users/signout', cookies={'jwt': created['jwt']})

    response = await signin(cli, created['username'], 'correct horse battery')
    assert response.status == 200
    signed_in = await response.json()
    assert signed_in['username'] == created['username']
    assert signed_in['has_password'] is True


async def test_guest_signout_deletes_account(cli):
    created = await signup(cli)

    response = await cli.post('/api/users/signout', cookies={'jwt': created['jwt']})
    assert response.status == 204

    response = await signin(cli, created['username'], 'does-not-matter')
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 5


async def test_avatar_upload_and_fetch(cli):
    created = await signup(cli)
    avatar = create_avatar_bytes()

    response = await cli.post(
        '/api/users/upload-profile-picture',
        data={'file': avatar},
        cookies={'jwt': created['jwt']},
    )
    assert response.status == 200
    body = await response.json()
    assert body['picture'].startswith('/api/users/avatar/')

    avatar_response = await cli.get(body['picture'])
    assert avatar_response.status == 200
    assert avatar_response.content_type == 'image/png'
    payload = await avatar_response.read()
    assert payload.startswith(b'\x89PNG')


async def test_invalid_avatar_upload_returns_usage_error(cli):
    created = await signup(cli)

    response = await cli.post(
        '/api/users/upload-profile-picture',
        data={'file': b'not-an-image'},
        cookies={'jwt': created['jwt']},
    )
    assert response.status == 400
    body = await response.json()
    assert body['code'] == 8


async def test_delete_account_removes_permanent_user(cli):
    username = random_username()
    created = await signup(cli, username=username)
    response = await update_profile(cli, created['jwt'], password='permanent123')
    assert response.status == 200

    response = await cli.delete('/api/users/me', cookies={'jwt': created['jwt']})
    assert response.status == 204

    response = await signin(cli, username, 'permanent123')
    assert response.status == 400
