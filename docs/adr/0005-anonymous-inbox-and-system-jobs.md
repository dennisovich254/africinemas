# ADR-0005: Anonymous callbacks write to a system-owned inbox; a scheduled system job processes it

- **Status:** Accepted (spike S4 passed on Jac 0.37.18, on a real server)
- **Date:** 2026-09-27
- **Sub-phase:** P1.3
- **Builds on:** ADR-0003 (tenant principals), ADR-0004 (flush, `on_commit`)
- **Evidence:** `tests/spikes/s4_receipt_job_tests.jac` against `tests/spikes/s4_app.jac`, served by `jac run` with the scheduler enabled

## Context

M-Pesa (Daraja) confirms payments by calling our server **anonymously**, and guest checkout also runs without a login. Spike S4 (architecture §138) asked: can an anonymous `def:pub` request write a record that a system-identity worker later processes into tenant-owned data?

The fallback was a `root.shared` inbox with a restricted `__jac_access__`, with guest checkout deferred.

## What the spike showed

One test, run against a real server (the scheduler only runs in a served process), checked in order:

1. An anonymous `def:pub` records a receipt. A retried callback with the same reference is recognised as a duplicate and returns the same receipt.
2. An anonymous caller holding a receipt id **can't resolve it, read it or change it**.
3. A static `@schedule` task turns the receipt into a `Payment` **owned by the tenant's principal**. The owner reads it by grant, and another user sees nothing.
4. The job runs as **Jac's system identity**: its root is the system root, `00000000-0000-0000-0000-000000000000`. Later runs don't reprocess anything.
5. A receipt naming an unknown tenant is marked `rejected` and creates nothing.
6. After a server restart, the payment and both receipt states are intact.

## Why the inbox is system-owned

Anonymous requests all run on the **same** guest root. A node an anonymous request creates is owned by that root, so every other anonymous caller would own it too and could read, change or delete it. Instead, `record_receipt` acts as the system root just long enough to append the receipt to a system-owned `Inbox` (`core/tenancy/principal.system_root_id()` plus `act_as`), then restores the guest root. The system root is also exactly where the static job starts.

## Decision

Adopt the system inbox and scheduled system job. The fallback is not needed.

1. **Inbound anonymous records** (payment callbacks, guest checkout submissions) are appended to a system-owned inbox. The public endpoint does nothing else as the system root: it validates input shape, appends, and restores the caller in a `finally`.
2. **Processing is a static `@schedule` task**, which runs as the system identity. For each new record it:
   1. resolves the tenant;
   2. acts as the tenant's principal to create tenant data;
   3. applies grants through the tenant helper (ADR-0004);
   4. marks the record processed or rejected.
3. **Idempotent everywhere.** Every server replica fires its own copy of a static task. Records carry a status and a unique external reference (for example the M-Pesa receipt number). Re-runs and duplicate callbacks are no-ops.
4. **Flush per identity switch** inside the job, as in ADR-0004. External calls (for example a Daraja status query) go in `on_commit` or in a later job step, never before the graph write that records them.
5. **`[scale.scheduler] enabled = true`** is now set in `jac.toml`. `jac install` adds `apscheduler` to the project venv.

## Consequences and open points

- The public endpoint briefly holds system rights. The code that does this is small and lives in one module, and review must keep it that way.
- The callback's **authenticity** is not addressed here. Daraja callbacks aren't signed. P5 verifies each payment against Daraja's transaction status API before a booking is confirmed.
- With several replicas, two can process the same receipt concurrently. SERIALIZABLE plus replay should make the loser see `processed` and skip it. That is tested with real concurrency in spike S5.
- Latency is up to one scheduler interval. The spike used 1 s; P5 picks the production interval.
