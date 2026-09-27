"""Spike S2 (plan P1.2): staff reach tenant nodes through a StaffGroup grant.

Test-only app entry (never imported by main.jac). Builds on ADR-0003: the tenant's
service principal owns the Tenant, its StaffGroup and its Venues. Each tenant node
carries one `allow_group` entry for the StaffGroup, whatever the number of staff.

Membership is an edge from the staff member's own root to the StaffGroup: Jac counts
every node a root has an outgoing edge to as one of its groups (jaclang
`_groups_of`). So:
- joining happens in the staff member's own request (accepting an invite token),
  with a CONNECT grant on the group that exists only for that moment;
- the member grants the principal WRITE on the membership edge, so the tenant can
  remove it later;
- each identity's changes are committed before switching (JI-020).
"""

import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from jaclang.server.identity.app_tokens {
    token_create,
    token_peek,
    token_consume
}
import from core.tenancy.principal {
    node_id,
    access_level,
    new_principal,
    act_as,
    restore,
    flush_now
}

glob INVITE: str = "staff-invite";

node Tenant {
    has name: str,
        principal_root_id: str = "",
        staff_group_id: str = "";
}

node StaffGroup {
    has tenant_id: str = "";
}

node Invite {
    has used_by: str = "";
}

node Membership {
    has staff_root_id: str,
        edge_id: str;
}

node Venue {
    has name: str;
}

edge HasVenue {}

edge ForTenant {}

edge MemberOf {}

edge OwnsTenant {}

def _attach_to_tenant(n: any, tenant: Tenant, owner_root_id: str) {  # jac:ignore[W1037]
    # The one place tenant nodes get their grants: the staff group (one entry) and the owner.
    Jac.allow_group(n, UUID(tenant.staff_group_id), AccessLevel.WRITE);  # jac:ignore[E1053]
    Jac.allow_root(n, UUID(owner_root_id), AccessLevel.WRITE);  # jac:ignore[E1053]
}

def _owned_tenant(tenant_id: str) -> Tenant {
    found: any = jobj(tenant_id);  # jac:ignore[W1037]
    if found is None or not Jac.check_write_access(found.__jac__) {
        raise PermissionError("not a tenant you manage");
    }
    return found as Tenant;
}

def:priv s2_create_tenant(name: str) -> dict[str, str] {
    caller = node_id(root);
    principal = new_principal(name);
    act_as(principal);
    try {
        tenant = Tenant(name=name, principal_root_id=principal);
        root ++> tenant;
        group = StaffGroup(tenant_id=node_id(tenant));
        root ++> group;
        tenant.staff_group_id = node_id(group);
        group +>:ForTenant:+> tenant;
        venue = Venue(name=f"{name} Main Hall");
        tenant +>:HasVenue:+> venue;
        # Members traverse *through* the group, so it needs READ for its own members.
        Jac.allow_group(group, UUID(tenant.staff_group_id), AccessLevel.READ);  # jac:ignore[E1053]
        for n in [tenant, venue] {
            _attach_to_tenant(n, tenant, caller);
        }
        # The owner has no grant on the group, so flush it now, as its owner (JI-020).
        flush_now();
    } finally {
        restore(caller);
    }
    root +>:OwnsTenant:+> tenant;
    return {
        "tenant_id": node_id(tenant),
        "group_id": tenant.staff_group_id,
        "principal_root_id": principal
    };
}

def:priv s2_add_venue(tenant_id: str, name: str) -> str {
    tenant = _owned_tenant(tenant_id);
    caller = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        venue = Venue(name=name);
        tenant +>:HasVenue:+> venue;
        _attach_to_tenant(venue, tenant, caller);
        flush_now();
    } finally {
        restore(caller);
    }
    return node_id(venue);
}

def:priv s2_invite(tenant_id: str) -> str {
    tenant = _owned_tenant(tenant_id);
    caller = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        # Single use lives in the graph (transactional), not in the token store.
        invite = Invite();
        (jobj(tenant.staff_group_id) as StaffGroup) ++> invite;
        flush_now();
    } finally {
        restore(caller);
    }
    # A replay of this request can mint an extra token; it points at an Invite that was
    # rolled back, so it can never be redeemed, and it expires with its TTL.
    return token_create(
        INVITE,
        subject=node_id(invite),
        ttl_seconds=3600,
        payload={
            "principal_root_id": tenant.principal_root_id,
            "group_id": tenant.staff_group_id,
            "invite_id": node_id(invite)
        }
    );
}

def _is_member(group_id: str) -> bool {
    return any(node_id(g) == group_id for g in [root->:MemberOf:->[?:StaffGroup]]);
}

def:priv s2_join(token: str) -> dict[str, any] {
    # Replay-safe: no external side effect runs before the commit. The token is only
    # peeked here and consumed in on_commit (reference/persistence, "Side effects and
    # replay"); single use is enforced by the Invite node inside the transaction.
    got = token_peek(INVITE, token);
    if got is None {
        return {"joined": False, "reason": "invalid or expired invite"};
    }
    principal = str(got["payload"]["principal_root_id"]);
    group_id = str(got["payload"]["group_id"]);
    invite_id = str(got["payload"]["invite_id"]);
    me = node_id(root);
    if _is_member(group_id) {
        return {"joined": True, "reason": "already a member"};
    }
    # 1. As the principal: claim the invite and allow me to attach to the group.
    act_as(principal);
    try {
        found: any = jobj(invite_id);  # jac:ignore[W1037]
        if found is None or (found as Invite).used_by {
            return {"joined": False, "reason": "invite already used"};
        }
        (found as Invite).used_by = me;
        Jac.allow_root(jobj(group_id), UUID(me), AccessLevel.CONNECT);  # jac:ignore[E1053]
        flush_now();
    } finally {
        restore(me);
    }
    # 2. As me: join, and let the principal remove this membership later.
    group = jobj(group_id) as StaffGroup;
    root +>:MemberOf:+> group;
    edge_id = "";
    for e in [edge root->:MemberOf:->group] {
        Jac.allow_root(e, UUID(principal), AccessLevel.WRITE);  # jac:ignore[E1053]
        edge_id = node_id(e);
    }
    flush_now();
    # 3. As the principal: withdraw my CONNECT (no rejoining on my own) and record the
    #    membership, which is how the tenant finds the edge again to remove it.
    act_as(principal);
    try {
        group = jobj(group_id) as StaffGroup;
        Jac.disallow_root(group, UUID(me));  # jac:ignore[E1053]
        group ++> Membership(staff_root_id=me, edge_id=edge_id);
        flush_now();
    } finally {
        restore(me);
    }
    on_commit(lambda { token_consume(INVITE, token); });
    return {"joined": True, "reason": ""};
}

def:priv s2_remove_staff(tenant_id: str, staff_root_id: str) -> dict[str, int] {
    tenant = _owned_tenant(tenant_id);
    caller = node_id(root);
    target = str(UUID(staff_root_id));
    removed = 0;
    act_as(tenant.principal_root_id);
    try {
        group = jobj(tenant.staff_group_id) as StaffGroup;
        for m in [group-->[?:Membership]] {
            if m.staff_root_id == target {
                member_edge: any = jobj(m.edge_id);  # jac:ignore[W1037]
                if member_edge is not None {
                    Jac.destroy([member_edge]);
                }
                Jac.destroy([m]);
                removed += 1;
            }
        }
        flush_now();
    } finally {
        restore(caller);
    }
    return {"removed": removed};
}

def:priv s2_staff_view -> list[dict[str, any]] {
    seen: list[dict[str, any]] = [];
    for g in [root->:MemberOf:->[?:StaffGroup]] {
        for t in [g->:ForTenant:->[?:Tenant]] {
            seen.append(
                {
                    "tenant": t.name,
                    "level": access_level(t),
                    "venues": sorted([v.name for v in [t->:HasVenue:->[?:Venue]]])
                }
            );
        }
    }
    return seen;
}

def:priv s2_rename_venues(new_name: str) -> int {
    count = 0;
    for g in [root->:MemberOf:->[?:StaffGroup]] {
        for t in [g->:ForTenant:->[?:Tenant]] {
            for v in [t->:HasVenue:->[?:Venue]] {
                v.name = new_name;
                count += 1;
            }
        }
    }
    return count;
}

def:priv s2_owner_venues -> list[str] {
    return sorted(
        [
            v.name for t in [root->:OwnsTenant:->[?:Tenant]]
            for v in [t->:HasVenue:->[?:Venue]]
        ]
    );
}

def:priv s2_acl(tenant_id: str) -> dict[str, list[str]] {
    access = _owned_tenant(tenant_id).__jac__.access;
    return {
        "roots": sorted([str(k) for k in access.roots.anchors.keys()]),
        "groups": sorted([str(k) for k in access.groups.anchors.keys()])
    };
}

def:priv s2_probe(node_id_str: str) -> dict[str, any] {
    found: any = jobj(node_id_str);  # jac:ignore[W1037]
    if found is None {
        return {"resolved": False, "can_read": False, "can_write": False};
    }
    return {
        "resolved": True,
        "can_read": Jac.check_read_access(found.__jac__),
        "can_write": Jac.check_write_access(found.__jac__)
    };
}

def:priv s2_try_self_join(group_id: str) -> dict[str, any] {
    # A user who only knows the group's id tries to attach to it.
    found: any = jobj(group_id);  # jac:ignore[W1037]
    if found is None {
        return {"resolved": False};
    }
    root +>:MemberOf:+> (found as StaffGroup);
    return {"resolved": True};
}
