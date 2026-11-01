# JI-063: A served web app made a PWA installs, but never opens without a connection

- **Version:** Jac 0.38.3
- **Found:** 2026-10-31, while specifying the offline scanner (`docs/specs/offline-scanner.md`, 17.2b), by reading `jaclang/client/targets/impl/pwa_build.impl.jac` and `jaclang/client/impl/serving.impl.jac`. Not yet run.
- **Status:** open; we'll write our own service worker for the scanner.

## What the source does

With a `[client.pwa]` table, `jac build` writes `manifest.json`, `sw.js` and icons into the client's `dist/`, and the served page registers the worker:

```js
navigator.serviceWorker.register('/static/sw.js')
```

The guide says this gives "Offline support via Service Worker". For an app served by `jac run`, it can't:

1. **The worker's scope is `/static/`.** A service worker controls only pages under its own folder unless the server sends `Service-Worker-Allowed`, and nothing in Jac sends it. The app's pages (`/`, `/app/...`) are outside `/static/`, so the worker never sees their navigations; with no connection the browser shows its offline error.
2. **The precached files aren't the ones the page asks for.** `PRECACHE_ASSETS` lists `./` (that is, `/static/`) and the top-level files of `dist/` (`./client.<hash>.js`, `./styles.css`), but the served page loads `/static/client.js?hash=<hash>` and `/static/styles.css?hash=<hash>`. `dist/assets/` (e.g. the QR worker) isn't listed at all: `_get_precache_files` doesn't look in subfolders.
3. **Nothing fetched later is kept.** The fetch handler is cache-first for everything except `/api/`, but only `/api/` responses are put in the cache; Jac's endpoints are `/function/<name>` and `/walker/<name>`, so no response is ever kept.
4. **After a deploy it may serve an old app.** The cache name is fixed (`jac-pwa-cache-v1` unless set) and `sw.js` changes only when the list of top-level file names does, so a cache-first entry can outlive the deploy that replaced it.

## What we'd expect

Either the worker is served from the app's root (or with `Service-Worker-Allowed: /`), precaches what the served page actually loads, and keeps the page shell for offline navigations, with a cache name that changes with each build; or the guide says the PWA support is installability only.

## Workaround

Our own service worker for the scanner, served from a custom route at the site's root, which keeps the scanner page, the client bundle, the styles and the QR worker, with the bundle's hash in its cache name (spec §5 D1).
