# ADR-0073: Snacks only, at the box office

- **Status:** Accepted
- **Date:** 2026-10-24
- **Sub-phase:** P12.10 (improvements #21, #26)
- **Code:** `core/booking/snack_sale.jac`, `core/payments/payment_api.jac` (`pay_order`), `core/booking/confirm.jac` and `core/payments/resolver.jac` (an order without a seat hold), `core/snacks/pickup_api.jac` (a day to hand over), `web/backoffice/SnackOnlySale.jac`, `web/backoffice/BoxOfficeSection.jac`
- **Tests:** `tests/integration/snack_sale_tests.jac`, `tests/isolation/registry.jac`, `e2e/box_office_tests.jac`, `e2e/support/snacks.jac`

## Context
A walk-in may want popcorn without a ticket. Every order was a showtime's: placed, paid, followed and expired through it (place_order, start_payment, my_payment, the resolver).

## Decision
1. **A snacks-only order hangs off the venue.** It's an ordinary `Order` with no showtime (`screening_id` ""), no seats and no seat hold, linked from the `Venue`. Everything after placing it is shared with ticket orders:
   - confirming it (`confirm_order`: the stock sold, the ledger entry, a pickup code);
   - settling M-Pesa (`order_of` finds it from the payment);
   - expiring it unpaid (`expire_order`: its stock back), listed in `OPEN_ORDERS` like any order.

   Only the two lookups by a seat hold now skip an order without one.
2. **The same two steps as a ticket sale, one request each:**
   - **placing:** `place_snack_order`, the stock set aside until `pay_by`;
   - **paying:** `sell_snacks_for_cash`, or `sell_snacks_with_mpesa` followed by `counter_snack_payment`.

   Two requests also keep a write from ever following a mid-request commit (JI-042).
3. **Starting a payment takes the order's lookup.** `pay_order(cinema, find_order, …)` is `_start_payment`'s body, unchanged. The showtime path passes `pending_order` for its showtime, and the venue path passes the venue's pending order for the sale.
4. **Handing over:** the pickup code, and the Snack counter's `hand_over_snacks`, on the same page. Without a showtime, the snacks can be handed over for 24 hours after the sale.
5. **Who:** staff who sell at the venue (`bookings.create` there), on shift, at a live cinema, as for tickets. The box office page has **Tickets** and **Snacks only** tabs. Snacks only works even when no showtime is on sale.
6. **Mixed ticket and snack sales:** the paid screen shows both ticket codes and the
   one snack pickup code. Staff can record the handover there immediately; the public
   two-hour pickup window still applies to orders bought outside the counter. Printing
   includes the pickup code when the customer will collect the snacks later.

## Consequences
- Snacks-only takings are in the ledger and the sales report. 12.11 shows them apart from ticket money.
- Adding more snacks to an existing booking later (12.14) can reuse `pay_order` with that booking.
