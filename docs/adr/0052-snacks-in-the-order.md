# ADR-0052: Snacks in the order and the payment

- **Status:** Accepted
- **Date:** 2026-10-22
- **Sub-phase:** P12.7
- **Code:** `core/booking/order_api.jac` (`place_order` takes `snacks`), `core/booking/models.jac` (`Order.snack_*`), `core/snacks/order_stock.jac`, `core/booking/confirm.jac`, `core/payments/resolver.jac` (`expire_order`)
- **Tests:** `tests/integration/snack_order_tests.jac`

## Context
P12.6 (ADR-0051) prices a snack cart at a venue. Customers on the storefront (P12.8) and staff at the box office (P12.10) buy snacks with their tickets, so the order must carry the snacks, the payment must cover them, and stock must follow the order: the last bottle can't be sold twice, and an unpaid order mustn't keep it.

## Decision
1. **`place_order` takes the snack cart** (optional, the same lines as `price_snacks`). The server prices it with `price_cart` at the showtime's venue. A refused cart refuses the order (`snacks_unavailable`, every problem listed).
2. **The order keeps a snapshot**: `snack_lines` (each line's name, quantity, unit and line price, add-ons and combo choices), `snacks_cents`, and the venue. `total_cents` is tickets plus snacks, so the M-Pesa amount and the ledger entry are the whole order with nothing else changed. Ticket `lines` stay tickets only, because confirming issues one ticket per line. A later price change changes nothing.
3. **Idempotency covers the snacks.** The cart, in a canonical form, is kept as `snack_request`. The same key with different snacks is `key_reused`, as it is for seats.
4. **Stock follows the order** (`core/snacks/order_stock.jac`), counting only variants that track stock and stop selling at zero, with combo components included:
   - *placed*: the units are reserved, and the order keeps what it reserved (`snack_stock`). If a unit sold out since the cart was priced, the order is refused and what was taken is given back. If making the order fails afterwards, the reservation is released with the other claims.
   - *paid*: `confirm_order`, used by both M-Pesa and cash, commits the reservation as a sale movement naming the order, in the order's own commit. It runs once per order (the FINALIZE gate), so repeated callbacks sell once.
   - *ended unpaid*: `expire_order` releases it.
5. Variants that keep selling at zero (food made to order) aren't counted. Selling them doesn't touch stock yet; recipes come later.

## Consequences
- The sale movements are saved in `confirm_order`'s one commit, with the order, its tickets and the ledger entry. (Recording them after that commit lost them: a node linked to the cinema after the commit wasn't saved in the payment job's request.) The counters live outside the graph (ADR-0041), so they move just before that commit. If the commit then fails, the units have left "reserved" without a sale movement, and a count correction on the Stock page fixes it. A counter that can't be committed is logged, and the order is paid either way.
- The storefront and the box office only need to send the cart; prices and stock are the server's.
