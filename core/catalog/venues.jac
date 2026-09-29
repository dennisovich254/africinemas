"""Looking up a cinema's venues, for any module that takes a venue id (P3.1).

Venue ids arrive from clients (venue endpoints, staff invitations and role changes), so
every use checks the venue exists and belongs to the cinema before relying on it.
"""

import from core.tenancy.models { Tenant, Membership }
import from core.tenancy.membership { records_of }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.models { Venue }

def find_venue(tenant: Tenant, venue_id: str) -> Venue | None {
    # `tenant`'s venue with id `venue_id`, or None if there's no such venue at this
    # cinema (including another cinema's venue and ids that aren't valid).
    if not venue_id {
        return None;
    }
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found: any = jobj(venue_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    if not isinstance(found, Venue) or found.tenant_id != node_id(tenant) {
        return None;
    }
    return found as Venue;
}

def staff_at(tenant: Tenant, venue_id: str) -> list[Membership] {
    # Members of `tenant`, active or disabled, holding any role limited to `venue_id`.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        records = records_of(tenant);
    } finally {
        restore(me);
    }
    return [
        m
        for m in records
        if any(key.partition("@")[2] == venue_id for key in m.roles)
    ];
}
