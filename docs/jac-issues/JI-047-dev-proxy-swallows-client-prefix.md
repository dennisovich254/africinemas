# JI-047: In `--dev` mode, a server route with a path parameter sends every page under its prefix to the API

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-10, P8.6c (`jac run --dev main.jac`); the cause landed in P8.3
- **Status:** open (we serve with `--no-dev`: `scripts/dev_daraja.sh`, e2e)

## What we saw
With `jac run --dev main.jac`, every storefront page (`/c/westgate`, `/c/westgate/sign-up`, ...) answered the API server's JSON `404 Not Found` instead of the web app. `jac run --no-dev` (our `scripts/dev_daraja.sh` and the e2e server) serves the same pages correctly.

The cinema connector is `@restspec(path="/c/{slug}/mcp")` (P8.3). For the Vite dev proxy, Jac cuts a parameterised route at its first `{` and proxies the whole prefix. The generated `.jac/client/configs/vite.dev.config.js` gets:

```js
"/c": { target: "http://localhost:8001", changeOrigin: true },
```

so Vite forwards `/c/*` (the client's storefront routes) to the API. `client_claimed_paths` only checks Jac's built-in prefixes (`/api`, `/walker`, ...), so a client route can't claim `/c` back. The logic is in `jaclang/client/impl/vite_bundler.impl.jac`, in the `declared_path.split('{')[0]` branch.

## Workaround (in place)
Run the app with `--no-dev` (`scripts/dev_daraja.sh`). A client change then needs a restart instead of hot reload.

## Suggestion upstream
Proxy a parameterised route as an anchored regex (for example `^/c/[^/]+/mcp$`), the way exact routes already get `^...$`, instead of its bare static prefix. Or skip prefixes that the client router's routes use.
