# ADR-0016: The Daraja adapter: never retry a push, retry reads, keep secrets out of logs

- **Status:** Accepted
- **Date:** 2026-10-06
- **Sub-phase:** P5.2
- **Code:** `core/payments/daraja.jac`, `core/payments/choice.jac`, `core/payments/provider.jac`
- **Tests:** `tests/unit/daraja_tests.jac` (fixtures in `tests/fixtures/daraja/`), `tests/unit/payment_choice_tests.jac`

## Context
Plan 5.2 puts Safaricom's Daraja API behind the `PaymentProvider` interface (ADR-0015): OAuth, the STK push and the STK status query. A push puts a PIN prompt on a customer's phone, so a duplicate means a second prompt and possibly a second charge. Daraja has no idempotency key for pushes.

## Decision
1. **OAuth token cache.** A client-credentials token is fetched once and reused until 60 seconds before its `expires_in`; if Daraja refuses it earlier (HTTP 401), one new token is fetched and the call repeated once. One provider instance per process holds the token.
2. **A push is never retried.** If the push gets no answer (a timeout), the result is `uncertain`: the prompt may or may not have reached the phone. The per-payment token in the callback URL (plan 5.4) still matches a payment the customer completes, and a status query is impossible without a `CheckoutRequestID`, so the caller treats the payment as unsettled rather than pushing again.
3. **Reads are retried.** OAuth and the status query are retried (twice, with backoff) on timeouts and network errors; a status query that never answers is `UNKNOWN`, which the resolver job (plan 5.5) settles later.
4. **Exact fields.** The push sends Daraja's fields: `Password = base64(shortcode + passkey + timestamp)` with the timestamp in Nairobi time (`YYYYMMDDHHMMSS`), the amount in whole shillings (prices are whole shillings, ADR-0015), the customer's `2547…`/`2541…` number, an https `CallBackURL`, `AccountReference` up to 12 characters and `TransactionDesc` up to 13. Paybill (`CustomerPayBillOnline`, the default) or Till (`CustomerBuyGoodsOnline`) is a setting.
5. **Query results.** `ResultCode` maps to a state (0 paid, 1032 cancelled, else failed); Daraja's "the transaction is being processed" error is still waiting (`STK_REQUESTED`); an unknown `CheckoutRequestID` is `UNKNOWN`.
6. **Callbacks are parsed, not trusted.** `parse_callback` turns Safaricom's body into an `StkStatus` with the receipt, amount and phone on success; plan 5.4 confirms every success with a status query (§33).
7. **No secrets in logs.** The config's printed form omits the key, secret and passkey; tokens and passwords are never logged; phone numbers are masked (`2547*****678`). A test captures the log output to prove it. A missing Daraja setting is reported by name, never by value.
8. **Configuration.** `AFRICINEMAS_PAYMENTS=daraja` with `DARAJA_CONSUMER_KEY`, `DARAJA_CONSUMER_SECRET`, `DARAJA_SHORTCODE`, `DARAJA_PASSKEY` (and optionally `DARAJA_BASE_URL`, defaulting to the sandbox, and `DARAJA_TRANSACTION_TYPE`). These are the platform's sandbox credentials for now; per-cinema merchant accounts with credentials in a secrets manager (§30, §31) come with onboarding.

## Consequences
- The contract tests run against bodies in Daraja's documented formats, not recordings; plan 5.7's real sandbox run replaces them with recorded responses.
- A status query doesn't return the receipt or amount; those come from the callback, which 5.4 keeps (the query only confirms the outcome).
