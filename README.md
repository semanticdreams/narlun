# narlun-server

[![Tests](https://github.com/semanticdreams/narlun/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/semanticdreams/narlun/actions/workflows/test.yml)

Redis-only backend for Narlun.

## Development

Run a local Redis server and then start the app:

```bash
uv sync
redis-server
uv run python -m app.app
```

The default API port is `3000`.

For the web frontend:

```bash
cd ui
flutter pub get
npm install
make web
```

Production builds should use `flutter build web --release` and be served from
the same origin as `/api`.

## Tests

The test suite starts its own disposable Redis instance:

```bash
uv run python -m pytest -svx
cd ui && flutter test
cd ui && make browser-e2e
```
