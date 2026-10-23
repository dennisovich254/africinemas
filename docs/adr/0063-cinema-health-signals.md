# ADR-0063: A cinema's technical health, for our support team

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P13.5c
- **Code:** `core/support/health.jac` (`health_of`), `core/support/names.jac`, `web/support/HealthPanel.jac`; shown by `core/platform/cinemas_api.jac`, `core/support/requests.jac` (`platform_support_request`) and `core/platform/overview_api.jac`
- **Tests:** `tests/integration/health_tests.jac`, `e2e/platform_cinemas_tests.jac`, `e2e/platform_overview_tests.jac`, `e2e/support_tests.jac`

## Context
When a cinema asks for help, or before it does, our support team needs to see what's going wrong technically. It should see that without opening the cinema's bookings or its customers (Phase 13's rule).

## Decision
1. **Five signals per cinema, counted from its own records**, by the same graph walk as its reports:
   - **payments needing attention:** M-Pesa took money that couldn't be settled on its own, in the last 30 days;
   - **refunds due:** open refund tasks, and their total;
   - **M-Pesa attempts that failed:** failed, timed-out or with a prompt that may not have arrived, out of all attempts in the last 7 days;
   - **stuck payments and orders:** still waiting on M-Pesa, or unpaid past their time, 30 minutes after the resolver or the sweeper should have settled or released them;
   - **emails not sent:** ticket and support emails still queued 10 minutes on.
2. **Failures are a problem only when they're most attempts** (at least 5, and half or more). Customers cancel prompts and mistype PINs every day, so one failure is normal.
3. **Counts and sums only.** There's no phone, email, holder or reference, and the tests check that.
4. **Shown where the team needs them:**
   - on the cinema's directory page;
   - folded above the chat on each help request, opened when something's up;
   - on the overview, as the number of cinemas with problems, naming up to five, most problems first, linked to their pages.

   A signal that's up says "Needs a look" with an icon, never by colour alone.
5. **Not yet: storefront errors.** Pages don't report their errors anywhere today. That needs a client error report first (logging what fails in visitors' browsers), which is its own piece of work.

## Consequences
- Each overview and cinema page walks the cinema's records, like the directory (ADR-0058). That's fine for hundreds of cinemas. Thousands would need the signals kept as events happen.
- Phase 15's fee and monthly invoices can add their own signals, such as an invoice overdue, the same way.
