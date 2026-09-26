# ADR-0001: The desktop app reuses the web UI through a shared `AppRoot`

- **Status:** Accepted (compile-verified locally; the full native build is verified by the `build-desktop` CI job from P0.5)
- **Date:** 2026-09-26
- **Sub-phase:** P0.2

## Context

The plan ships one Jac workspace with three apps: `web` (`web-app`), `desktop` (`desktop`) and `mobile` (`mobile`). The desktop app is the counter/box-office/admin station and should have **every web feature without a second UI codebase**.

`jac create --app desktop --kind desktop` scaffolds its own `desktop/main.jac` with an unrelated demo UI. By default the desktop app also runs its **own embedded server and database** (`[desktop] backend = "embedded"`). That would give a counter PC a separate seat inventory from the website and allow double-booking.

## Decision

1. **Shared root component.** The web UI's root lives in a plain module, `web/AppRoot.jac`, exporting `AppRoot`. It is not an app entry, so no app boundary applies. Both entry points render it:
   - `main.jac` (web): `def:pub app -> JsxElement { return <AppRoot />; }`
   - `desktop/main.jac`: the same, plus the global stylesheet import.

   Every screen is written once, under `web/`. Desktop-only additions (P9.2: file export, OS notifications) are small components that the desktop entry can wrap around `AppRoot`.
2. **Remote backend, never embedded.** `jac.toml` sets `[desktop] backend = "${AFRICINEMAS_SERVER_URL:-http://localhost:8000}"`. The desktop binary is a native window onto the shared server. All walkers and functions run there, against the one database.
3. **Client imports use the dotted relative form** (`import from ..web.AppRoot { AppRoot }`), which is what the bundler resolves (Jac guide `jac-cl-organization`).

## Evidence

- `jac check --app web` and `jac check --app desktop` both pass with the shared `AppRoot`.
- `jac run --dev web` serves the page (Vite 6.4.3), and `POST /function/app_info` returns 200.
- A local native desktop build could not complete: Jac's desktop toolchain installs `g++ pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev` via non-interactive `sudo -n apt-get`, which fails without cached sudo credentials. See "Consequences".

## Consequences

- Desktop inherits the responsive web UI (plan §1.1) at its window size (min 1024×700), so it gets the PC layouts.
- **Local desktop builds need a one-time system install** by the developer: `sudo apt-get install -y g++ pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev`, then `jac setup --toolchain desktop`. CI runners have passwordless sudo, so the `build-desktop` job provisions this automatically.
- Jac can't cross-compile desktop builds. A Windows counter PC build has to be made on Windows (P9.1).

## Other findings from the spike (for later phases)

- `jac run --faux` lists `def:pub` functions under a heading "FUNCTIONS (Authenticated)", but a real server answers them **without a token** (verified with `curl`). Don't use the `--faux` headings for security decisions; the isolation tests (P2.4) are the source of truth.
- For `web-app` kind, `jac run web` starts **dev mode** on ports 8000 (Vite) and 8001 (API) and ignores `--port`. A stale server holding a port pushes the API to the next free port. Stop stale servers with `pkill -f "[j]ac run"`.
- On CPUs without AVX2 (e.g. Celeron N4020), Jac's bundled bun crashes with "Illegal instruction". The fix is bun's baseline build via `JAC_BUN`, which `scripts/doctor.sh` now checks.
- The server boots Jac's built-in platform admin (`admin`) with a **default password** and logs a warning. P0.7's production-config tests must prove it's changed or disabled.
