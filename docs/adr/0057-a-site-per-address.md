# ADR-0057: Each of AfriCinemas' sites on its own address

- **Status:** Accepted (13.1b.b: the platform; 13.1b.c: the storefronts; 13.1b.d: deploying them)
- **Date:** 2026-10-23
- **Sub-phase:** P13.1b.b, P13.1b.c, P13.1b.d
- **Code:** `core/site.jac` (`site_for_host`, `storefront_address`, `platform_address`), `web/site.jac`, `web/AppRoot.jac` (`PlatformSite`, `StorefrontSite`, `MainSite`), `web/shell/AppLink.jac` (`local_path`), `web/platform/*`, `core/booking/ticket_delivery.jac` and `core/mcp/server.jac` (links sent out), `scripts/platform_setup.jac`
- **Tests:** `tests/unit/site_tests.jac`, `e2e/platform_tests.jac` (`PLATFORM_URL`), `e2e/storefront_address_tests.jac` (`MAIN_URL`, `store_url`; e2e/support/web.jac)

## Context
The owner wants the platform, the back office and the storefronts to behave as three distinct websites (plan 13.1b, owner decision 2026-10-23): `admin.africinemas.co.ke`, `africinemas.co.ke` and `<slug>.africinemas.co.ke`. Separate accounts came first (ADR-0056). Separate addresses finish the separation in the browser too, because browsers keep each address's storage apart, sign-ins included.

## Decision
1. **One server, one app; the address picks the site.** The sites live under one domain, `AFRICINEMAS_SITE_DOMAIN` (`africinemas.co.ke`; by default the host of `AFRICINEMAS_PUBLIC_URL`):
   - the back office on the domain itself;
   - the platform on `admin.<domain>`;
   - each cinema's storefront on `<slug>.<domain>`.

   The server says which site an address is (`site_for_host`, public), so the rule lives in one place, ready for cinemas' own domains later. The page asks once per tab and keeps the answer in `sessionStorage`. `AppRoot` gives each site only its own routes. A storefront's pages are `/`, `/movies`, `/m/<movie>`, `/s/<showtime>`, `/tickets/<token>`, `/my-tickets`, `/sign-in`, `/sign-up`, `/account` and `/oauth/authorize`. An address under the domain that's no open cinema's is "not found".
2. **Old links go on.** On the main address, `/c/<slug>/...` goes to the same page (query and fragment kept) on the cinema's address. Claude's consent page for a cinema's connector goes to that cinema's address, where its customers are signed in. The old `/platform` paths were never anywhere but development, so they're simply gone.
3. **Every other address is every site, as before.** A tunnel, `127.0.0.1` and the desktop app serve the back office and every storefront under `/c/<slug>`. A quick tunnel serves only its own address, so phone testing over it still works, and the sign-in slots (ADR-0054) stay for these addresses.
4. **Links are written once.** Pages and the server still name storefront pages `/c/<slug>/...`. `local_path` turns them into the page's own path on the cinema's address, and `AppLink` applies it, so the same link works on every site. Links the server sends out (ticket emails, Claude's answers) use `storefront_address`: the cinema's own address when `AFRICINEMAS_PUBLIC_URL` is on the domain, and the `/c/<slug>` form on it when it's a tunnel. The back office's "View storefront" opens the cinema's address.
5. **Development uses `*.localhost`.** Browsers send every `*.localhost` address to this machine and Vite's dev server accepts them, so `admin.localhost:8000` and `anga.localhost:8000` work with `AFRICINEMAS_SITE_DOMAIN=localhost:8000` and nothing else. The browser tests' server uses `localhost:8870`.
6. **The platform's sign-in pages say as little as possible** (owner, 2026-10-23): no description of who the platform is for or how people join.
7. **The server is still the guard.** The address only decides which pages are offered. Every endpoint still checks its caller (ADR-0037, ADR-0056), whichever address the request comes from.

## Consequences
- Under the domain, each site's sign-in lives in its own address's storage, so the platform, the back office and every cinema's storefront are signed in and out apart. The slots matter only on addresses outside it.
- `AFRICINEMAS_SITE_DOMAIN` replaces 13.1b.b's `AFRICINEMAS_PLATFORM_URL`: one setting names every site's address.
- Production needs a wildcard DNS record and a wildcard certificate for `*.africinemas.co.ke`, and a proxy that passes the `Host` header through. `deploy/Caddyfile` and `docs/runbooks/three-sites.md` set this up, and `scripts/check_sites.sh` checks every address after a deploy. A new cinema needs no DNS change.
- The desktop and mobile apps, whose host names never start with `admin.`, are the main site, as before.
