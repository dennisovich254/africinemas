"""Joining a tenant's staff group (ADR-0004).

Jac counts every node a root links to as one of that root's groups, so a membership is
a MemberOf edge from the member's OWN root, created in the member's own request:
1. As the principal: allow the member to attach to the group (CONNECT), and flush.
2. As the member: link to the group, and let the principal delete that edge later.
3. As the principal: withdraw the CONNECT (no self-rejoin) and record the membership.
Each identity flushes its changes before the next switch (JI-020); all of it stays in
the request's one transaction.
"""

import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from core.tenancy.models { StaffGroup, Membership, MemberOf }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }

def join_group(principal_root_id: str, group: StaffGroup) -> Membership {
    # Call in the joining member's request (their root is the current root).
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
        membership = Membership(staff_root_id=me, edge_id=edge_id, role=group.role);
        group ++> membership;
        flush_now();
    } finally {
        restore(me);
    }
    return membership;
}
