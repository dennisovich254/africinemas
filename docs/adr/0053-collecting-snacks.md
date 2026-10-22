# ADR-0053: Collecting snacks at the snack counter, by a pickup code

- **Status:** Accepted
- **Date:** 2026-10-22
- **Sub-phase:** P12.9
- **Code:** `core/booking/ticket_codes.jac` (`PICKUPS`, `PICKUP_VERSION`, `pickup_payload`), `core/booking/confirm.jac`, `core/snacks/pickup_api.jac` (`snack_pickup`, `hand_over_snacks`), `core/booking/redeem_api.jac` (refuses pickup codes), `web/backoffice/SnackCounterSection.jac`, `web/storefront/PayPanel.jac` (`PickupCard`)
- **Tests:** `tests/unit/ticket_code_tests.jac`, `tests/integration/snack_pickup_tests.jac`, `e2e/snack_checkout_tests.jac`

## Context
Customers buy snacks with their tickets (P12.7, P12.8) and collect them at the counter, as the owner decided on 2026-10-10. Staff need to know what was paid for, and the same order must not be collected twice. The door scanner (P6.2, ADR-0021) solved the same problem for tickets.

## Decision
1. **One pickup code per paid order with snacks**, made in `confirm_order`'s commit with the tickets. It's a reference like a ticket's: 16 characters in four groups, claimed for good in its own namespace (`PICKUPS`, owner `<tenant id>|<order id>`). Its QR is signed as `SNK1` instead of `TKT1`, with the same key.
2. **The two scanners keep apart.** The door refuses a pickup code, scanned or typed (`snack_code`, "It's collected at the snack counter"), and the snack counter refuses a ticket (`ticket_code`). Typed references are told apart by which namespace claims them.
3. **Look up, then hand over.** `snack_pickup` shows the order: its showtime, each snack with its extras and a combo's contents, paid or not, and whether pickup is open. It changes nothing. `hand_over_snacks` marks the order collected, once. Refusals: `invalid_code`, `ticket_code`, `unknown_pickup` (another cinema's code gets the same answer), `not_paid`, `too_early`, `showtime_over` and `already_collected` (when, and by whom). It is audited as "snacks.handed_over".
4. **When:** from 2 hours before the showtime (`PICKUP_OPENS_MINUTES`) until it ends, so snacks can be collected before or during the film.
5. **Who:** staff on shift with `concessions.collect` at the order's snack venue: box office agents and managers, general managers, admins and owners. A venue-limited role works only at its venues. Ushers can't.
6. **Once, however many counters race:** an atomic claim on the order (`snacks-collected`, ADR-0007) is taken before it's marked collected, and released if saving fails, as at the door.
7. **Screens:** a **Snack counter** section in the back office scans with the scanner's camera or takes the typed code. "You're booked" shows the pickup QR and reference under "Your snacks".

## Consequences
- The tickets page, the ticket email and My tickets list the snacks with the pickup code next (12.9, part two).
- Orders paid before this change have no pickup code. "You're booked" then says to collect the snacks with the ticket.
