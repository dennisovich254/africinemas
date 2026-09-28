"""A tenant's access group, and adding staff to it (ADR-0004, ADR-0008 revised in P2.5).

Each tenant has one access group: tenant nodes grant it WRITE, one entry per node,
however many staff there are. Roles are not groups: they live on each member's
Membership record (core/tenancy/membership.jac), so they can be changed by others.
"""

import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from core.authz.policy { role_key }
import from core.tenancy.models {
    Tenant,
    StaffGroup,
    Membership,
    ForTenant,
    ACCESS_GROUP
}
import from core.tenancy.membership { link_to_group, new_record, records_of }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }

def access_group(tenant: Tenant) -> StaffGroup {
    # Finds or creates `tenant`'s access group. Created once, at signup.
    caller = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        for g in [root-->[?:StaffGroup]] {
            if g.tenant_id == node_id(tenant) {
                return g;
            }
        }
        group = StaffGroup(tenant_id=node_id(tenant), role=ACCESS_GROUP);
        root ++> group;
        group +>:ForTenant:+> tenant;
        group_id = UUID(node_id(group));
        # Members traverse root -> group -> tenant, so the group grants READ on itself.
        Jac.allow_group(group, group_id, AccessLevel.READ);  # jac:ignore[E1053]
        Jac.allow_group(tenant, group_id, AccessLevel.WRITE);  # jac:ignore[E1053]
        flush_now();
        return group;
    } finally {
        restore(caller);
    }
}

def add_staff(tenant: Tenant, role: str, venue_id: str) -> Membership {
    # Makes the CALLER staff of `tenant` with `role` (at `venue_id`, "" = tenant-wide),
    # adding the role if they are already staff. Call in the member's own request.
    key = role_key(role, venue_id);
    me = node_id(root);
    group = access_group(tenant);
    act_as(tenant.principal_root_id);
    try {
        existing = [
            m
            for m in records_of(tenant)
            if m.staff_root_id == me
        ];
    } finally {
        restore(me);
    }
    if existing {
        record = existing[0];
        act_as(tenant.principal_root_id);
        try {
            if key not in record.roles {
                record.roles = record.roles + [key];
            }
            flush_now();
        } finally {
            restore(me);
        }
        return record;
    }
    edge_id = link_to_group(tenant.principal_root_id, group);
    act_as(tenant.principal_root_id);
    try {
        record = new_record(group, me, edge_id, [key]);
        flush_now();
    } finally {
        restore(me);
    }
    return record;
}
