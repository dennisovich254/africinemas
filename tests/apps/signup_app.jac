"""Test-only app entry: the production signup endpoints plus inspection helpers (P2.2).
Never imported by main.jac.
"""

import from core.tenancy.signup { create_cinema, my_cinemas }  # jac:ignore[W2037] served here
import from core.tenancy.registry { lookup_slug }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    system_root_id,
    count_principals
}

def:pub t_tenants(slug: str) -> int {
    # Tenant nodes with this slug anywhere in the graph (read as the system root).
    caller = node_id(root);
    act_as(system_root_id());
    try {
        return len(
            [
                t for r in allroots()
                for t in [r-->[?:Tenant]]
                if t.slug == slug
            ]
        );
    } finally {
        restore(caller);
    }
}

def:pub t_principals -> int {
    return count_principals();
}

def:pub t_slug_holder(slug: str) -> str | None {
    return lookup_slug(slug);
}
