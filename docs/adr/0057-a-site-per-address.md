# ADR-0057: Each of AfriCinemas' sites on its own address

- **Status:** Accepted (13.1b.b: the platform; storefronts follow in 13.1b.c)
- **Date:** 2026-10-23
- **Sub-phase:** P13.1b.b
- **Code:** `web/site.jac`, `web/AppRoot.jac` (`PlatformSite`), `web/platform/*`, `core/platform/accounts.jac` (`platform_address`), `scripts/platform_setup.jac`
- **Tests:** `tests/unit/platform_address_tests.jac`, `e2e/platform_tests.jac` (`PLATFORM_URL`, e2e/support/web.jac)

## Context
The owner wants the platform, the back office and the storefronts to behave as three distinct websites (plan 13.1b, owner decision 2026-10-23): `admin.africinemas.co.ke`, `africinemas.co.ke` and `<slug>.africinemas.co.ke`. Separate accounts came first (ADR-0056). Separate addresses finish the separation in the browser too, because browsers keep each address's storage apart, sign-ins included.

## Decision
1. **One server, one app; the address picks the site.** `web/site.jac` reads the page's host name: one starting with `admin.` is the platform, and anything else is the main site. `AppRoot` gives the platform's address only its own routes (`/`, `/:section`, `/sign-in`, `/join`) and gives the main address none of them. Any other page is "not found". A single-part path on the platform's address is a console section, behind its sign-in.
2. **Development uses `*.localhost`.** `admin.localhost:8000` is the platform. Browsers send every `*.localhost` address to this machine, and Vite's dev server accepts them, so there's nothing to set up. The browser tests use `admin.localhost` on the test server (`PLATFORM_URL`).
3. **No new setting.** The platform's address is `admin.` in front of `AFRICINEMAS_PUBLIC_URL` (without any `www.`). The setup script's join links and the console's invitation links point there.
4. **No redirects from the old `/platform` paths.** They only ever existed in development, and a page that isn't there is plainer than one that sends visitors to the console.
5. **The server is still the guard.** The address only decides which pages are offered. Every platform endpoint still checks the caller's platform account (ADR-0056), whichever address the request comes from.

## Consequences
- The platform's sign-in no longer needs its own slot (ADR-0054). Its address's storage is its own. The slots stay for the storefronts until 13.1b.c moves them to their own addresses.
- Production needs `admin.africinemas.co.ke` in DNS and on the certificate (13.1b.d).
- The desktop and mobile apps, whose host names never start with `admin.`, are the main site, as before.
