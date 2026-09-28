"""A tenant's staff groups: one access group plus role groups (ADR-0004, ADR-0008).

- The ACCESS group holds the graph grants: tenant nodes grant it WRITE, one entry per
  node however many staff there are. Every staff member joins it once.
- ROLE groups (e.g. usher, or usher at venue v-1) hold no node grants; membership in
  them is what `resolve_context` turns into role assignments.
Both kinds hang off the tenant's principal root and link to the Tenant (ForTenant), so
members can traverse root -> group -> tenant.
"""

import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from core.authz.policy { RoleAssignment }
import from core.tenancy.models {
    Tenant,
    StaffGroup,
    MemberOf,
    ForTenant,
    ACCESS_GROUP
}
import from core.tenancy.membership { join_group }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }

def ensure_group(tenant: Tenant, role: str, venue_id: str) -> StaffGroup {
    # Finds or creates the tenant's group for `role` at `venue_id` ("" = tenant-wide).
    # Group creation is an admin action (signup, invitations), not a hot path; a rare
    # duplicate from a race still grants the same thing (JI-024).
    if role != ACCESS_GROUP {
        RoleAssignment(role=role, venue_ids=[venue_id] if venue_id else None);
    }
    caller = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        for g in [root-->[?:StaffGroup]] {
            if g.tenant_id == node_id(tenant)
                and g.role == role
                and g.venue_id == venue_id {
                return g;
            }
        }
        group = StaffGroup(tenant_id=node_id(tenant), role=role, venue_id=venue_id);
        root ++> group;
        group +>:ForTenant:+> tenant;
        group_id = UUID(node_id(group));
        # Members traverse through their groups, so each grants READ on itself.
        Jac.allow_group(group, group_id, AccessLevel.READ);  # jac:ignore[E1053]
        if role == ACCESS_GROUP {
            Jac.allow_group(tenant, group_id, AccessLevel.WRITE);  # jac:ignore[E1053]
        }
        flush_now();
        return group;
    } finally {
        restore(caller);
    }
}

def _is_member(group: StaffGroup) -> bool {
    return any(
        node_id(g) == node_id(group) for g in [root->:MemberOf:->[?:StaffGroup]]
    );
}

def add_staff(tenant: Tenant, role: str, venue_id: str) {
    # Makes the CALLER staff of `tenant` with `role`: joins the access group (once) and
    # the role group. Call in the joining member's own request (ADR-0004).
    for group in [
        ensure_group(tenant, ACCESS_GROUP, ""),
        ensure_group(tenant, role, venue_id)
    ] {
        if not _is_member(group) {
            join_group(tenant.principal_root_id, group);
        }
    }
}
