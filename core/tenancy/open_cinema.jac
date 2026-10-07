"""Finding the cinema behind a storefront slug, for public and customer endpoints.

The caller isn't staff, so can't read the Tenant node itself: it's read as the system
root. A cinema is open to the public from signup until it starts closing (ADR-0009), so
owners can try their storefront before going live.
"""

import from core.tenancy.models { Tenant }
import from core.tenancy.registry { lookup_slug }
import from core.tenancy.principal { node_id, act_as, restore, system_root_id }

glob OPEN_STATES: list[str] = ["configuring", "ready_for_go_live", "active"];

def open_cinema(selector: str) -> Tenant | None {
    # The open cinema with this slug, or None if unknown, malformed or not open.
    tenant_id = lookup_slug(selector) if selector else None;
    if tenant_id is None {
        return None;
    }
    me = node_id(root);
    act_as(system_root_id());
    try {
        found: any = jobj(tenant_id);  # jac:ignore[W1037]
    } finally {
        restore(me);
    }
    if not isinstance(found, Tenant) or found.state not in OPEN_STATES {
        return None;
    }
    return found as Tenant;
}

def tenant_by_id(tenant_id: str) -> Tenant | None {
    # The cinema with this id whatever its state, for system jobs (payments, mail).
    me = node_id(root);
    act_as(system_root_id());
    try {
        found: any = jobj(tenant_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as Tenant if isinstance(found, Tenant) else None;
}
