"""Spike S1 (plan P1.1): a per-tenant service principal owns the tenant subgraph.

Test-only app entry (never imported by main.jac). While running on behalf of the
signed-up owner, `s1_create_tenant` creates an internal user as the tenant's service
principal, switches the request's root to it so the Tenant and Venue it creates are
owned by that principal, then grants the owner WRITE on each node. The spike tests in
s1_tenant_principal_tests.jac check ownership, isolation and revocation on a real
served app. The result is recorded in docs/adr/0003-tenant-ownership-model.md.

Uses runtime APIs the guides don't document (UserManager.create_internal_user,
ExecutionContext.set_user_root); see the ADR for the risk.
"""

import secrets;
import from uuid { UUID }
import from jaclang { JacRuntime as Jac }

node Tenant {
    has name: str,
        principal_root_id: str = "";
}

node Venue {
    has name: str;
}

edge HasVenue {}

edge OwnsTenant {}

def _root_id(node_obj: any) -> str {  # jac:ignore[W1037]
    return str(node_obj.__jac__.id);
}

def _owner_id(node_obj: any) -> str {  # jac:ignore[W1037]
    return str(getattr(node_obj.__jac__, "root"));
}

def _level(node_obj: any) -> str {  # jac:ignore[W1037]
    return str(Jac.check_access_level(node_obj.__jac__).name);
}

def _as_root(root_id: str) {
    # Every node created until the next switch is owned by this root.
    Jac.get_context().set_user_root(root_id);
}

def _new_principal(tenant_name: str) -> str {
    ctx = Jac.get_context();
    users = Jac.get_user_manager(ctx.base_path_dir or "");
    # A random password that is never stored or returned: nobody can log in as it.
    created = users.create_internal_user(
        f"svc-tenant-{secrets.token_hex(8)}", secrets.token_urlsafe(32)
    );
    if "error" in created {
        raise RuntimeError(
            f"could not create the principal for {tenant_name}: {created}"
        );
    }
    root_id = users.ensure_user_root(str(created["user_id"]));
    if not root_id {
        raise RuntimeError(f"the principal for {tenant_name} has no root");
    }
    return str(root_id);
}

def:priv s1_create_tenant(name: str) -> dict[str, str] {
    caller_root_id = _root_id(root);
    principal_root_id = _new_principal(name);
    _as_root(principal_root_id);
    try {
        tenant = Tenant(name=name, principal_root_id=principal_root_id);
        root ++> tenant;
        venue = Venue(name=f"{name} Main Hall");
        tenant +>:HasVenue:+> venue;
        for n in [tenant, venue] {
            Jac.allow_root(n, UUID(caller_root_id), AccessLevel.WRITE);  # jac:ignore[E1053]
        }
    } finally {
        _as_root(caller_root_id);
    }
    root +>:OwnsTenant:+> tenant;
    return {
        "tenant_id": _root_id(tenant),
        "caller_root_id": caller_root_id,
        "principal_root_id": principal_root_id,
        "tenant_owner_id": _owner_id(tenant),
        "venue_owner_id": _owner_id(venue)
    };
}

def:priv s1_my_tenants -> list[dict[str, any]] {
    found: list[dict[str, any]] = [];
    for tenant in [root->:OwnsTenant:->[?:Tenant]] {
        found.append(
            {
                "name": tenant.name,
                "level": _level(tenant),
                "venues": [v.name for v in [tenant->:HasVenue:->[?:Venue]]]
            }
        );
    }
    return found;
}

def:priv s1_probe(tenant_id: str) -> dict[str, any] {
    # What a caller who was given only the id can do with it.
    found = jobj(tenant_id);
    if found is None {
        return {"resolved": False, "can_read": False, "can_write": False};
    }
    tenant = found as Tenant;
    return {
        "resolved": True,
        "can_read": Jac.check_read_access(tenant.__jac__),
        "can_write": Jac.check_write_access(tenant.__jac__)
    };
}

def:priv s1_try_tamper(tenant_id: str) -> dict[str, any] {
    found = jobj(tenant_id);
    if found is None {
        return {"resolved": False};
    }
    tenant = found as Tenant;
    tenant.name = "tampered";
    root +>:OwnsTenant:+> tenant;
    return {"resolved": True};
}

def:priv s1_step_down(tenant_id: str) -> dict[str, any] {
    # Offboarding: the principal (the owner of the nodes) revokes the human's grant.
    caller_root_id = _root_id(root);
    tenant = jobj(tenant_id) as Tenant;
    _as_root(tenant.principal_root_id);
    try {
        for n in [tenant] + [tenant->:HasVenue:->[?:Venue]] {
            Jac.disallow_root(n, UUID(caller_root_id));  # jac:ignore[E1053]
        }
        # Flush now, as the principal. At request end the flush re-checks write access
        # under the caller's root, and the caller just lost it, so the revocation would
        # be dropped silently (jaclang Session._flush_locked).
        Jac.commit();
    } finally {
        _as_root(caller_root_id);
    }
    return {"revoked": True};
}

def:priv s1_principal_view(principal_root_id: str) -> list[str] {
    # What hangs off the principal's own root: where the tenant subgraph persists.
    # A platform operation (it needs the principal's id, not the owner's grant).
    caller_root_id = _root_id(root);
    _as_root(principal_root_id);
    try {
        return [t.name for t in [root-->[?:Tenant]]];
    } finally {
        _as_root(caller_root_id);
    }
}
