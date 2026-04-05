from pathlib import Path

from app.app import create_app


async def test_web_root_serves_spa_routes_without_swallowing_api_or_missing_assets(
    aiohttp_client,
    redis_url,
    monkeypatch,
    tmp_path,
):
    web_root = tmp_path / 'web'
    web_root.mkdir()
    (web_root / 'index.html').write_text('<!doctype html><html><body>app-shell</body></html>')
    (web_root / 'app.js').write_text('console.log("ok");')

    monkeypatch.setattr('config.WEB_ROOT', str(web_root))
    app = await create_app(redis_url=redis_url, enable_cors=False)
    await app['redis'].flushdb()
    client = await aiohttp_client(app)

    root = await client.get('/')
    assert root.status == 200
    assert 'app-shell' in await root.text()

    app_route = await client.get('/rooms')
    assert app_route.status == 200
    assert 'app-shell' in await app_route.text()

    asset = await client.get('/app.js')
    assert asset.status == 200
    assert await asset.text() == 'console.log("ok");'

    missing_asset = await client.get('/missing.js')
    assert missing_asset.status == 404

    missing_api = await client.get('/api/does-not-exist')
    assert missing_api.status == 404

    hidden_probe = await client.get('/.git/config')
    assert hidden_probe.status == 404
