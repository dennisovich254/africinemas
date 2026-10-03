# JI-038: A write conflict at session close is only logged: the client is told its writes succeeded

- **Version:** jaclang 0.37.18, `jac run` with the embedded Postgres
- **Found:** 2026-10-03, P4.7 (the seat-hold load test: 200 visitors holding seats at once)
- **Status:** open. **High**: silent data loss behind a success answer. Worked around (see below).

## What happened
200 anonymous requests ran `hold_seats` at once, each writing different seat nodes (as the cinema's principal: `act_as`, writes, `flush()`, `restore`) and creating one new node. Every request answered `200` with `"ok": true`. Afterwards about 80% of the winners' writes were missing: no hold node, seat fields unchanged. The server log shows, per lost request, in its trace:

```text
WARNING Permission denied: field_write on SeatSlot[...] owned by root[<principal>]; required WRITE, have NO_ACCESS
WARNING Permission denied: field_write on SeatHold[...] ...
WARNING commit on close failed: WriteConflict: WriteConflict: anchor <seat> changed concurrently (expected v2, found v1)
```

So the request's writes were flushed in its transaction; at session close the runtime flushed again as the caller (refused, as expected), then the COMMIT hit a write conflict. The transaction rolled back, the conflict was logged at WARNING, and the answer already computed was sent. The request was neither replayed nor answered with `409`.

Sequential requests are unaffected; the loss needs concurrent writers. `JAC_DB_RO_UNITS=0` (read tier off) does not change it.

## Docs
`jac guide reference/persistence`, "Concurrent writes": "A rejected request does not error. The server rolls back its uncommitted work ... and replays the walker (or function) from the start." With `on_conflict = "retry"` and `conflict_max_attempts`, a conflict should end in a replay or a `409 write_conflict`, never in a success answer.

## Workaround (in place)
Write paths that run concurrently end with `commit_now()` (`core/tenancy/principal.jac`): flush, then the `commit()` builtin, inside the function, still acting as the principal. A conflict then raises `WriteConflict` inside the unit of work, which Jac replays; nothing is left for the close-time commit. Used by the hold and order paths (`core/booking/hold_api.jac`, `core/booking/order_api.jac`). Their follow-up claim work runs after `commit_now()` returns rather than in `on_commit`.

## Suggested fix
Treat a failed close-time commit like a conflict inside the unit: replay the request (or answer `409`), and never send the answer of a unit whose transaction did not commit.
