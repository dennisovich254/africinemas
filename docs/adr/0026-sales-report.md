# ADR-0026: The sales report counts money on the day it was taken and tickets on the day of the showtime

- **Status:** Accepted
- **Date:** 2026-10-08
- **Sub-phase:** P7.1
- **Code:** `core/reporting/aggregates.jac`, `core/reporting/report_api.jac` (`sales_report`), `core/payments/models.jac` (`PaymentIntent.sold_by`), `core/payments/payment_api.jac` (`counter_payment`), `core/payments/settlement.jac`
- **Tests:** `tests/unit/reporting_tests.jac`, `tests/integration/reporting_tests.jac`, `tests/integration/counter_sale_tests.jac`

## Context
Plan 7.1: the owner's dashboard (architecture §76) and revenue reporting (§77) need revenue, tickets sold, occupancy, top movies and a per-venue drill-down, with refunds subtracted. A ticket is often bought days before its showtime, so "the 5th's revenue" can mean the money taken on the 5th or the money from the 5th's showtimes. An M-Pesa sale at the box office (ADR-0025) left no mark of the counter: its ledger entry had no `recorded_by`.

## Decision
1. **One endpoint,** `sales_report(tenant, date_from, date_to, venue_id)`:
   - a period is the cinema's local days, `date_from` to `date_to` (YYYY-MM-DD, both included, at most 366 days), in the price list's time zone;
   - `venue_id` limits everything to one venue;
   - it needs a login, an open shift (ADR-0006) and `financial_reports.read`: owners, general managers, finance managers and auditors.
2. **Takings count on the day the money was taken:** the ledger's entries (ADR-0019) by `created_at`.
   - **gross** is the payments;
   - **refunds** are `refund_due`, `refund` and `reversal`, shown as a positive amount;
   - **adjustments** are added as they are;
   - **net** is the sum of every entry, so refunds and adjustments are subtracted;
   - payments split by method (M-Pesa, cash) and by channel: a payment with `recorded_by` set was taken at the box office, otherwise online.
3. **Attendance counts on the day the showtime starts,** for every showtime that was put on sale and not cancelled:
   - tickets sold are issued or used ones (refunded and voided ones don't count); scanned are used ones;
   - seats on sale are the showtime's seat slots that aren't blocked or house seats;
   - ticket revenue is the sold tickets' prices from their order's lines, service fee included;
   - from these: occupancy, tickets per show, average ticket price, revenue per available seat.
4. **The drill-down** goes venue, screen, movie, showtime, each with the attendance numbers; a venue also has its net takings. Top movies and top showtimes are the five with the most ticket revenue.
5. **Counting is separate from collecting:** `aggregates.jac` takes plain records and only counts, so its numbers are tested against a fixture with known answers; `report_api.jac` collects the records from the cinema's graph.
6. **An M-Pesa sale at the counter is recorded as the agent's:** the payment intent keeps the member of staff who started it (`sold_by`), and settlement puts them on the ledger entry's `recorded_by`, as a cash sale does.

## Consequences
- **Two time bases on one page:** a ticket bought on Monday for Friday counts in Monday's takings and in Friday's occupancy. The dashboard (7.3) must label them ("Money taken", "Showtimes").
- **Not reported, because nothing records them:** discounts, tax and concession sales. Concessions (Phase 12) will split ticket money from snack money by the order's lines.
- **Paying refunds out (§38) must not subtract twice:** today a refund owed is one `refund_due` entry. When refunds are paid out, the payout must not add a second negative entry for the same money, or refunds and net would count it twice.
- **The report walks the whole cinema** on every request: its venues, screens, showtimes, orders, tickets and ledger entries. That's fine at a few cinemas' size; a large one would need totals kept as sales happen.
- **M-Pesa sales at the counter before this change** have no `recorded_by` and count as online.
