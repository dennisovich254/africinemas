# ADR-0004: Staff reach tenant data through one StaffGroup grant per node

- **Status:** Accepted (spike S2 passed on Jac 0.37.18)
- **Date:** 2026-09-27
- **Sub-phase:** P1.2
- **Builds on:** ADR-0003 (the tenant's service principal owns the subgraph)
- **Evidence:** `tests/spikes/s2_staff_group_tests.jac` (10 tests) against `tests/spikes/s2_app.jac`

## Context

Spike S2 (architecture §138) asked:
- Do `allow_group` grants on tenant nodes let staff (via `MemberOf` → `StaffGroup`) **read and write** through normal traversal?
- Does removing a membership revoke access **immediately**?
- Do tenant B's staff see nothing of tenant A?

The fallback was one `allow_root` per staff member per node, which costs O(staff) entries per node and needs a rewrite on every join and leave.

## What the spike showed

| Test | Result |
| --- | --- |
| Staff who accepted an invite reach the tenant and its venue with WRITE, through the group | pass |
| A staff write persists, and the owner sees it | pass |
| Joining adds no per-user entry to tenant nodes: one group entry covers all staff | pass |
| A venue added after joining is visible to existing staff | pass |
| Removing the membership revokes access on the very next request | pass |
| Removed staff can't rejoin on their own, and strangers can't self-join with the group id | pass |
| An invite works only once | pass |
| Tenant B's staff see nothing of tenant A, even with its ids | pass |
| Memberships, grants and removals persist across a restart | pass |
| A used invite is consumed on commit: repeats are refused and nothing duplicates | pass |

## How Jac resolves groups (read from the 0.37.18 source)

`_groups_of(root)` returns **every node the user's root has an outgoing edge to**, whatever the edge type. A group grant on a node applies to anyone whose root links to the group node. That shapes the design:

- **Membership is an edge from the staff member's own root**, so it is created in the staff member's own request (accepting an invite).
- **Nobody may be able to attach to a StaffGroup on their own.** Attaching needs CONNECT on the group. The principal grants it to the joining member for the length of the join only, then withdraws it.
- **The staff member owns the membership edge.** At join time they grant the principal WRITE on it, which is what later lets the tenant delete it.
- **The principal can't see the edge from the group's side.** It isn't in the group's incoming edges when read as the principal. So the join also writes a principal-owned `Membership` record with the member's root id and the edge id. Removal resolves the edge by id and destroys it. The records double as the staff roster.

## Decision

Adopt group grants. The fallback is not needed.

1. **One `StaffGroup` per tenant** (role groups come in P2: one group per role, same mechanism), owned by the tenant's principal and linked `StaffGroup -[ForTenant]-> Tenant`. Members traverse `root → StaffGroup → Tenant → …`, so the group grants READ on itself.
2. **`_attach_to_tenant(node, tenant)`** is the only place tenant nodes get their grants: `allow_group(staff_group, WRITE)` plus the owner's grant. Grants are per node, not per subtree, so every creation path calls it. A test in P2 enforces this, per architecture §112.
3. **Join flow** (the staff member's request):
   1. Peek the invite token.
   2. As the principal: mark the principal-owned `Invite` node used, and grant the member CONNECT on the group.
   3. As the member: create the `MemberOf` edge, and grant the principal WRITE on it.
   4. As the principal: withdraw the CONNECT, and write the `Membership` record.
   5. `on_commit`: consume the token.
4. **Removal** (the owner's request, acting as the principal): destroy the membership edge and its record.
5. **Only StaffGroup ids are ever used as group ids** in `allow_group`. Any node a user links to counts as one of their groups (for example the owner's `OwnsTenant` edge to their Tenant), so granting on any other id would leak.

## Rules this spike added to ADR-0003's

- **Flush, never commit, mid-request.** `Jac.commit()` inside a request does a real `COMMIT` and runs `on_commit` callbacks early. A later replay would then leave half the work applied. `core/tenancy/principal.flush_now()` writes pending rows into the **same** open transaction, with the ACL check under the current identity, which is all the JI-020 workaround needs. ADR-0003 is updated to match.
- **External side effects go in `on_commit`.** Jac replays a request from the start on a write conflict, and on the first write of a function it has seen only reading (the "read tier", `reference/persistence`). Anything outside the graph (a token consume, an email, an M-Pesa STK push) belongs in `on_commit`, or it runs once per attempt. Single-use state lives in the graph (`Invite.used_by`), where SERIALIZABLE and replay resolve races.

## What we could not show

- **A forced replay.** The first version of the join consumed the token in the function body and called `Jac.commit()` midway. Its first call in a fresh process ran twice (logged), and the invite was burned. We couldn't tell whether that replay was the read-tier upgrade or a conflict provoked by the mid-request commit: with the in-process test client the runtime's writer record stayed empty. The current flow follows the documented rule, but a test that forces a replay waits for spike S5 (concurrency on a real server).
- **Truly concurrent redemptions of one invite.** Sequential double use is refused. Concurrent use relies on SERIALIZABLE conflict detection on `Invite.used_by`, which is also covered in S5.
