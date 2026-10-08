# JI-042: A write after a mid-request commit re-runs the whole request, repeating the work already committed

- **Version:** jaclang 0.37.18, `jac run` / in-process test app with the embedded Postgres
- **Found:** 2026-10-08, P7.2 (the audit log)
- **Status:** open. **High for this app** if hit (a sale or a ticket scan done twice, the second answer a refusal); avoided (no graph write after a part-way commit). Note: the writer mark lapses after `JAC_DB_RO_WRITER_TTL_S` (300 s), so in production the first call after a quiet spell is the one at risk.

## What happened
Endpoints that commit part-way through their work (`commit_now()`: the cash sale, the M-Pesa prompt at the counter, the door scan) gained one more write at the end: the audit event. The first call of each of these endpoints in a fresh app then did its work twice. The first run committed (ticket used, order confirmed, payment created); the run that answered found that done and refused (`already_redeemed`, `no_order`, `payment_in_progress`). Later calls of the same endpoint were fine. The server logged, at INFO:

```text
read tier: unit core.booking.redeem_api.redeem_ticket wrote inside a read-only snapshot; re-running at SERIALIZABLE and recording it as a writer
```

So a request starts on a read-only snapshot. After `commit()` inside the unit, the next transaction is read-only again. A write in it makes Jac re-run the unit from the start as a writer, and the work committed before is not undone. The first write before any commit is handled without a re-run of committed work (the unit has committed nothing yet).

## Docs
`jac guide reference/persistence` and the 0.37.x release notes: read-only units run at `REPEATABLE READ READ ONLY`, and a unit that writes is restarted at SERIALIZABLE. Nothing says that a unit which already committed (the `commit()` builtin) is re-run from the start, repeating what it committed.

## Workaround (in place)
- **The audit log writes outside the graph** (`core/audit/log.jac`, Jac's shared store): an audited endpoint makes no graph write after its work, so nothing can trigger the re-run.
- **Rule for this app:** in an endpoint that commits part-way (`commit_now()`), don't make a graph write after the commit.
- **Tried and dropped:** turning the read tier off (`JAC_DB_RO_UNITS=0`). It removed the re-run, but then every read ran at SERIALIZABLE, and concurrent requests failed with Postgres serialization errors on reads, which Jac answers as 500s in function endpoints (JI-031). Writing the audit event before the work didn't help either: the cash sale was still re-run.

## Checked: the M-Pesa start path
`_start_payment` (`core/payments/payment_api.jac`) writes the graph after its commit (the push result, `ensure_pushed`). That is safe in practice: Jac keeps writer marks in a per-process table (`_unit_writers`, `jaclang/server/session.jac`), and an expired mark is removed, so "the first payment after a quiet spell" is the same state as "the first payment in a fresh app". Every payment test file starts a fresh app and its first payment passes, so that path is covered. Why the cash sale differed (its first write before the commit did not record it as a writer) is not established.

## Suggested fix
For the Jac team: once a unit has committed (`commit()`), don't re-run it on a later write; begin the next transaction at SERIALIZABLE instead (the unit is evidently a writer). Or refuse the write with a clear error, rather than replaying work that can't be rolled back.
