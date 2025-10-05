import pytest
from app.app import create_app


@pytest.fixture
async def cli(loop, aiohttp_client):
    app = await create_app()
    await app['db'].execute('delete from users')
    client = await aiohttp_client(app)
    return client
