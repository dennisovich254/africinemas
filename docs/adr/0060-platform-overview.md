# ADR-0060: The platform overview

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P13.4
- **Code:** `core/platform/overview_api.jac` (`platform_overview`), `web/platform/OverviewFigures.jac`, `web/backoffice/report_parts.jac` (`TakingsChart`'s count, now a parameter)
- **Tests:** `tests/integration/platform_overview_tests.jac`, `e2e/platform_overview_tests.jac`

## Context
The console's home showed only who you are. The team needs to see the platform at a glance: how many cinemas there are and in which states, who joined this week, and how bookings and takings are going across every cinema.

## Decision
1. **For every platform role** (`platform.read`), on the Overview, under the welcome.
2. **Figures:**
   - cinemas, and how many are in each state;
   - sign-ups in the last 7 days;
   - bookings and net takings over the last 14 days, in all and day by day.
3. **A booking is a payment.** That's an online order paid, or a box office sale. Bookings and takings are counted by **the day the money was taken**, from the same ledger entries as each cinema's own sales report. So the platform's figures add up to the cinemas' own, and an upcoming showtime's bookings count on the day they were made.

   The cinema report's "tickets for that day's showtimes" answers a different question: how full a day's screenings are.
4. **The platform's days are Nairobi's** (`Africa/Nairobi`) for every cinema, so the same date means the same day across cinemas.
5. **The chart is the cinema dashboard's** `TakingsChart`. It has one series, a readout on hover, tap or focus, and a table view, and it follows the dataviz rules already checked there. Its count is now a parameter: tickets on a cinema's dashboard, bookings here. Fourteen days with no sales show one line saying so, not an axis of zeros.
6. **Not yet:** cinemas with technical problems (13.5) and reviews waiting (Phase 14). They're added to the overview when those exist.

## Consequences
- Like the directory (ADR-0058), the overview reads every cinema's records on each request. That's fine for hundreds of cinemas. With thousands, it needs daily totals kept as money is taken.
- Phase 15's fee (10% of every booking) can be shown from the same ledger entries, per day.
