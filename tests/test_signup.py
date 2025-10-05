from tests.helpers import random_username


async def test_signup(cli):
    r = await cli.get('/api/users/me')
    assert r.status == 200
    d = await r.json()
    assert d['authenticated'] is False

    r = await cli.post('/api/users/update-profile')
    assert r.status == 401

    username = random_username()
    r = await cli.post('/api/users/signup',
                       json=dict(username=username))
    assert r.status == 200
    d = await r.json()
    assert d['id']
    assert (jwt := r.cookies['jwt'].value)

    r = await cli.get('/api/users/me',
                      cookies=dict(jwt=jwt))
    d = await r.json()
    assert d['username'] == username

    email = username + '@example.com'
    r = await cli.post('/api/users/update-profile',
                       json=dict(email=email),
                       cookies=dict(jwt=jwt))
    assert r.status == 200, await r.json()

    r = await cli.get('/api/users/me',
                      cookies=dict(jwt=jwt))
    d = await r.json()
    assert d['email'] == email

    r = await cli.post('/api/users/signout')
    assert r.status == 204

    r = await cli.post('/api/users/signup',
                       json=dict(username=username))
    assert r.status == 400
    d = await r.json()
    assert d['code'] == 2
    assert d['message'] == 'Username exists'
