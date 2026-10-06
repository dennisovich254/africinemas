# ADR-0018: Callbacks only file receipts; payments settle from M-Pesa's own answer

- **Status:** Accepted
- **Date:** 2026-10-06
- **Sub-phase:** P5.4
- **Code:** `core/payments/settlement.jac`, `core/payments/models.jac` (`RefundTask`), `core/booking/models.jac` (`Ticket`), `core/payments/payment_api.jac` (callback tokens)
- **Tests:** `tests/integration/settlement_tests.jac`, `tests/isolation/` (webhook routes)

## Context
Safaricom reports an STK push's outcome by POSTing to the callback URL we gave it. Architecture §33-§35: never trust the callback (or the browser) as proof of payment; acknowledge quickly and process asynchronously; three duplicate callbacks must make one payment, one booking and one ticket set. Daraja doesn't sign callbacks, so Jac's HMAC webhook protocol can't be used (§34). The graph has no unique constraints, and find-or-create doesn't converge under concurrency (JI-024).

## Decision
1. **The callback only files a receipt.** `POST /hooks/mpesa/{token}` (`@restspec`, public) checks the per-payment token (made and indexed when the payment starts, P5.3), parses the body (`parse_callback`, ADR-0016) and keeps only what settling needs (checkout id, result code, receipt, amount) in an inbox in the claims table. The first callback per payment is kept; duplicates change nothing. It always answers `{"ResultCode": 0}` and writes nothing to the graph, so it is quick and not exposed to JI-038. Unknown tokens and bodies that aren't STK callbacks are acknowledged and ignored.
2. **Settling asks M-Pesa.** `settle()` runs the status query. Still waiting: nothing changes. Unknown: the payment is `UNKNOWN` (plan 5.5 resolves it). Failed or cancelled: the payment says so and the order is free for another attempt, whatever the callback claimed. Confirmed paid: the payment is `SUCCESS` with its receipt, the order `confirmed`, the hold `paid`, the seats `SOLD`, and one `Ticket` per seat issued, in one explicit commit.
3. **One ticket set** (§35), by atomic claims (ADR-0007) rather than find-or-create: a per-order finalize gate (`order-paid`) lets one settle finalize, its owner naming the payment and the attempt, so the job and a status check racing can't both issue tickets; an M-Pesa receipt is claimed once (`mpesa-receipt`); settling a final payment changes nothing.
4. **What can't settle cleanly needs attention**, with a `RefundTask` (money was taken but bought nothing): the paid amount differs (`amount_mismatch`), M-Pesa confirms after the payment failed or was cancelled or the order stopped waiting (`late_success`), the receipt was already used (`receipt_reused`), or another payment already paid the order (`order_already_paid`). No tickets are issued.
5. **Who settles.** A scheduled job (`settle_callbacks`, every `AFRICINEMAS_SETTLE_SECONDS`, default 5) settles every filed receipt; a final payment's receipt leaves the inbox. `my_payment` settles the visitor's own payment when a receipt for it is waiting, so the page updates at once, and returns the tickets of a paid order.
6. **The isolation guard covers custom paths.** Routes under `/hooks/` must be in the registry (scope `webhook`) and are probed anonymously.

## Consequences
- Tickets are minimal (seat, type, reference); signed QR payloads come with plan 6.1.
- Refund tasks are recorded but not yet acted on; refunds become ledger entries with plan 5.5 (§37, §38).
- The query doesn't return the receipt or amount, so a payment confirmed without a callback (the resolver, 5.5) has no receipt until reconciliation.
