import socket
import subprocess
import time

import aiohttp
import pytest

from app.app import create_app


def find_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


@pytest.fixture(scope='session')
def redis_url(tmp_path_factory):
    port = find_free_port()
    data_dir = tmp_path_factory.mktemp('redis-data')
    process = subprocess.Popen([
        'redis-server',
        '--save', '',
        '--appendonly', 'no',
        '--port', str(port),
        '--dir', str(data_dir),
    ])

    url = f'redis://127.0.0.1:{port}/0'
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                pass
        except Exception:
            time.sleep(0.1)
            continue
        else:
            break
    else:
        process.terminate()
        raise RuntimeError('Redis test server did not start')

    yield url

    process.terminate()
    process.wait(timeout=10)


@pytest.fixture
async def cli(aiohttp_client, redis_url):
    app = await create_app(redis_url=redis_url, enable_cors=False)
    await app['redis'].flushdb()
    client = await aiohttp_client(app, cookie_jar=aiohttp.DummyCookieJar())
    return client
