"""Test-only app entry for P2.4: the production signup and tenant endpoints, plus helpers
that add and remove staff directly (the invitation flow arrives in P2.5).
Never imported by main.jac.
"""

import from core.tenancy.signup { create_cinema, my_cinemas }  # jac:ignore[W2037] served here
import from core.tenancy.tenant_api { my_access, rename_cinema }  # jac:ignore[W2037] served here
import from core.tenancy.groups { add_staff }
import from core.tenancy.membership { remove_member }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore, system_root_id }

def _tenant(tenant_id: str) -> Tenant {
    # Test-only: resolve any tenant as the system root (a non-member can't, JI-021).
    caller = node_id(root);
    act_as(system_root_id());
    try {
        return jobj(tenant_id) as Tenant;
    } finally {
        restore(caller);
    }
}

def:priv t_join_as(tenant_id: str, role: str, venue_id: str) -> str {
    # Make the caller staff of `tenant_id` with `role` (at `venue_id`, "" = tenant-wide).
    add_staff(_tenant(tenant_id), role, venue_id);
    return node_id(root);
}

def:priv t_remove(tenant_id: str, staff_root_id: str) -> int {
    return remove_member(_tenant(tenant_id), staff_root_id);
}
