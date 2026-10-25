# ADR-0074: Snack sales and current stock in Reports

- **Status:** Accepted
- **Date:** 2026-10-25
- **Sub-phase:** P12.11
- **Code:** `core/reporting/aggregates.jac`, `core/reporting/report_api.jac`, `web/backoffice/ReportsSection.jac`, `web/backoffice/SnackReport.jac`
- **Tests:** `tests/unit/reporting_tests.jac`, `tests/integration/reporting_tests.jac`, `tests/integration/snack_reporting_tests.jac`, `e2e/dashboard_tests.jac`

## Context

The report collected orders under showtimes only, omitting P12.10's venue-owned
snacks-only orders. It also had no split between ticket and snack money, product
rankings, or current stock alerts. The venue selector was populated only from
showtimes in the selected period, so a venue selling only snacks could be missing.

## Decision

1. Collect both showtime-owned and venue-owned orders under the cinema's principal.
   Keep the existing `financial_reports.read` check, open-shift requirement and
   tenant-isolation registry entry; no new endpoint is added. The response includes
   every cinema venue for filtering, including venues without showtimes or sales.
2. Split each ledger amount in proportion to the order's saved `snacks_cents` and
   `total_cents`. Round to the nearest cent using integer arithmetic, half away
   from zero; the ticket portion is the remainder. Ticket net plus snack net always
   equals net takings. Full payments allocate exactly, and a payment/refund pair
   cancels exactly. Booking fees stay with tickets. The UI explains that refunds
   and adjustments use this proportional allocation; the ledger currently has no
   line-level allocation for partial refunds.
3. Rank the top ten products and variants by saved snack-line sales, including
   add-ons. A combo counts as one sold item; its components are not counted again.
   Count confirmed orders once, on the first successful payment's local day, and
   exclude payment attempts paired with a refund due. Unpaid orders do not count.
   Rankings are gross sales, explicitly labelled before refunds, while the net
   tiles reflect ledger adjustments. Product groups use stable IDs and the catalog
   name (saved line name if the product is missing); variant names and all prices
   come from the order snapshots. Archived products retain their historical sales.
4. Venue takings include venues with money but no showtimes in the period. These
   have zero attendance and no screen rows. The Overview also benefits from the
   corrected order collection.
5. Low-stock alerts are a **current snapshot**, independent of the date range,
   filtered by venue. Reuse the inventory counters and thresholds: available is
   on hand minus reserved, clamped at zero. Include low and out-of-stock tracked
   variants, excluding archived products and items switched off at that venue.
   The response records `stock_as_of`; the page labels this section "Low stock now".
6. Extend the existing responsive dashboard with two net tiles, semantic product
   and variant tables, and wrapping stock cards. Status is written in words, not
   conveyed by color alone. No new design system or dependencies are introduced.

## Validation

Pure aggregation fixtures cover exact splits, refund symmetry, local-day bounds,
variant grouping, empty periods, venue filtering and snacks-only venue totals.
Integration fixtures cover mixed M-Pesa and standalone cash sales, unpaid stock
reservations, price changes, archived products, finance access, tenant isolation
and money owed back after a short payment. Browser coverage checks both themes on
phone and desktop, totals, filtering, empty periods, stock alerts, overflow and
screenshots. Integration and browser execution are delegated to GitHub CI.
