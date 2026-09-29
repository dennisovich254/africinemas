"""Tenant-scoped endpoints (P2.4). Every one starts from `scoped(selector, action)`:
the caller's context is rebuilt from the graph and the action authorized before
anything is read or changed (ADR-0008). Each is listed in tests/isolation/registry.jac.

Refusals share one shape: {"ok": False, "error": {"code", "message"}}, with code
"not_found" (no such cinema, or not yours) or "forbidden" (yours, but not allowed).
"""

import from core.authz.policy { Forbidden, ROLE_PERMISSIONS }
import from core.authz.context {
    NoShift,
    NotFound,
    TenantScope,
    resolve_context,
    scoped
}
import from core.tenancy.models { NAME_MAX }
import from core.tenancy.responses { NOT_FOUND, FORBIDDEN, NO_SHIFT, refused }
import from datetime { timedelta }
import from core.clock { now }
import from core.tenancy.shifts { open_shift, close_shift, shift_is_open }

def:priv my_access(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The caller's roles in `tenant` (any member may ask).
    try {
        scope: TenantScope = resolve_context(tenant);
    } except NotFound {
        return NOT_FOUND;
    } except Forbidden {
        return FORBIDDEN;
    }
    allowed: set[str] = set();
    for a in scope.ctx.assignments {
        allowed = allowed | ROLE_PERMISSIONS[a.role];
    }
    return {
        "ok": True,
        "tenant_id": scope.ctx.tenant_id,
        "name": scope.tenant.name,
        "state": scope.tenant.state,
        "assignments": [
            {"role": a.role, "venue_ids": a.venue_ids} for a in scope.ctx.assignments
        ],
        # Everything any of the member's roles allows, for role-aware navigation; each
        # action is still authorized on the server, venue scope included.
        "permissions": sorted(allowed),
        "shift_open": shift_is_open(scope.ctx.tenant_id, scope.ctx.member_root_id)
    };
}

def:priv rename_cinema(tenant: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        scope = scoped(tenant, "tenant.settings.update");
    } except NotFound {
        return NOT_FOUND;
    } except NoShift {
        return NO_SHIFT;
    } except Forbidden {
        return FORBIDDEN;
    }
    clean = name.strip();
    if not clean or len(clean) > NAME_MAX {
        return refused(
            "invalid_name", f"Enter a cinema name of 1 to {NAME_MAX} characters."
        );
    }
    scope.tenant.name = clean;
    return {"ok": True, "name": clean};
}

def:priv start_shift(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Opens (or restarts) the caller's shift at `tenant` (ADR-0006). Any member may.
    try {
        scope = resolve_context(tenant);
    } except NotFound {
        return NOT_FOUND;
    }
    ttl = open_shift(scope.ctx.tenant_id, scope.ctx.member_root_id);
    return {"ok": True, "expires_at": (now() + timedelta(seconds=ttl)).isoformat()};
}

def:priv end_shift(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Ends the caller's shift at `tenant` at once; the UI calls it on logout.
    try {
        scope = resolve_context(tenant);
    } except NotFound {
        return NOT_FOUND;
    }
    close_shift(scope.ctx.tenant_id, scope.ctx.member_root_id);
    return {"ok": True};
}
