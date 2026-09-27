# ADR-0003: Each tenant's subgraph is owned by a per-tenant service principal

- **Status:** Accepted (spike S1 passed on Jac 0.37.18)
- **Date:** 2026-09-27
- **Sub-phase:** P1.1
- **Evidence:** `tests/spikes/s1_tenant_principal_tests.jac` (8 tests) against the test-only app `tests/spikes/s1_app.jac`

## Context

The architecture (§4, layer 1) wants every tenant's data to hang off a `Tenant` node that is **not** owned by the cinema owner's personal account. In Jac a node's owner always keeps WRITE access, and nobody can take it away. If the human owner's root owned the tenant, changing owner or offboarding the owner (§16) couldn't be done safely.

Spike S1 (§138) asked: can a server-side flow, running on behalf of the signed-up owner, create a per-tenant service principal and create nodes owned by it? The fallback was to have the platform system identity own all tenant data, with the boundary enforced only by `authorize()` and group grants.

## What the spike showed

All pass criteria hold on a served app (the in-process `JacTestClient`):

| Test | Result |
| --- | --- |
| The Tenant and its Venue are owned by the tenant's principal, not the calling owner | pass |
| Each tenant gets its own principal | pass |
| The owner reaches the tenant (and the venue) with WRITE, by grant | pass |
| Another tenant's owner can't read or write it, even holding its id; a tamper attempt doesn't stick | pass |
| The owner's grant can be revoked, which is possible because they don't own the nodes | pass |
| Nobody can log in as the principal | pass |
| The subgraph persists under the principal's root across an app restart (new client, same store) | pass |
| After the owner steps down, the tenant stays persisted under its principal (no orphaned data) | pass |

**How it works** (no documented API exists for this; see Risks):

1. `JacRuntime.get_user_manager(base_path).create_internal_user(name, password)` creates the principal. The name is `svc-tenant-<random>`, and the password is 32 random bytes that are never stored or returned.
2. `ensure_user_root(user_id)` returns the principal's root id.
3. `JacRuntime.get_context().set_user_root(principal_root_id)` switches the request's root. The Tenant is attached to that root, so it persists there, and every node created is owned by the principal. The caller's root is restored in a `finally` block. `set_user_root` also resets the entry node.
4. While acting as the principal, `allow_root(node, owner_root, WRITE)` grants the owner access. In P1.2 this becomes an `allow_group` on the tenant's StaffGroup.

## Decision

Adopt the per-tenant service principal model. The fallback is not needed.

Rules for Phase 2 onwards:

1. **One module owns the mechanism.** Only `core/tenancy/` may call `create_internal_user`, `ensure_user_root` or `set_user_root`. It exposes a small helper (for example `as_principal(tenant, fn)`) that always restores the caller's root. The S1 spike tests stay in the suite as **contract tests**, so a Jac upgrade that changes these internals fails CI rather than production.
2. **Changes to an existing principal-owned node that the caller can't write must be flushed while acting as the principal.** Call `core/tenancy/principal.flush_now()` before switching back. Never `Jac.commit()` mid-request: it commits the transaction midway, which breaks the request's atomicity under replay (corrected in P1.2, see ADR-0004). At the end of a request, Jac's flush re-checks write access under the caller's root and **silently drops** rows the caller can't write ([JI-020](../jac-issues/JI-020-self-revocation-silently-not-persisted.md)). The spike's revocation only worked after this change.
3. **Never use `jobj()` for authorization.** Resolve client-supplied ids by traversal from the caller's `Tenant` node, as §4 already requires. In 0.37.18 `jobj` returned `None` for a node the caller can't read, but the guides say it resolves regardless of grants ([JI-021](../jac-issues/JI-021-jobj-returns-none-without-access.md)). Neither behaviour is a boundary.
4. **Principals are ordinary accounts** (role `user`) whose credentials nobody knows. They appear in the admin user list with the `svc-tenant-` prefix. P2 records each principal's id on the Tenant node and in the platform control graph.

## Risks

- **Internal API.** `UserManager` and `ExecutionContext.set_user_root` are runtime internals, not documented guide APIs. The contract tests (rule 1) and the pinned Jac version (`==0.37.18`) contain this. Upgrades are deliberate PRs that must pass the spike tests.
- **Silent write drops (JI-020).** An unauthorized write is dropped without an error, which is safe but easy to miss. P2 tests assert on persisted state (a follow-up request, or a restart), never on in-request values.
