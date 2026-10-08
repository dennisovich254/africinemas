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
2. **The page leads with the movies, as a cinema should** (inspired by streaming-app home pages). The shell's title stays the page's `h1` but is visually hidden on the home page (`AppShell(title_hidden)`), whose greeting is its visible heading; the web address line gives way to the "View storefront" chip. The side column is three separate tiles:
   - a header: a greeting in the display face, the cinema's day and the member's roles, an "On shift" chip and a "View storefront" chip;
   - a **hero** for the next showtime (or the one showing now): the movie's backdrop (or its poster, blurred) behind a dark scrim, the title in the display face, time, screen, venue, seats sold, and Sell or Scan as pill buttons; "No showtimes today" with "Add a showtime" when there are none;
   - today's figures as four compact tiles;
   - today's showtimes as **poster cards** (time, title and screen on the artwork, seats sold, Sell or Scan), a row that scrolls within itself on a phone and a grid on desktop;
   - a **side panel**: quick actions, the setup checklist (until every step is done) and recent activity.

   Artwork is decorative (titles are always written). It comes from **`showtime_art(tenant, screening_id, kind)`**, a staff endpoint (shift, `showtimes.read` at the showtime's venue), not the storefront's public images: those serve only an open cinema's movies on sale, so a cinema still being set up showed no artwork. The hero shows the poster itself on the right on wider screens, over the backdrop (or the poster blurred). Text on artwork is white on a black scrim of at least 60 % opacity, for contrast. A phone stacks everything, the hero first. Off shift, the page says what starting one shows.
3. **The shift banner** is one compact row above every section (it was a page-wide alert), wrapping on a phone with the button last.
4. **"Your roles"** is no longer a section; the header names them ("Signed in as Owner").

## Consequences
- The 7.3 Overview summary (`TodayAtAGlance`) is replaced by the home page's figures.
- The page reads the whole cinema (as the sales report does) on each load: fine at this size.
- Off shift, nothing about today shows until the shift starts (consistent with ADR-0006); the checklist appears once it does.
