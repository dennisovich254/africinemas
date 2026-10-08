# JI-042: A write after a mid-request commit re-runs the whole request, repeating the work already committed

- **Version:** jaclang 0.37.18, `jac run` / in-process test app with the embedded Postgres
- **Found:** 2026-10-08, P7.2 (the audit log)
- **Status:** open. **High for this app** if hit (a sale or a ticket scan done twice, the second answer a refusal); worked around.

## What happened
Endpoints that commit part-way through their work (`commit_now()`: the cash sale, the M-Pesa prompt at the counter, the door scan) gained one more write at the end: the audit event. The first call of each of these endpoints in a fresh app then did its work twice. The first run committed (ticket used, order confirmed, payment created); the run that answered found that done and refused (`already_redeemed`, `no_order`, `payment_in_progress`). Later calls of the same endpoint were fine. The server logged, at INFO:

```text
read tier: unit core.booking.redeem_api.redeem_ticket wrote inside a read-only snapshot; re-running at SERIALIZABLE and recording it as a writer
```

So a request starts on a read-only snapshot. After `commit()` inside the unit, the next transaction is read-only again. A write in it makes Jac re-run the unit from the start as a writer, and the work committed before is not undone. The first write before any commit is handled without a re-run of committed work (the unit has committed nothing yet).

## Docs
`jac guide reference/persistence` and the 0.37.x release notes: read-only units run at `REPEATABLE READ READ ONLY`, and a unit that writes is restarted at SERIALIZABLE. Nothing says that a unit which already committed (the `commit()` builtin) is re-run from the start, repeating what it committed.

## Workaround (in place)
- **The read tier is off:** `core/tenancy/principal.jac` sets `JAC_DB_RO_UNITS=0` when imported (every app imports it), so every request runs at SERIALIZABLE from its start and is never re-run to upgrade. Writing first was not enough: the cash sale was still re-run, because the transaction after `commit()` was read-only again. And the "writer" mark lapses after `JAC_DB_RO_WRITER_TTL_S` (300 s), so in production the first sale after a quiet spell would have been hit. `tests/unit/read_tier_tests.jac` checks the setting.
- **Also:** `audited` (`core/audit/log.jac`) writes the event ("pending") before the endpoint's work and sets its result after.

## Suggested fix
For the Jac team: once a unit has committed (`commit()`), don't re-run it on a later write; begin the next transaction at SERIALIZABLE instead (the unit is evidently a writer). Or refuse the write with a clear error, rather than replaying work that can't be rolled back.
