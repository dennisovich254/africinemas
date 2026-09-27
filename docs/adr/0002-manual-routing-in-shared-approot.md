# ADR-0002: Manual routing inside the shared `AppRoot`

- **Status:** Accepted
- **Date:** 2026-09-27
- **Sub-phase:** P0.8c

## Context

P0.8c adds the first screens beyond the welcome card: a responsive shell and a living style guide at `/design-system`. That needs client-side routing.

Jac offers two routing systems (Jac guide `jac-cl-routing`) and says to pick one and never mix them:

- **File-based routing (the guide's default).** Files under `pages/` become routes, and `main.jac` must export `def:pub app(children)`, which receives the generated router tree.
- **Manual routing.** One component declares `<Router>`/`<Routes>`/`<Route>` from `@jac/runtime`, and `main.jac` mounts it with a no-argument `app()`.

ADR-0001 requires the web and desktop apps to render **the same root component** (`web/AppRoot.jac`), so every screen is written once. With file-based routing, the route tree is generated per app from that app's own `pages/` directory. The desktop entry (`desktop/main.jac`) would need its own `pages/` tree or some unverified way to share one. That reopens the duplication ADR-0001 closed.

## Decision

1. **Manual routing.** `web/AppRoot.jac` owns the only `<Router>` and route table. Both entry points keep rendering `<AppRoot />` unchanged, so the desktop app gets every route automatically.
2. **There is no `pages/` directory** anywhere in the workspace. Route components live in `web/routes/`. Shared layout components live in `web/shell/`.
3. **Routes so far:**
   - `/` is the storefront welcome.
   - `/design-system` and `/design-system/:section` are the living style guide. It hosts the shell components with demo data, so browser e2e tests and UI reviews exercise them in the production bundle.
   - `*` renders a not-found page.
4. **In-app links use `Link` and `useNavigate`** from `@jac/runtime`, never `<a href>`, which would trigger a full reload.

## Consequences

- There are no automatic `(auth)/` route guards. Protected areas (from P2) wrap their routes in `AuthGuard` explicitly in the route table. Tests cover each guard.
- Clean URLs (`/design-system`) need an SPA fallback. `jac run` provides it. Any other production host must also serve the app HTML for unknown paths (P10).
- The style guide ships in production. It shows only demo data and no tenant data, so it's safe to expose. It doubles as the UI review page.
