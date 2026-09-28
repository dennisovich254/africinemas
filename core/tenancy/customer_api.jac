"""Customer accounts per cinema (P2.6). Storefront endpoints: anyone signed in may use
them at any cinema, and they only ever return the caller's own customer data. Listed in
tests/isolation/registry.jac with scope "customer".

A person has one platform login and a separate CustomerProfile at each cinema they use.
The profile belongs to the cinema (its principal, ADR-0003), is readable by that
customer only, and is attached to the cinema's access group so staff reach it
(ADR-0004). One profile per (cinema, person) is an atomic claim whose value is the
profile's id (ADR-0007): the claim is both the uniqueness guard and the lookup.
"""

import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from core.clock { now }
import from core.claims { claim, holder, make_permanent, release }
import from core.tenancy.models { Tenant, CustomerProfile, NAME_MAX }
import from core.tenancy.registry { lookup_slug }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.responses { NOT_FOUND, refused }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id,
    assign_id,
    system_root_id
}

glob PROFILE_CLAIMS: str = "customer-profile",
     CLAIM_HOLD_S: int = 300,
     # A storefront takes customers from signup until the cinema starts closing.
     OPEN_STATES: list[str] = ["configuring", "ready_for_go_live", "active"];

def _storefront(selector: str) -> Tenant | None {
    # The cinema behind a storefront slug, read as the system root (a customer isn't
    # staff, so can't read the Tenant node itself). None if unknown or not open.
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
    if found is None or (found as Tenant).state not in OPEN_STATES {
        return None;
    }
    return found as Tenant;
}

def _profile_key(tenant: Tenant) -> str {
    return f"{node_id(tenant)}:{node_id(root)}";
}

def _view(tenant: Tenant, profile: CustomerProfile, created: bool) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "created": created,
        "slug": tenant.slug,
        "profile_id": node_id(profile),
        "display_name": profile.display_name
    };
}

def _read_own(profile_id: str) -> CustomerProfile | None {
    # The caller's own profile (they hold a READ grant on it).
    found: any = jobj(profile_id);  # jac:ignore[W1037]
    return found as CustomerProfile if found is not None else None;
}

def:priv join_as_customer(tenant: str, display_name: str) -> dict[str, any] {  # jac:ignore[W1037]
    shop = _storefront(tenant);
    if shop is None {
        return NOT_FOUND;
    }
    name = display_name.strip();
    if not name or len(name) > NAME_MAX {
        return refused("invalid_name", f"Enter a name of 1 to {NAME_MAX} characters.");
    }
    key = _profile_key(shop);
    existing_id = holder(PROFILE_CLAIMS, key);
    if existing_id is not None {
        existing = _read_own(existing_id);
        if existing is not None {
            return _view(shop, existing, False);
        }
    }
    me = node_id(root);
    profile_id = fresh_node_id();
    winner = claim(PROFILE_CLAIMS, key, profile_id, CLAIM_HOLD_S);
    if winner != profile_id {
        # A concurrent join by the same person won; hand back that profile.
        other = _read_own(winner);
        return _view(shop, other, False) if other is not None else NOT_FOUND;
    }
    try {
        act_as(shop.principal_root_id);
        try {
            profile = CustomerProfile(
                tenant_id=node_id(shop),
                customer_root_id=me,
                display_name=name,
                created_at=now().isoformat()
            );
            assign_id(profile, profile_id);
            shop ++> profile;
            Jac.allow_root(profile, UUID(me), AccessLevel.READ);  # jac:ignore[E1053]
            attach_to_tenant(profile, shop);
            flush_now();
        } finally {
            restore(me);
        }
    } except Exception as e {
        release(PROFILE_CLAIMS, key, profile_id);
        raise e;
    }
    on_commit(lambda { make_permanent(PROFILE_CLAIMS, key, profile_id); });
    return _view(shop, profile, True);
}

def:priv my_customer_profile(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    shop = _storefront(tenant);
    if shop is None {
        return NOT_FOUND;
    }
    profile_id = holder(PROFILE_CLAIMS, _profile_key(shop));
    profile = _read_own(profile_id) if profile_id is not None else None;
    if profile is None {
        return NOT_FOUND;
    }
    return _view(shop, profile, False);
}
