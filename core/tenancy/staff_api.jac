"""Staff invitations and lifecycle (P2.5). Tenant-scoped endpoints start from
`scoped(slug, action)` (ADR-0008) and are listed in tests/isolation/registry.jac.

- invite_staff: needs employees.invite, and the inviter must already hold every
  permission of the role (no escalation). Returns a one-time token (Jac's token store)
  that expires after AFRICINEMAS_INVITE_TTL_S (default 72 h).
- A role limited to a venue must name one of this cinema's venues (P3.1): invite_staff
  and change_staff_roles refuse any other id with unknown_venue, and an invitation whose
  venue was deleted since it was sent can't be accepted.
- accept_invite: the invitee's own request (their membership edge must come from their
  root, ADR-0004). Single use is decided by an atomic claim on the invite (ADR-0007);
  the token is only peeked in the body and consumed in on_commit (JI-022).
- list_staff / change_staff_roles / set_staff_status / remove_staff: need
  employees.read, employees.assign_roles or employees.disable; the actor must be able to
  grant every role the member holds (so an admin can't touch an owner), and nobody can
  change their own membership (no self-promotion, no locking yourself out).
"""

import os;
import from operator { itemgetter }
import from datetime { timedelta }
import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from jaclang.server.identity.app_tokens {
    token_create,
    token_peek,
    token_consume
}
import from core.clock { now }
import from core.claims { claim, make_permanent, release }
import from core.authz.policy { Forbidden, role_key, can_grant }
import from core.authz.context { NoShift, NotFound, TenantScope, scoped }
import from core.tenancy.models { Tenant, Invite, Membership }
import from core.tenancy.groups { add_staff }
import from core.tenancy.membership { records_of, remove_member }
import from core.tenancy.responses { NOT_FOUND, FORBIDDEN, NO_SHIFT, refused }
import from core.catalog.venues { find_venue }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    system_root_id
}

glob INVITE_PURPOSE: str = "staff-invite",
     INVITE_CLAIMS: str = "staff-invite",
     TTL_ENV: str = "AFRICINEMAS_INVITE_TTL_S",
     TTL_DEFAULT_S: int = 72 * 3600,
     CLAIM_HOLD_S: int = 300,
     STATUSES: list[str] = ["active", "disabled"],
     INVALID_INVITE: dict[str, bool | dict[str, str]] = {
         "ok": False,
         "error": {
             "code": "invalid_invite",
             "message": "This invitation is no longer valid. Ask for a new one."
         }
     },
     UNKNOWN_VENUE: dict[str, bool | dict[str, str]] = {
         "ok": False,
         "error": {
             "code": "unknown_venue",
             "message": "That venue isn't one of this cinema's venues."
         }
     },
     SELF_CHANGE: dict[str, bool | dict[str, str]] = {
         "ok": False,
         "error": {
             "code": "self_change",
             "message": "Ask another owner or admin to change your own access."
         }
     };

def _ttl_s -> int {
    return int(os.environ.get(TTL_ENV, str(TTL_DEFAULT_S)));
}

def _as_principal_record(scope: TenantScope, member_id: str) -> Membership | None {
    # The member's record, read as the tenant's principal. Call inside act_as.
    try {
        wanted = str(UUID(member_id));
    } except ValueError {
        return None;
    }
    for m in records_of(scope.tenant) {
        if m.staff_root_id == wanted {
            return m;
        }
    }
    return None;
}

def _may_manage(scope: TenantScope, record: Membership) -> bool {
    # The actor must be able to grant every role the member holds.
    return all(can_grant(scope.ctx, key.partition("@")[0]) for key in record.roles);
}

def:priv invite_staff(tenant: str, role: str, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        scope = scoped(tenant, "employees.invite");
    } except NotFound {
        return NOT_FOUND;
    } except NoShift {
        return NO_SHIFT;
    } except Forbidden {
        return FORBIDDEN;
    }
    try {
        key = role_key(role, venue_id);
    } except ValueError {
        return refused("invalid_role", f"'{role}' can't be given here.");
    }
    if not can_grant(scope.ctx, role) {
        return FORBIDDEN;
    }
    if venue_id and find_venue(scope.tenant, venue_id) is None {
        return UNKNOWN_VENUE;
    }
    me = node_id(root);
    created = now();
    act_as(scope.tenant.principal_root_id);
    try {
        invite = Invite(role_key=key, invited_by=me, created_at=created.isoformat());
        scope.tenant ++> invite;
        flush_now();
    } finally {
        restore(me);
    }
    ttl = _ttl_s();
    # A replay of this request can mint an extra token; it names an Invite that was
    # rolled back, so it can never be accepted, and it expires on its own.
    token = token_create(
        INVITE_PURPOSE,
        subject=node_id(invite),
        ttl_seconds=ttl,
        payload={"tenant_id": scope.ctx.tenant_id, "invite_id": node_id(invite)}
    );
    return {
        "ok": True,
        "token": token,
        "invite_id": node_id(invite),
        "expires_at": (created + timedelta(seconds=ttl)).isoformat()
    };
}

def:priv accept_invite(token: str) -> dict[str, any] {  # jac:ignore[W1037]
    peeked = token_peek(INVITE_PURPOSE, token) if token else None;
    if peeked is None {
        return INVALID_INVITE;
    }
    tenant_id = str(peeked["payload"].get("tenant_id", ""));
    invite_id = str(peeked["payload"].get("invite_id", ""));
    me = node_id(root);
    act_as(system_root_id());
    try {
        found_tenant: any = jobj(tenant_id);  # jac:ignore[W1037]
        found_invite: any = jobj(invite_id);  # jac:ignore[W1037]
    } finally {
        restore(me);
    }
    if found_tenant is None
        or found_invite is None
        or (found_invite as Invite).used_by {
        return INVALID_INVITE;
    }
    tenant = found_tenant as Tenant;
    invite = found_invite as Invite;
    # A venue named by the invitation may have been deleted since it was sent.
    invited_venue = invite.role_key.partition("@")[2];
    if invited_venue and find_venue(tenant, invited_venue) is None {
        return INVALID_INVITE;
    }
    # Exactly one accept wins, even when several arrive at once (ADR-0007).
    if claim(INVITE_CLAIMS, invite_id, me, CLAIM_HOLD_S) != me {
        return INVALID_INVITE;
    }
    try {
        (role, _, venue) = invite.role_key.partition("@");
        record = add_staff(tenant, role, venue);
        act_as(tenant.principal_root_id);
        try {
            invite.used_by = me;
            flush_now();
        } finally {
            restore(me);
        }
    } except Exception as e {
        restore(me);
        release(INVITE_CLAIMS, invite_id, me);
        raise e;
    }
    on_commit(
        lambda {
            token_consume(INVITE_PURPOSE, token);
            make_permanent(INVITE_CLAIMS, invite_id, me);
        }
    );
    return {"ok": True, "slug": tenant.slug, "member_id": me, "roles": record.roles};
}

def:priv list_staff(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        scope = scoped(tenant, "employees.read");
    } except NotFound {
        return NOT_FOUND;
    } except NoShift {
        return NO_SHIFT;
    } except Forbidden {
        return FORBIDDEN;
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        staff = [
            {
                "member_id": m.staff_root_id,
                "roles": m.roles,
                "status": m.status,
                "joined_at": m.joined_at
            } for m in records_of(scope.tenant)
        ];
    } finally {
        restore(me);
    }
    return {"ok": True, "staff": sorted(staff, key=itemgetter("joined_at"))};
}

def _manage(
    tenant: str,
    member_id: str,
    action: str,
    change: any  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # Shared frame for changing someone else's membership; `change(scope, record)`
    # returns a refusal dict or None after applying the change (as the principal).
    try {
        scope = scoped(tenant, action);
    } except NotFound {
        return NOT_FOUND;
    } except NoShift {
        return NO_SHIFT;
    } except Forbidden {
        return FORBIDDEN;
    }
    me = node_id(root);
    try {
        target = str(UUID(member_id));
    } except ValueError {
        return refused("not_member", "That person isn't staff here.");
    }
    if target == me {
        return SELF_CHANGE;
    }
    act_as(scope.tenant.principal_root_id);
    try {
        record = _as_principal_record(scope, target);
        if record is None {
            return refused("not_member", "That person isn't staff here.");
        }
        if not _may_manage(scope, record) {
            return FORBIDDEN;
        }
        refusal = change(scope, record);
        if refusal is not None {
            return refusal;
        }
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True};
}

def:priv change_staff_roles(
    tenant: str, member_id: str, roles: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    def apply(scope: TenantScope, record: Membership) -> dict[str, any] | None {  # jac:ignore[W1037]
        keys: list[str] = [];
        for key in roles {
            (role, _, venue) = key.partition("@");
            try {
                keys.append(role_key(role, venue));
            } except ValueError {
                return refused("invalid_role", f"'{key}' can't be given here.");
            }
            if not can_grant(scope.ctx, role) {
                return FORBIDDEN;
            }
            if venue and find_venue(scope.tenant, venue) is None {
                return UNKNOWN_VENUE;
            }
        }
        if not keys {
            return refused(
                "invalid_role", "Give at least one role, or remove the person."
            );
        }
        record.roles = sorted(set(keys));
        return None;
    }
    return _manage(tenant, member_id, "employees.assign_roles", apply);
}

def:priv set_staff_status(tenant: str, member_id: str, status: str) -> dict[str, any] {  # jac:ignore[W1037]
    def apply(_scope: TenantScope, record: Membership) -> dict[str, any] | None {  # jac:ignore[W1037]
        if status not in STATUSES {
            return refused("invalid_status", "Status must be active or disabled.");
        }
        record.status = status;
        return None;
    }
    return _manage(tenant, member_id, "employees.disable", apply);
}

def:priv remove_staff(tenant: str, member_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    def apply(scope: TenantScope, record: Membership) -> dict[str, any] | None {  # jac:ignore[W1037]
        remove_member(scope.tenant, record.staff_root_id);
        return None;
    }
    return _manage(tenant, member_id, "employees.disable", apply);
}
