"""Tenant context, resolved on the server on every call (P2.4, ADR-0008).

The client only names a cinema: its slug, a selector and never authority (ADR-0006).
`resolve_context` looks the slug up and then reads the CALLER's membership from the
graph (their MemberOf edge to the tenant's access group, and their Membership record
under it, which only they can read), so a role granted, changed or removed, or a member
disabled, a moment ago applies to this very call, whatever the caller's token says.

An unknown slug, a malformed one and a cinema the caller doesn't belong to all raise
the same NotFound, so a selector can't be used to probe which cinemas exist.
"""

import from core.authz.policy { AuthContext, Resource, require, assignments_from_keys }
import from core.tenancy.models { Tenant, StaffGroup, Membership, MemberOf, ForTenant }
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
    me = node_id(root);
    tenant: Tenant | None = None;
    keys: list[str] = [];
    for g in [root->:MemberOf:->[?:StaffGroup]] {
        if g.tenant_id != tenant_id {
            continue;
        }
        for m in [g-->[?:Membership]] {
            if m.staff_root_id == me and m.status == "active" {
                keys = keys + m.roles;
            }
        }
        linked = [g->:ForTenant:->[?:Tenant]];
        tenant = linked[0] if linked else tenant;
    }
    if tenant is None or not keys {
        raise NotFound();
    }
    return TenantScope(
        tenant=tenant,
        ctx=AuthContext(
            tenant_id=tenant_id,
            member_root_id=me,
            assignments=assignments_from_keys(keys)
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
