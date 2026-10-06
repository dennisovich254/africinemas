# ADR-0019: A resolver job settles stuck payments and releases unpaid orders; money is an append-only ledger

- **Status:** Accepted
- **Date:** 2026-10-06
- **Sub-phase:** P5.5
- **Code:** `core/payments/resolver.jac`, `core/payments/ledger.jac`, `core/payments/settlement.jac` (ledger entries), `core/booking/order_api.jac` and `core/payments/payment_api.jac` (indexes)
- **Tests:** `tests/integration/resolver_tests.jac`

## Context
A payment whose callback never arrives, or that M-Pesa answers slowly, must not stay open forever, and an order nobody pays must not keep its seats `PAYMENT_PENDING` (§24, §124). Architecture §37: money is recorded as immutable ledger entries, not edited fields.

## Decision
1. **Indexes, not walks.** Each order is listed in `open-order` and each payment in `open-payment` (claims, claim-first: a lapsed listing still shows up) when created, so the job finds them without walking every showtime. A listing leaves once the order or payment is final.
2. **Stuck payments** (older than `AFRICINEMAS_STUCK_SECONDS`, default 60) are settled from M-Pesa's own answer (`settle`, ADR-0018), with or without a callback. One M-Pesa still calls "processing" after `AFRICINEMAS_TIMEOUT_SECONDS` (default 180) becomes `TIMEOUT` and is asked again on later runs, so a late payment still settles. A push a crashed request committed but never sent is sent if the order can still be paid.
3. **Unpaid orders.** An order past its `pay_by` first gets a last chance: its open payments are settled, so a payment that went through confirms the order. Otherwise it expires: unsettled payments fail ("the time to pay ran out"), the hold expires, the seats go back to available, and the seat claims, the hold's order claim and the order's payment claim are released.
4. **Append-only ledger.** `LedgerEntry` nodes on the order, written in the same commit as the change that moves the money, with no function that edits or deletes one: `payment` (+ amount) when a payment is confirmed; `payment` (+) and `refund_due` (-) when money was taken that bought nothing. A confirmed booking balances to its total, money that bought nothing to zero. Kinds `refund`, `reversal` and `adjustment` are reserved for refunds (§38).
5. **The job** (`resolve_payments`, every `AFRICINEMAS_RESOLVE_SECONDS`, default 30) runs on every server copy; every step is repeatable, and settling and expiring re-read state before acting.

## Consequences
- A payment confirmed without a callback has no M-Pesa receipt until reconciliation (§36); its ledger entry carries the amount but an empty receipt.
- Paying refunds out (and the `refund` entry) is a later step; refund tasks and `refund_due` entries record what is owed.
