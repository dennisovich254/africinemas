# ADR-0029: The Overview is a role-shaped staff home page, from one request

- **Status:** Accepted
- **Date:** 2026-10-09
- **Sub-phase:** P7.4
- **Code:** `core/reporting/staff_home.jac` (`staff_home`), `core/reporting/report_api.jac` (`cinema_records`), `web/backoffice/StaffHome.jac`, `web/backoffice/BackOffice.jac` (`ShiftBanner`)
- **Tests:** `tests/integration/staff_home_tests.jac`, `e2e/home_tests.jac`

## Context
The Overview is the first page every member of staff sees. It showed a page-wide shift alert, one role badge and empty space: nothing about today, nothing to do next, and no guidance for a cinema that has just signed up.

## Decision
1. **One endpoint, shaped by role:** `staff_home(tenant)` answers, for the cinema's today:
   - **setup** (`venues.configure`): seven steps in the order a new cinema does them (venue, a screen's published seat layout, prices, movie, a published showtime, published branding, a second member of staff), each done or not, with the section that does it;
   - **showtimes:** today's showtimes put on sale and not cancelled, at venues where the caller may read showtimes, with seats sold and on sale, and whether the caller may sell (`bookings.create`) or scan (`tickets.scan`) there;
   - **figures** (`financial_reports.read`): today's net takings, tickets, occupancy and showtimes, the sales report's numbers (ADR-0026);
   - **activity** (`audit.read`): the last five audit events.

   A part the caller may not see is `None`. It needs an open shift, as every staff endpoint does (ADR-0006).
2. **The page:** a header (greeting and the cinema's day, the roles, "On shift", a link to the storefront), then on desktop two columns: today's figures and showtimes (each with Sell or Scan) on the left; quick actions (at most four, from the member's permissions), the setup checklist (until every step is done) and recent activity on the right. A phone stacks them in that order. Off shift, the page says what starting one shows.
3. **The shift banner** is one compact row above every section (it was a page-wide alert), wrapping on a phone with the button last.
4. **"Your roles"** is no longer a section; the header names them ("Signed in as Owner").

## Consequences
- The 7.3 Overview summary (`TodayAtAGlance`) is replaced by the home page's figures.
- The page reads the whole cinema (as the sales report does) on each load: fine at this size.
- Off shift, nothing about today shows until the shift starts (consistent with ADR-0006); the checklist appears once it does.
