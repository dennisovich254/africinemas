# ADR-0041: Snack stock: atomic counts per variant per venue, and movements with reasons

- **Status:** Accepted
- **Date:** 2026-10-11
- **Sub-phase:** P12.4
- **Code:**
  - `core/claims.jac` (`stock_counts`, `stock_change`, `stock_reserve`, `stock_release`, `stock_commit`)
  - `core/snacks/stock.jac` (pure rules)
  - `core/snacks/inventory_api.jac`
  - `core/snacks/models.jac` (`StockMovement`; variant `stock_rules`)
  - `web/backoffice/SnackStockPage.jac`
- **Tests:** `tests/unit/snack_stock_tests.jac`, `tests/integration/claims_tests.jac` (counters), `tests/integration/snack_stock_tests.jac`, `e2e/snack_stock_tests.jac`

## Context
The design guide (§8) asks for:
- stock per sellable variant per location;
- `on_hand`, `reserved` and `available = on_hand − reserved`;
- a low-stock alert and an at-zero rule;
- every change recorded as a movement with a reason;
- no overselling, enforced on the server, so two customers can't buy the last bottle.

It advises finished-item stock first, with recipes later.

## Decision
1. **Only variants with "Track stock" have stock**, kept per venue. A variant without it always sells.
2. **The counts are atomic counters on the shared store**, in `core/claims.jac`, the one module allowed to touch it (ADR-0007):
   - a key per cinema, variant and venue, holding `{"on_hand", "reserved"}`;
   - every change is a single SQL statement with its guard in the `WHERE` clause;
   - on hand never goes below zero, and a reservation takes only what's available;
   - a guard that fails changes nothing and returns `None`.

   They live outside the graph for the same reason claims do: a graph read-then-write would let concurrent requests both pass (JI-024).
3. **Every change is a `StockMovement`** (a tenant node, only ever added). It records the variant, venue, reason, change, on hand after, note, who made it and when. Reasons:
   - staff: `received`, `damaged`, `count` (a count correction sets the counted total), `other`;
   - orders: `sale`.

   `check_adjustment` refuses what makes no sense, such as damaging more than on hand or receiving zero. A count computed against a stale on hand still records the true change made.
4. **Stock rules per venue:** a low-stock alert (0–100,000) and what happens at zero. `unavailable` stops selling, for bottles and packets; `allow` keeps selling, for snacks made to order. The status is Out, Low or In stock.
5. **Orders will use** `reserve_stock` (only what's available, otherwise out of stock), `commit_stock` (the units leave on hand and reserved together, recorded as a sale of the order) and `release_stock` (give back an unpaid order's units). P12.7 wires them into ordering and payment.
6. **Who changes what:**
   - Reading levels and history needs `concessions.read` at that venue.
   - Adjustments and rules need `concessions.inventory` at that venue, so venue-scoped box office staff keep stock only where they work.

   Every id is checked against the cinema, and every change is audited.
7. **The back office has a Stock page.** For each venue it lists the tracked variants with on hand, reserved, available and status, plus a "Low or out only" filter. Each row has:
   - an **Adjust** form with a reason, a quantity, a note, and a preview of the stock after the change;
   - **Alerts**, for the threshold and the at-zero rule.

   Below the list, **Stock history** shows each change with its reason, who made it and when.

## Consequences
- Stock counts aren't in the graph, so they aren't in graph exports. The movements are, and they explain every count.
- Transfers between venues, receipts against purchase orders, recipes (component stock for prepared snacks) and stock for add-ons are later. Each adds movements without changing the counters.
