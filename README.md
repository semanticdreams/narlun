# narlun-server

Redis-only backend for Narlun.

## Development

Run a local Redis server and then start the app:

```bash
uv sync
redis-server
uv run python -m app.app
```

The default API port is `3000`.

## Tests

The test suite starts its own disposable Redis instance:

```bash
uv run python -m pytest -svx
```
