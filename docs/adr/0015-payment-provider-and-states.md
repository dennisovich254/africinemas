# ADR-0015: One payment provider interface, a scripted simulator, and explicit states

- **Status:** Accepted
- **Date:** 2026-10-03
- **Sub-phase:** P5.1
- **Code:** `core/payments/state.jac`, `core/payments/provider.jac`, `core/payments/simulator.jac`, `core/payments/choice.jac`, `core/payments/phone.jac`
- **Tests:** `tests/unit/payment_state_tests.jac`, `tests/unit/payment_simulator_tests.jac`, `tests/unit/payment_choice_tests.jac`, `tests/unit/phone_tests.jac`

## Context
Phase 5 takes M-Pesa payments through Safaricom's Daraja API (architecture §29–§37): an STK push asks the customer for their PIN, and the result comes back twice over, as a callback Safaricom POSTs to us and as a status query we can make. We need to build and test every outcome (paid, insufficient funds, cancelled, no answer, paid too late, push refused) long before, and without depending on, Safaricom's sandbox.

## Decision
1. **One interface.** `PaymentProvider` has two operations: `stk_push(StkRequest) -> StkPushResult` and `query(checkout_request_id) -> StkStatus`. A callback, once parsed (plan 5.4), is also an `StkStatus`, so the app handles both answers the same way. Daraja (plan 5.2) and the simulator implement it.
2. **A scripted simulator.** `SimulatedProvider` scripts each push's outcome by phone number: `success`, `fail` (ResultCode 1), `cancel` (1032), `timeout` (no callback; the query says 1037), `late_success` (nothing until `pay_late()`, then paid) and `reject` (the push is refused). `callback()` is what Safaricom would POST; `push_count(reference)` lets tests prove how many PIN prompts a payment caused (plan 5.3).
3. **Explicit states** (§32): `CREATED → STK_REQUESTED → SUCCESS | FAILED | CANCELLED | TIMEOUT | UNKNOWN`, with `CREATED → FAILED` for a refused push and `TIMEOUT`/`UNKNOWN` settled later by a status query. Any other move raises `InvalidTransition`; moving to the current state is a no-op, so a duplicate callback changes nothing.
4. **`NEEDS_ATTENTION`, added to §32.** Plan 5.4 needs a state for what can't be settled automatically: a paid amount that doesn't match, or a success after the payment failed, was cancelled or timed out (the seats may be gone; a refund task follows). It is reachable from `STK_REQUESTED`, `TIMEOUT`, `UNKNOWN`, `FAILED` and `CANCELLED`, and is final for the machine. Refunds and reversals stay ledger entries (§37).
5. **No default provider.** `payment_provider()` reads `AFRICINEMAS_PAYMENTS` (`simulator`; `daraja` from 5.2) and refuses when it is unset or unknown, so a forgotten setting can never mean fake payments and free tickets. The simulator is one instance per process.
6. **Money and numbers.** Amounts are cents like every price, but M-Pesa takes whole shillings, so a fractional amount is refused before it is sent. `msisdn()` turns what customers type (`0712 345 678`, `+254…`) into `2547XXXXXXXX` / `2541XXXXXXXX`.

## Consequences
- 5.3 (`initiate_payment`) and 5.4 (callbacks and verification) build against the interface and are tested with the simulator; 5.2 adds the Daraja adapter behind the same interface.
- The simulator's state lives in one process, so tests and demos run one server worker when they use it.
- Prices must be whole shillings to be payable by M-Pesa; the price list allows cents, so 5.3 refuses (or the price editor should prevent) fractional totals.
