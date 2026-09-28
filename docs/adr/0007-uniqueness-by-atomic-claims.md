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
