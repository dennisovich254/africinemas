# JI-031: A serialization failure (40001) inside a function endpoint answers 500 instead of being retried

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-29, P3.2 (concurrent `save_layout` calls on one screen, real server)
- **Status:** open (worked around in `core/tenancy/principal.jac`)

## What we saw
Five concurrent requests updated the same node (a seat layout draft). Some requests answered HTTP 500:
```
save_layout raised PgWireError: {'C': '40001', 'M': 'could not serialize access due to concurrent update',
                                  'F': 'nodeModifyTable.c', 'R': 'ExecCheckTupleVisible'}
```
The traceback runs from our `mem.flush(full=True)` (called mid-request, see JI-020) through `PgStore.upsert` to the `INSERT ... ON CONFLICT (id) DO UPDATE ... WHERE anchors.version = EXCLUDED.version` statement. The server log had no "re-running request" line.

## Why (from reading the runtime)
- `PgStore.upsert` raises `WriteConflict` when its version check matches no row. Under SERIALIZABLE, though, PostgreSQL can abort the statement itself with 40001 before that check returns. That surfaces as a raw `PgWireError`.
- Function endpoints run through `_run_function_with_occ` (`server/impl/server.impl.jac`). It retries `WriteConflict` and `ReadOnlyRetry` only; any other exception becomes a 500.
- `Session.run_request` and `Session.commit` (`server/impl/session.impl.jac`) do treat 40001/40P01 as retryable (`_is_serialization_conflict`). The function path above doesn't use that check.

We saw this with a flush made inside the request body. We haven't tested whether a 40001 raised by the end-of-request commit is retried.

## Workaround (in place)
`flush_now()` catches a 40001/40P01 error and raises `WriteConflict` instead, so the OCC loop re-runs the request in a fresh transaction. `jac.toml` sets `[serve] conflict_backoff_ms = 20` (default 0), so racing retries don't collide again at once. `tests/integration/seat_layout_concurrency_tests.jac` races five saves twice; before the workaround it failed 2 of 3 runs, and after it passed 3 of 3.

## Related
Endpoints re-run this way must be safe to repeat. Ours are: external effects happen in `on_commit`, and claims taken before a failure are released.
