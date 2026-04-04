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
