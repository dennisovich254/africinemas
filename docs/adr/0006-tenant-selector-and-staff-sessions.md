# ADR-0006: The tenant is an explicit selector; staff also need a short server-side session

- **Status:** Accepted (spikes S3 and S6 **failed** as posed on Jac 0.37.18, so their fallbacks are adopted)
- **Date:** 2026-09-27
- **Sub-phase:** P1.4
- **Evidence:**
  - `tests/spikes/s3_s6_real_server_tests.jac` (real server)
  - `tests/spikes/s6_staff_session_tests.jac` (the session fallback)
  - `tests/unit/no_underscore_walkers_tests.jac` (guard)

## Context

Architecture §138 asked two questions.

- **S3:** can `_before_request` middleware read the tenant from the `Host` / proxy header, pass the resolved value to the endpoint, or reject the request?
  - Fallback: the client passes the tenant slug as a parameter.
- **S6:** can the staff JWT lifetime go below one day, and can the Jac client keep the token out of `localStorage`?
  - Fallback: an external identity provider, a strict CSP, and a server-side re-check of membership on every call.

## What the spikes showed

| Question | Result on 0.37.18 |
| --- | --- |
| Does `_before_request` run? | **No**, for functions and walkers, anonymous or signed in ([JI-023](../jac-issues/JI-023-before-request-hook-never-runs.md)) |
| Is an underscore walker hidden from the API? | **No.** `/walker/_before_request` is routed, and fails when called |
| Token lifetime below 1 day? | **No.** `JAC_SERVE_AUTH_TOKEN_TTL_DAYS` must be an integer: `1` gives 24 h, `0.5` stops the server from starting, and `0` issues tokens that are refused at once |
| Can a token be revoked before it expires? | **No.** This is documented as a current limitation |
| Is the web client's token kept out of `localStorage`? | **No.** The client runtime stores it in `localStorage["jac_token"]` |

## Decision

1. **Tenant = explicit selector, never authority.**
   - The client works out the tenant slug from the page's host or path (for example `nova.africinemas.co.ke` → `nova`) and sends it with each call.
   - Endpoints resolve slug → `Tenant` through one helper.
   - What a caller may do still comes only from membership and grants (ADR-0003, ADR-0004), so a forged slug gains nothing. This is the §138 fallback, which §7 already allowed ("a hint, not authority").
2. **Staff also need a live shift session on the server.**
   - Staff actions check a system-owned `StaffSession` next to membership. It expires after a shift (8 h in the spike) and ends immediately on logout, or when the staff member is removed.
   - Staff can't extend their own session, because it is system-owned (ADR-0005's pattern).
   - Customers keep plain 1-day tokens.
   - `deploy/production.env` keeps `JAC_SERVE_AUTH_TOKEN_TTL_DAYS=1`, the shortest lifetime that works.
3. **The token sits in `localStorage`, so XSS is the main threat.**
   - P10 adds a strict Content-Security-Policy, with no third-party scripts in the back-office, and no raw HTML from tenant data (themes are typed tokens, ADR in P0.8a).
   - The short staff session limits how long a stolen token is useful.
   - We don't adopt an external IdP for the hackathon; it stays an option.
4. **No underscore walkers in app code.** They wouldn't run as hooks, and they would be public routes. A unit test enforces this.

## Consequences

- Every staff endpoint runs the same `authorize()` (P2): token → root → membership → live shift session → permission. That is one extra read per call.
- The tests pin the observed behaviour. If a Jac upgrade makes the hook run, or accepts shorter lifetimes, they fail, and this ADR should be revisited.

## Implemented in P2.7a: shifts as expiring claims

- A **shift** is an atomic claim (ADR-0007) keyed by `(cinema, member)`, with a time-to-live: `AFRICINEMAS_SHIFT_TTL_S`, **8 h** by default (`core/tenancy/shifts.jac`). It lives on the server and expires on its own. Checking it is one database lookup, and nothing in the graph needs cleaning up.
- `start_shift(tenant)` opens it; calling it again restarts the 8 hours. `end_shift(tenant)` closes it at once, and the UI calls it on logout (P2.7b). Only members can open one.
- **`scoped()` requires an open shift for every staff action.** Refusals are checked in order: `not_found` (not a member, or removed or disabled), then `no_shift` ("Start your shift to continue."), then `forbidden`. So removal or disabling always wins over an open shift. `my_access` works without a shift, so the UI can show a member their cinemas and roles before they start.
- A shift covers one cinema: staff of two cinemas open a shift at each.
- The owner is staff too, and needs a shift for staff actions.
