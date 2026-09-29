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
import from core.tenancy.shifts { shift_is_open }

class NotFound(LookupError) {
    def init(self: NotFound) {
        super.init("No such cinema.");
        self.code = "not_found";
    }
}

class NoShift(PermissionError) {
    # A member acting without an open shift (ADR-0006).
    def init(self: NoShift) {
        super.init("Start your shift to continue.");
        self.code = "no_shift";
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

def on_shift(selector: str) -> TenantScope {
    # Resolve the caller's context in `selector` and require an open shift (ADR-0006),
    # without checking an action: for endpoints that filter what they return per venue.
    # Raises NotFound or NoShift.
    scope = resolve_context(selector);
    if not shift_is_open(scope.ctx.tenant_id, scope.ctx.member_root_id) {
        raise NoShift();
    }
    return scope;
}

def scoped(selector: str, action: str, venue_id: str | None = None) -> TenantScope {
    # Resolve the caller's context in `selector`, require an open shift (ADR-0006) and
    # `action` on it. Raises NotFound, NoShift or Forbidden, in that order.
    scope = on_shift(selector);
    require(
        scope.ctx, action, Resource(tenant_id=scope.ctx.tenant_id, venue_id=venue_id)
    );
    return scope;
}
