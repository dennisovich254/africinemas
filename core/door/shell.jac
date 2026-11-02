"""The offline scanner's app shell (plan 17.2b, docs/specs/offline-scanner.md §5 D1, §13).

The installed scanner is a small app at /door/: its page is the app's own (any path
without an extension serves it), and these routes add what makes it installable and
able to open with no connection, since Jac's [client.pwa] can't (JI-063):

- GET /door/sw.js: the service worker, scope /door/. It keeps one cache per version
  of the app ("door-shell-<bundle hash>"): the scanner page, network first; the
  bundle, styles, fonts and QR worker under /static/, cache first, kept as the page
  loads them (and the files the page loaded before the worker took over, which the
  page sends it). It never touches /function/ or /walker/ answers.
- GET /door/manifest.webmanifest: id, start_url and scope /door/.

Trial S1: the worker takes over at once; activating only with an empty journal (§13)
comes with the journal.
"""

import json;
import from http { HTTPMethod }
import from jaclang.server.serving.datatypes { Response }

glob SW_JS: str = """// AfriCinemas scanner: the offline shell (docs/specs/offline-scanner.md §13).
const PREFIX = 'door-shell-';
const META = 'door-meta';
const SHELL = '/door/__shell__';
const VERSION_KEY = '/door/__version__';
const NAV_TIMEOUT_MS = 4000;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

async function version() {
  const meta = await caches.open(META);
  const kept = await meta.match(VERSION_KEY);
  return kept ? kept.text() : '';
}

async function current() {
  const v = await version();
  return v ? caches.open(PREFIX + v) : null;
}

async function keep(v, urls, shell) {
  // Stores this version's files, then makes it current and drops the others.
  const cache = await caches.open(PREFIX + v);
  for (const url of urls) {
    if (!(await cache.match(url))) {
      try {
        const got = await fetch(url, { cache: 'reload' });
        if (got.ok) { await cache.put(url, got); }
      } catch (e) { /* kept on its next load */ }
    }
  }
  try {
    const page = await fetch(shell, { cache: 'reload' });
    if (page.ok) { await cache.put(SHELL, page); }
  } catch (e) { /* the next navigation keeps it */ }
  const meta = await caches.open(META);
  await meta.put(VERSION_KEY, new Response(v));
  for (const name of await caches.keys()) {
    if (name.startsWith(PREFIX) && name !== PREFIX + v) { await caches.delete(name); }
  }
  return (await cache.keys()).length;
}

self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type !== 'keep' || !data.version) { return; }
  const reply = event.ports && event.ports[0];
  event.waitUntil(
    keep(data.version, data.urls || [], data.shell || '/door/')
      .then((count) => reply && reply.postMessage({ ok: true, version: data.version, count }))
      .catch((e) => reply && reply.postMessage({ ok: false, error: String(e) }))
  );
});

function withTimeout(promise, ms) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), ms);
    promise.then((r) => { clearTimeout(timer); resolve(r); },
                 (e) => { clearTimeout(timer); reject(e); });
  });
}

async function page(request) {
  // The scanner page: the network's if it answers soon, else the kept one.
  try {
    const got = await withTimeout(fetch(request), NAV_TIMEOUT_MS);
    if (got.ok) {
      const cache = await current();
      if (cache) { await cache.put(SHELL, got.clone()); }
      return got;
    }
  } catch (e) { /* offline, or too slow */ }
  const cache = await current();
  const kept = cache && (await cache.match(SHELL));
  return kept || new Response('The scanner is offline and not ready yet.', {
    status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
}

async function asset(request) {
  const cache = await current();
  const kept = cache && (await cache.match(request));
  if (kept) { return kept; }
  const got = await fetch(request);
  if (got.ok && cache) { await cache.put(request, got.clone()); }
  return got;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) { return; }
  if (request.mode === 'navigate' && url.pathname.startsWith('/door/')) {
    event.respondWith(page(request));
  } else if (url.pathname.startsWith('/static/')) {
    event.respondWith(asset(request));
  }
});
""",
     MANIFEST: dict[str, any] = {  # jac:ignore[W1037]
         "id": "/door/",
         "name": "AfriCinemas Scanner",
         "short_name": "Scanner",
         "description": "Scan tickets at the door, even when the connection drops.",
         "start_url": "/door/",
         "scope": "/door/",
         "display": "standalone",
         "orientation": "portrait",
         "background_color": "#111118",
         "theme_color": "#111118",
         "icons": [
             {
                 "src": "/static/assets/door/icon-192.png",
                 "sizes": "192x192",
                 "type": "image/png"
             },
             {
                 "src": "/static/assets/door/icon-512.png",
                 "sizes": "512x512",
                 "type": "image/png"
             },
             {
                 "src": "/static/assets/door/icon-512.png",
                 "sizes": "512x512",
                 "type": "image/png",
                 "purpose": "maskable"
             }
         ]
     };

@restspec(method=HTTPMethod.GET, path="/door/sw.js", envelope=False)
def:pub door_service_worker -> Response {
    # Never cached by the browser's HTTP cache, so a new worker is seen at once.
    return Response(
        content=SW_JS,
        media_type="text/javascript; charset=utf-8",
        headers={"Cache-Control": "no-cache", "Service-Worker-Allowed": "/door/"}
    );
}

@restspec(method=HTTPMethod.GET, path="/door/manifest.webmanifest", envelope=False)
def:pub door_manifest -> Response {
    return Response(
        content=json.dumps(MANIFEST),
        media_type="application/manifest+json",
        headers={"Cache-Control": "no-cache"}
    );
}
