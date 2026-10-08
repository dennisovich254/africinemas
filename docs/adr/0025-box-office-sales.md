# ADR-0025: The box office sells through the storefront's own flow; cash confirms at once, attributed to the agent

- **Status:** Accepted
- **Date:** 2026-10-08
- **Sub-phase:** P6.5
- **Code:** `core/booking/counter_api.jac`, `core/booking/confirm.jac`, `core/payments/ledger.jac` (`method`, `recorded_by`), `core/payments/payment_api.jac` (`counter_payment`), `web/backoffice/BoxOfficeSection.jac`, `web/storefront/Checkout.jac` (counter mode)
- **Tests:** `tests/integration/counter_sale_tests.jac`, `e2e/box_office_tests.jac`

## Context
Plan 6.5: counter staff sell to walk-in customers, for cash or with M-Pesa at the counter. A cash sale must create a confirmed booking and a ledger entry attributed to the agent, and an agent can't sell for another venue. Online, a visitor holds seats, places an order and pays with M-Pesa; settlement then confirms the order and issues the tickets.

## Decision
1. **The agent books through the storefront's own endpoints** (`hold_seats`, `place_order`) under a counter holder id, one per sale. Seats, prices, holds and their expiry work exactly as online. The page is the storefront's `Checkout` in counter mode: it takes the counter holder, a pay panel and a done panel.
2. **Confirming a paid order is one shared function,** `confirm.confirm_order`:
   - one commit makes the order confirmed, its seats sold, its tickets issued and the money a ledger entry;
   - then the tickets' references, the link and the email follow;
   - M-Pesa settlement and cash both use it, settlement passing its payment update to land in the same commit.
3. **`sell_for_cash`** confirms at once.
   - **The ledger entry:** the whole amount, `method` "cash", `recorded_by` the agent (`LedgerEntry` gains both fields; M-Pesa entries have `method` "mpesa").
   - **Once per order:** it takes settlement's per-order gate (`order-paid`), so an order is paid once.
   - **No overlap with M-Pesa:** it refuses while an M-Pesa prompt for the order is open. An M-Pesa success that arrives after a cash sale finds the gate taken and needs attention, with a refund task (ADR-0018).
   - **On the page,** the agent confirms the cash in two steps, so a slip doesn't sell.
4. **`sell_with_mpesa`** sends the customer the M-Pesa prompt through `counter_payment`. The email address is optional at the counter; online it's still required.
5. **Who may sell:** all counter endpoints need `bookings.create` at the showtime's venue. That's box office agents and managers, general managers, admins and owners; venue-limited staff only at their venues. `counter_showtimes` lists only showtimes on sale at those venues.
6. **The done panel** shows the tickets with QR codes, to print or photograph, and **New sale**. It replaces the customer's ticket panel, which would save the tickets to the signed-in agent's own account (ADR-0023).

## Consequences
- **Cash isn't reconciled yet:** there are no till sessions or end-of-day totals. Reports (7.1) can sum ledger entries by `method` and `recorded_by`.
- **No paper receipt or cash change calculation.** The agent confirms the amount shown.
