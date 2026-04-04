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

For push notifications, use `cd ui && make build-web` so the generated service
worker is patched with the push handlers after the Flutter build finishes.

## Web Push setup

Generate a VAPID keypair locally:

```bash
uv run python scripts/generate_vapid_keys.py
```

Then set these config values for your deployment:

```bash
PUSH_VAPID_PUBLIC_KEY=...
PUSH_VAPID_PRIVATE_KEY=...
PUSH_VAPID_SUBJECT=mailto:admin@example.com
```

If those values are unset, the app still works, but push notifications stay
disabled in the UI and on the backend.

## Tests

The test suite starts its own disposable Redis instance:

```bash
uv run python -m pytest -svx
cd ui && flutter test
cd ui && make browser-e2e
```
