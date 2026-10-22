# ADR-0054: A sign-in for the back office, and one per cinema's storefront, in the same browser

- **Status:** Accepted
- **Date:** 2026-10-22
- **Improvement:** #25
- **Code:** `web/auth/token_slots.jac` (`token_slot`, `install_token_slots`, `cinema_of_resource`), installed by `web/AppRoot.jac`
- **Tests:** `e2e/my_tickets_tests.jac` ("an owner stays signed in to the back office while a customer at their own cinema")

## Context
Customer accounts belong to one cinema and are apart from staff accounts (P8.6c, ADR-0037), and an owner may be a customer at their own cinema. Jac's client, however, keeps one sign-in token per site, under the localStorage key `jac_token`, and reads it on every request. The back office (`/app`) and the storefronts (`/c/<slug>`) are on the same site. So when an owner signed in as a customer on their storefront, that replaced their back-office sign-in. The back office then asked the server about a customer account, which has no cinemas and may not create one ("No cinemas found", then "this is a cinema's customer account").

## Decision
1. **Each part of the site keeps its own token:** `africinemas_token:staff` for the back office, staff sign-in and invitations, and `africinemas_token:customer:<slug>` for a cinema's storefront and for the consent page of its connector (`/oauth/authorize`, cinema from `resource`).
2. **`jac_token` means the current page's slot.** `install_token_slots` wraps `Storage.prototype.getItem`, `setItem` and `removeItem`, for `localStorage` and that one key only. Jac's own sign-in, sign-out, `jacIsLoggedIn`, requests and 401 handling all keep using `jac_token`, unchanged, and land in the right slot.
3. **Per tab.** Each tab maps the key from its own address, so a back-office tab and a storefront tab can be open together, each signed in as itself.
4. **Installed before anything asks the server:** as a module-level value of `AppRoot`, and once per tab.
5. **Migration:** a token stored under the old shared key moves, once, to the slot of the first page that loads.

## Consequences
- Signing in or out on a storefront never touches the back office, and the reverse.
- This relies on Jac's client reading `jac_token` through `localStorage.getItem`. If a Jac upgrade changes how the token is stored (for example to an HttpOnly cookie, which the threat model wants), this goes and is replaced by separate cookies per path.
- A storefront on its own domain later would need none of this.
