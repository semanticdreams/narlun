# Narlun Frontend

```bash
npm install
make web
make build-web
make browser-e2e
make hotreload
```

The frontend now targets the web only. In production it should be served from
the same origin as the backend API so browser cookies and websocket auth work
without cross-origin fallbacks.

Push notifications use standard Web Push. Production builds must go through
`make build-web` or `./tool/build_web.sh` so the generated Flutter service
worker is post-processed with Narlun's push handlers.

`ui/assets/icon.png` is the single source of truth for app icon assets. Run
`make sync-icons` after changing it to refresh `web/favicon.ico` and the PWA
icons under `web/icons/`. `make build-web` also runs this automatically via the
repo's `uv` environment so web builds cannot drift from the source icon.
