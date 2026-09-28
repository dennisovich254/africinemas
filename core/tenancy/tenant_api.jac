"""Tenant-scoped endpoints (P2.4). Every one starts from `scoped(selector, action)`:
the caller's context is rebuilt from the graph and the action authorized before
anything is read or changed (ADR-0008). Each is listed in tests/isolation/registry.jac.

Refusals share one shape: {"ok": False, "error": {"code", "message"}}, with code
"not_found" (no such cinema, or not yours) or "forbidden" (yours, but not allowed).
"""

import from core.authz.policy { Forbidden }
import from core.authz.context { NotFound, TenantScope, resolve_context, scoped }
import from core.tenancy.models { NAME_MAX }
import from core.tenancy.responses { NOT_FOUND, FORBIDDEN, refused }

def:priv my_access(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The caller's roles in `tenant` (any member may ask).
    try {
        scope: TenantScope = resolve_context(tenant);
    } except NotFound {
        return NOT_FOUND;
    } except Forbidden {
        return FORBIDDEN;
    }
    return {
        "ok": True,
        "tenant_id": scope.ctx.tenant_id,
        "name": scope.tenant.name,
        "state": scope.tenant.state,
        "assignments": [
            {"role": a.role, "venue_ids": a.venue_ids} for a in scope.ctx.assignments
        ]
    };
}

def:priv rename_cinema(tenant: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        scope = scoped(tenant, "tenant.settings.update");
    } except NotFound {
        return NOT_FOUND;
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
