"""Tenant-scoped endpoints (P2.4). Every one starts from `scoped(selector, action)`:
the caller's context is rebuilt from the graph and the action authorized before
anything is read or changed (ADR-0008). Each is listed in tests/isolation/registry.jac.

Refusals share one shape: {"ok": False, "error": {"code", "message"}}, with code
"not_found" (no such cinema, or not yours) or "forbidden" (yours, but not allowed).
"""

import from core.tenancy.reserved_words { name_claims, NAME_MESSAGE }
import from core.authz.policy { Forbidden, ROLE_PERMISSIONS }
import from core.authz.context {
    NoShift,
    NotFound,
    TenantScope,
    resolve_context,
    scoped
}
import from core.tenancy.models {
    NAME_MAX,
    DOORS_OPEN_MAX,
    SHIFT_HOURS_MAX,
    CASH_COUNT_MAX_LOW,
    CASH_COUNT_MAX_HIGH
}
import from core.tenancy.responses { NOT_FOUND, FORBIDDEN, NO_SHIFT, refused }
import from datetime { timedelta }
import from core.clock { now }
import from core.tenancy.shifts { open_shift, close_shift, shift_is_open }
import from core.audit.log { audited }
import from core.tenancy.open_cinema { preview_pass, is_preview }

def:protect storefront_preview(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A pass for the cinema's own team to see its storefront before it goes live
    # (P14.1); "" once it's live, when everyone sees it. Any member may ask.
    try {
        scope: TenantScope = resolve_context(tenant);
    } except NotFound {
        return NOT_FOUND;
    } except Forbidden {
        return FORBIDDEN;
    }
    cinema = scope.tenant;
    return {
        "ok": True,
        "state": cinema.state,
        "token": preview_pass(cinema) if is_preview(cinema) else ""
    };
}

def:protect my_access(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
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
        # When AfriCinemas verified it (P14.5), for the back office's badge; "" if not.
        "verified_at": scope.tenant.verified_at,
        "assignments": [
            {"role": a.role, "venue_ids": a.venue_ids} for a in scope.ctx.assignments
        ],
        # Everything any of the member's roles allows, for role-aware navigation; each
        # action is still authorized on the server, venue scope included.
        "permissions": sorted(allowed),
        "shift_open": shift_is_open(scope.ctx.tenant_id, scope.ctx.member_root_id)
    };
}

def _do_rename_cinema(tenant: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
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
    if name_claims(clean) {
        return refused("invalid_name", NAME_MESSAGE);
    }
    scope.tenant.name = clean;
    return {"ok": True, "name": clean};
}

def _do_set_doors_open(tenant: str, minutes: int) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        scope = scoped(tenant, "tenant.settings.update");
    } except NotFound {
        return NOT_FOUND;
    } except NoShift {
        return NO_SHIFT;
    } except Forbidden {
        return FORBIDDEN;
    }
    if isinstance(minutes, bool)
        or not isinstance(minutes, int)
        or not 0 <= minutes <= DOORS_OPEN_MAX {
        return refused(
            "invalid_minutes",
            f"Enter a whole number of minutes from 0 to {DOORS_OPEN_MAX}."
        );
    }
    scope.tenant.doors_open_minutes = minutes;
    return {"ok": True, "doors_open_minutes": minutes};
}

def _rules_of(cinema: any) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "shift_hours": cinema.shift_hours,
        "cash_count_max_cents": cinema.cash_count_max_cents
    };
}

def _do_box_office_rules(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Any member may read them: the box office checks its counts against the limit.
    try {
        scope = resolve_context(tenant);
    } except NotFound {
        return NOT_FOUND;
    }
    return _rules_of(scope.tenant);
}

def _do_set_box_office_rules(
    tenant: str, shift_hours: int, cash_count_max_cents: int
) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        scope = scoped(tenant, "tenant.settings.update");
    } except NotFound {
        return NOT_FOUND;
    } except NoShift {
        return NO_SHIFT;
    } except Forbidden {
        return FORBIDDEN;
    }
    if isinstance(shift_hours, bool)
        or not isinstance(shift_hours, int)
        or not 1 <= shift_hours <= SHIFT_HOURS_MAX {
        return refused(
            "invalid_hours",
            f"Enter a whole number of hours from 1 to {SHIFT_HOURS_MAX}."
        );
    }
    if isinstance(cash_count_max_cents, bool)
        or not isinstance(cash_count_max_cents, int)
        or not CASH_COUNT_MAX_LOW <= cash_count_max_cents <= CASH_COUNT_MAX_HIGH {
        return refused(
            "invalid_limit",
            f"Enter an amount from KES {CASH_COUNT_MAX_LOW // 100:,} to KES {CASH_COUNT_MAX_HIGH
                // 100:,}."
        );
    }
    scope.tenant.shift_hours = shift_hours;
    scope.tenant.cash_count_max_cents = cash_count_max_cents;
    return _rules_of(scope.tenant);
}

def _do_start_shift(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Opens (or restarts) the caller's shift at `tenant` (ADR-0006). Any member may.
    try {
        scope = resolve_context(tenant);
    } except NotFound {
        return NOT_FOUND;
    }
    ttl = open_shift(
        scope.ctx.tenant_id, scope.ctx.member_root_id, scope.tenant.shift_hours
    );
    return {"ok": True, "expires_at": (now() + timedelta(seconds=ttl)).isoformat()};
}

def _do_end_shift(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Ends the caller's shift at `tenant` at once; the UI calls it on logout.
    try {
        scope = resolve_context(tenant);
    } except NotFound {
        return NOT_FOUND;
    }
    close_shift(scope.ctx.tenant_id, scope.ctx.member_root_id);
    return {"ok": True};
}

def:protect rename_cinema(tenant: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "cinema.renamed",
        "cinema",
        tenant,
        lambda -> any { return _do_rename_cinema(tenant, name); }  # jac:ignore[W1037]
    );
}

def:protect set_doors_open(tenant: str, minutes: int) -> dict[str, any] {  # jac:ignore[W1037]
    # How many minutes before a showtime its tickets can be scanned (improvements #10).
    return audited(
        tenant,
        "cinema.doors_changed",
        "cinema",
        tenant,
        lambda -> any { return _do_set_doors_open(tenant, minutes); }  # jac:ignore[W1037]
    );
}

def:protect box_office_rules(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _do_box_office_rules(tenant);
}

def:protect set_box_office_rules(
    tenant: str, shift_hours: int, cash_count_max_cents: int
) -> dict[str, any] {  # jac:ignore[W1037]
    # How long a shift lasts and the most one cash count may be (P15.6b). A shift
    # already open keeps its length.
    return audited(
        tenant,
        "cinema.box_office_rules_changed",
        "cinema",
        tenant,
        lambda -> any { return _do_set_box_office_rules(  # jac:ignore[W1037]
            tenant, shift_hours, cash_count_max_cents
        ); }
    );
}

def:protect start_shift(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "shift.started",
        "shift",
        "",
        lambda -> any { return _do_start_shift(tenant); }  # jac:ignore[W1037]
    );
}

def:protect end_shift(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "shift.ended",
        "shift",
        "",
        lambda -> any { return _do_end_shift(tenant); }  # jac:ignore[W1037]
    );
}
