# ADR-0064: Only an active cinema is public

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P14.1
- **Code:** `core/tenancy/open_cinema.jac` (`open_cinema`, `preview_pass`, `require_live`), `core/tenancy/tenant_api.jac` (`storefront_preview`), `core/platform/cinemas_api.jac` (`platform_approve_cinema`), `web/preview.jac`, `web/backoffice/StorefrontLink.jac`, `core/testing/go_live.jac` (test-only), `scripts/activate_existing_cinemas.jac`
- **Tests:** `tests/integration/go_live_tests.jac`, `tests/unit/no_test_code_in_main_tests.jac`, `e2e/go_live_tests.jac`

## Context
Anyone could sign up, name a cinema anything, and sell tickets from the first minute (threat model 1.1). Phase 14 puts verification before going public, and 14.1 builds the gate: nothing a fake does is seen by the public until AfriCinemas has approved it.

## Decision
1. **One gate.** `open_cinema`, which every public, customer, booking, payment, Claude and listing endpoint already used to find a cinema, finds only an `active` one. Anything else answers as unknown, so a cinema being set up or waiting for review has no public trace: no storefront, no showtimes, no holds, not in the directory or Claude's search, and its address is no cinema's (`site_for_host` says "none").
2. **The team's preview.**
   - **The pass:** the back office's "View storefront" asks `storefront_preview` (any member of the cinema) for a pass: an 8-hour token for that one cinema, held in the app's token store.
   - **Carrying it:** the link carries it as `#preview=<pass>`. The storefront page keeps it for its tab, takes it out of the address bar, and sends it on every request to its own server in the `x-africinemas-preview` header (`web/preview.jac`, which wraps `fetch`).
   - **Checking it:** with a valid pass for that cinema, `open_cinema` finds it before it goes live.
   - **The banner:** the page shows "Only your team can see this…". Anyone holding the link sees the preview until the pass expires, which is how an owner shows a colleague. The pass opens no other cinema.
3. **No money before going live.** `require_live` refuses placing an order, starting a payment and every box office sale (`not_live`: "This cinema isn't taking bookings yet…") while the cinema isn't active, in a preview too.
4. **Approval, for now.** Reviewers and super admins (`platform.review`) have **Approve** on a cinema's page in the console (`platform_approve_cinema`). It moves the cinema through `ready_for_go_live` to `active`, and it's recorded in the platform's log, about the cinema, so it shows in its history. 14.5 replaces this with the review of the owner's and the business's verification.
5. **Existing cinemas stay public** (owner, 2026-10-22). `scripts/activate_existing_cinemas.jac` made every cinema from before 14.1 active, once.
6. **Tests make cinemas live without the review.**
   - **Server tests:** the test-only `t_go_live` lives in `core/testing/` (the real-server tests copy only `core/`), for the test apps. `tests/unit/no_test_code_in_main_tests.jac` fails if the production app or anything it serves imports it. The storefront tests that ran against `main.jac` now run against `payment_app.jac`, which serves the same endpoints.
   - **Browser tests:** these approve through `platform_approve_cinema` as the test super admin.
7. **"No cinema here" isn't remembered.** The page keeps its site's answer for the tab, but not "none", since a cinema can go live after a visit.

## Consequences
- 14.4's "Submit for review" moves a cinema to `ready_for_go_live`, and 14.5's review approves it, through this same gate.
- 14.6's suspension is the same gate: a `suspended` cinema isn't `active`, so it's gone from the public at once.
