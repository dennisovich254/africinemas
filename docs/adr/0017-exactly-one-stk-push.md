# ADR-0017: Starting a payment sends exactly one STK push, whatever reruns

- **Status:** Accepted
- **Date:** 2026-10-06
- **Sub-phase:** P5.3
- **Code:** `core/payments/payment_api.jac`, `core/payments/models.jac`, `core/faults.jac` (`replay_point`)
- **Tests:** `tests/integration/payment_tests.jac` (app: `tests/apps/payment_app.jac`)

## Context
Paying an order sends an STK push: a PIN prompt on the customer's phone. Daraja has no idempotency key (ADR-0016), so a second push is a second prompt and possibly a second charge. A Jac request can run more than once: it is replayed after a write conflict (§25, JI-031), a visitor can tap Pay twice, and several servers may serve the same visitor. Architecture §29 says to send the push only after the payment record commits.

## Decision
1. **Record first, push after the commit.** `start_payment` creates a `PaymentIntent` (state `created`) under the order and commits it explicitly (`commit_now`, JI-038). Nothing is sent from a unit of work that may be replayed.
2. **A one-shot gate.** The push is sent only by whoever wins an atomic claim on the intent (`stk-gate`, ADR-0007). Every other caller, on any server, never sends it.
3. **The result is kept outside the transaction.** The push's outcome is claimed at once (`stk-result`, a JSON record). A caller that finds the gate taken but the intent still `created` records the outcome from there instead of pushing again. Any later call for the intent (the same key again, or `my_payment`) completes a push that a crashed request left unsent.
4. **Idempotency key.** The browser sends a key per payment attempt: the same key returns the same intent (a different number under it is `key_reused`); keys keep their intent for 24 hours.
5. **One active payment per order.** A permanent claim (`order-payment`) names the order's current intent; a new attempt is refused (`payment_in_progress`) until that intent is final. A refused push fails the intent and frees the order for another attempt; later outcomes (cancelled, failed) free it in plan 5.4.
6. **Seats.** The order already made its seats `PAYMENT_PENDING` (P4.5), so a payment doesn't change them; an order past its `pay_by` can't be paid (`order_expired`).
7. **Forced replays in tests.** `replay_point(step)` raises one `WriteConflict` when `AFRICINEMAS_FAULTS` names `replay:<step>`, so Jac reruns the request. Tests force a rerun before the commit and after it (before the push); both end with exactly one push and one intent.

## Consequences
- A push that got no answer is `uncertain` and is never sent again; the callback URL's token (plan 5.4) or the resolver job (plan 5.5) settles it.
- If the server dies between winning the gate and keeping the result, the intent stays `created` with no record of whether a prompt was sent; the resolver treats it as uncertain and the order's `pay_by` ends it.
- The callback URL is `DARAJA_CALLBACK_BASE` + `/hooks/mpesa/<token>`; the endpoint itself comes with plan 5.4.
