"""Tenant context, resolved on the server on every call (P2.4, ADR-0008).

The client only names a cinema: its slug, a selector and never authority (ADR-0006).
`resolve_context` looks the slug up and then reads the CALLER's memberships from the
graph (their MemberOf edges to the tenant's role groups), so a role granted, changed or
removed a moment ago applies to this very call, whatever the caller's token says.

An unknown slug, a malformed one and a cinema the caller doesn't belong to all raise
the same NotFound, so a selector can't be used to probe which cinemas exist.
"""

import from core.authz.policy {
    ROLE_PERMISSIONS,
    AuthContext,
    RoleAssignment,
    Resource,
    require
}
import from core.tenancy.models { Tenant, StaffGroup, MemberOf, ForTenant }
import from core.tenancy.registry { lookup_slug }
import from core.tenancy.principal { node_id }

class NotFound(LookupError) {
    def init(self: NotFound) {
        super.init("No such cinema.");
        self.code = "not_found";
    }
}

obj TenantScope {
    has tenant: Tenant,
        ctx: AuthContext;
}

def resolve_context(selector: str) -> TenantScope {
    tenant_id = lookup_slug(selector) if selector else None;
    if tenant_id is None {
        raise NotFound();
    }
    tenant: Tenant | None = None;
    venues_by_role: dict[str, list[str] | None] = {};
    for g in [root->:MemberOf:->[?:StaffGroup]] {
        if g.tenant_id != tenant_id or g.role not in ROLE_PERMISSIONS {
            continue;
        }
        if tenant is None {
            linked = [g->:ForTenant:->[?:Tenant]];
            tenant = linked[0] if linked else None;
        }
        if not g.venue_id {
            venues_by_role[g.role] = None;
        } elif g.role not in venues_by_role {
            venues_by_role[g.role] = [g.venue_id];
        } elif venues_by_role[g.role] is not None {
            venues_by_role[g.role] = sorted(venues_by_role[g.role] + [g.venue_id]);
        }
    }
    if tenant is None or not venues_by_role {
        raise NotFound();
    }
    return TenantScope(
        tenant=tenant,
        ctx=AuthContext(
            tenant_id=tenant_id,
            member_root_id=node_id(root),
            assignments=[
                RoleAssignment(role=role, venue_ids=venues)
                for (role, venues) in sorted(venues_by_role.items())
            ]
        )
    );
}

def scoped(selector: str, action: str, venue_id: str | None = None) -> TenantScope {
    # Resolve the caller's context in `selector` and require `action` on it
    # (raises NotFound or Forbidden).
    scope = resolve_context(selector);
    require(
        scope.ctx, action, Resource(tenant_id=scope.ctx.tenant_id, venue_id=venue_id)
    );
    return scope;
}
