"""Staff membership (ADR-0004, ADR-0008 as revised in P2.5).

A staff member has exactly two things in a tenant:
- a MemberOf edge from their OWN root to the tenant's access group, which is what the
  graph grants key on. Jac counts every node a root links to as one of its groups, so
  the edge must be created in the member's own request:
  1. as the principal: allow the member to attach to the group (CONNECT), flush;
  2. as the member: link to the group, and let the principal delete that edge later;
  3. as the principal: withdraw the CONNECT (no self-rejoin);
- a Membership record, owned by the tenant's principal and readable only by that
  member, holding their role keys and status. Owners and admins change roles by editing
  it, which is why roles live here and not on edges the member would have to create.
Each identity flushes before the next switch (JI-020); it all stays in one transaction.
"""

import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from core.clock { now }
import from core.tenancy.models { Tenant, StaffGroup, Membership, MemberOf }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }

def link_to_group(principal_root_id: str, group: StaffGroup) -> str {
    # Creates the caller's MemberOf edge to `group` (steps 1-3). Returns the edge id.
    me = node_id(root);
    act_as(principal_root_id);
    try {
        Jac.allow_root(group, UUID(me), AccessLevel.CONNECT);  # jac:ignore[E1053]
        flush_now();
    } finally {
        restore(me);
    }
    root +>:MemberOf:+> group;
    edge_id = "";
    for e in [edge root->:MemberOf:->group] {
        Jac.allow_root(e, UUID(principal_root_id), AccessLevel.WRITE);  # jac:ignore[E1053]
        edge_id = node_id(e);
    }
    flush_now();
    act_as(principal_root_id);
    try {
        Jac.disallow_root(group, UUID(me));  # jac:ignore[E1053]
        flush_now();
    } finally {
        restore(me);
    }
    return edge_id;
}

def new_record(
    group: StaffGroup, staff_root_id: str, edge_id: str, roles: list[str]
) -> Membership {
    # Call while acting as the tenant's principal.
    record = Membership(
        staff_root_id=staff_root_id,
        edge_id=edge_id,
        roles=roles,
        joined_at=now().isoformat()
    );
    group ++> record;
    # Only the member (and the principal, its owner) can read it.
    Jac.allow_root(record, UUID(staff_root_id), AccessLevel.READ);  # jac:ignore[E1053]
    return record;
}

def records_of(tenant: Tenant) -> list[Membership] {
    # Every membership record of `tenant`. Call while acting as its principal.
    return [
        m
        for g in [root-->[?:StaffGroup]]
        if g.tenant_id == node_id(tenant) for m in [g-->[?:Membership]]
    ];
}

def remove_member(tenant: Tenant, staff_root_id: str) -> int {
    # Removes `staff_root_id` from `tenant`: their MemberOf edge and their record.
    # Returns how many role keys they held. Their next call finds nothing (P2.4).
    target = str(UUID(staff_root_id));
    caller = node_id(root);
    removed = 0;
    act_as(tenant.principal_root_id);
    try {
        for m in records_of(tenant) {
            if m.staff_root_id == target {
                member_edge: any = jobj(m.edge_id);  # jac:ignore[W1037]
                if member_edge is not None {
                    Jac.destroy([member_edge]);
                }
                removed += len(m.roles);
                Jac.destroy([m]);
            }
        }
        flush_now();
    } finally {
        restore(caller);
    }
    return removed;
}
