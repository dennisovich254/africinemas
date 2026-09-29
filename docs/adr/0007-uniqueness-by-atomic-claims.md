# ADR-0007: Uniqueness is enforced by atomic claims, not graph find-or-create

- **Status:** Accepted (user decision 2026-09-28)
- **Date:** 2026-09-28
- **Sub-phase:** P2.1
- **Evidence:**
  - `tests/integration/tenant_slug_concurrency_tests.jac`: 8 concurrent claims on a real server, now passing
  - `tests/integration/claims_tests.jac`
  - [JI-024](../jac-issues/JI-024-find-or-create-does-not-converge.md) and its repro in `docs/jac-issues/repro/JI-024/`

## Context

Several rules need "exactly one": one tenant per slug (P2.1), one hold per seat (P4.3), one redemption per ticket (P6). The persistence reference promises that concurrent find-or-create requests converge on one node under SERIALIZABLE.

On Jac 0.37.18 they don't. With the docs' own pattern, 8 concurrent requests left up to 8 nodes for one key:
- in every variant: anonymous or signed in, with the read tier on or off;
- with a `200` for every request;
- and one raw `40001` escaped as a `500` (JI-024).

Jac has no unique constraint on nodes.

## Decision

Enforce uniqueness with **atomic claims** in `core/claims.jac`. A claim is one statement on Jac's shared store table `kv_state` (the table Jac's own token store uses), keyed by `africinemas:claim:<namespace>:<key>`:

```sql
INSERT INTO kv_state (key, value, expires_at) VALUES (...)
ON CONFLICT (key) DO UPDATE ... WHERE the existing claim has expired
RETURNING value
```

- **The primary key guarantees one holder.** Callers are told who the holder is, so a racer learns it lost.
- **Operations:**
  - `claim(ns, key, owner, ttl_seconds)`: `ttl_seconds` 0 means permanent. An expired claim can be taken over.
  - `holder(ns, key)`;
  - `make_permanent(ns, key, owner)` and `release(ns, key, owner)`, both holder-only.
- **Claims commit on their own connection, outside the request's graph transaction.** A claim made by a request that then fails stays behind. So anything provisional gets a TTL, and becomes permanent (or is released) only after the graph work succeeds:
  - signup (P2.2) claims the slug for a few minutes, then makes it permanent once the tenant exists;
  - a seat hold (P4.3) is a claim whose TTL is the hold time.
- **`core/claims.jac` is the only module that touches the shared store**, like `core/tenancy/principal.jac` for principals (ADR-0003). The claims tests are contract tests for Jac upgrades.
- **The graph keeps the data. The claim store keeps only "who holds which key".** The slug index is therefore not a graph node, and the earlier `TenantRegistry`/`TenantSlug` nodes are removed.

## Related decisions made while building P2.1

- **`[placement] default = "server"`** in `jac.toml`. Jac compiled an import-free module natively by default, and there an enum return came back as an `int` and a custom exception lost its type ([JI-026](../jac-issues/JI-026-native-placement-wrong-enum-and-exceptions.md)).
- **No non-string defaults on endpoint parameters**, because omitted ones arrive as strings ([JI-025](../jac-issues/JI-025-omitted-endpoint-defaults-arrive-as-strings.md)). This is enforced by `tests/unit/endpoint_signature_tests.jac`.

## Consequences

- One extra round trip per claim. Slugs are claimed rarely; seat holds are measured by the S5 load test (P4.7).
- Claims live outside the graph. Graph exports or backups don't include them, so the owning graph records (the Tenant's `slug`, a Hold node) remain the business record, and a repair job can rebuild claims from them if needed.
- If JI-024 is fixed upstream, graph convergence can take over again. The concurrency test will tell.
- **Applied in P2.2 (signup):** the tenant's id is picked first (`principal.fresh_node_id` + `assign_id`), the slug is claimed for it before anything else is created, a failure releases the claim and deletes the principal, and `on_commit` makes the claim permanent. **Residual risk:** if the server dies between the graph commit and `on_commit`, the provisional hold (15 min) can lapse while the tenant exists. A reconciliation job re-claims slugs of committed tenants (plan 11.1b).
- **Applied in P3.1 (venues and auditoriums):** venue names are unique per cinema (namespace `venue-name`, key `<tenant id>:<name>`) and auditorium names per venue (`auditorium-name`, key `<venue id>:<name>`). Names are compared with spaces collapsed and case folded. The claim's value is the node's id, picked before the node is created. A rename claims the new name and releases the old one on commit, and a delete releases its name on commit. **Residual risk:** as above; a crash before `on_commit` can leave a deleted or renamed-away name claimed, which the same reconciliation job clears (plan 11.1b). `tests/integration/auditorium_concurrency_tests.jac` races five creates of one name on a real server.
- **Applied in P3.2 (seat layouts):** each (screen, version number) is a claim (`layout-version`) held by the layout's id, so concurrent saves can't create one version twice. A short-lived edit lock per screen (`layout-edit`, 15 s TTL, released on commit or failure) lets one save or publish run at a time; a concurrent one is refused with `layout_busy`. The lock can't stop a database conflict on its own: a request that takes it just after another released it may still hold a transaction snapshot from before that commit. That conflict (PostgreSQL 40001) is re-run through Jac's `WriteConflict` retry (JI-031, `flush_now`).
- **Applied in P3.5a (screenings), with a lesson:** creating or moving a screening takes a per-screen schedule lock (`screen-schedule`, 15 s TTL, released on commit or failure), then checks for overlaps by reading the screen's screenings from the graph. That wasn't enough on its own. A concurrency test created two overlapping screenings in one of three runs: a request took the lock just after another released it, but its transaction snapshot predated that commit, so its graph read didn't include the new screening. The two requests wrote different records (each a new screening), so nothing clashed at commit (compare JI-024). The fix materialises the conflict: each create or reschedule also bumps `Auditorium.schedule_rev`, so concurrent schedulings of one screen write the same record, the database rejects the later one (40001), and Jac re-runs it (`flush_now`, JI-031), which then sees the overlap. **Rule:** a claim used as a lock doesn't protect a check made by reading the graph; make competing writers touch one shared record, or keep the check itself in a claim.
