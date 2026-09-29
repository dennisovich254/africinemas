"""Venues and auditoriums (P3.1). Tenant-scoped endpoints, listed in
tests/isolation/registry.jac.

- Reading needs venues.read. list_venues returns only the venues the caller may read
  there, so venue-scoped staff (an usher at one venue) see just their venue.
- Changing needs venues.configure at the venue; creating or deleting a whole venue
  needs it cinema-wide.
- A venue or auditorium id from another cinema answers not_found.
- Names are unique per cinema (venues) and per venue (auditoriums), ignoring case and
  extra spaces. Each name is an atomic claim whose value is the node's id (ADR-0007): a
  graph check-then-create would let concurrent requests all pass (JI-024). Claims are
  provisional until the request commits; renamed-away and deleted names are released
  on commit.
- A venue that still has auditoriums can't be deleted.
"""

import from jaclang { JacRuntime as Jac }
import from core.clock { now }
import from core.claims { claim, make_permanent, release }
import from core.authz.policy { Forbidden, ROLE_PERMISSIONS, Resource, authorize }
import from core.authz.context { NoShift, NotFound, TenantScope, on_shift, scoped }
import from core.tenancy.models { NAME_MAX }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.responses { NOT_FOUND, FORBIDDEN, NO_SHIFT, refused }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id,
    assign_id
}
import from core.catalog.models { Venue, Auditorium, ADDRESS_MAX }

glob VENUE_NAMES: str = "venue-name",
     AUDITORIUM_NAMES: str = "auditorium-name",
     CLAIM_HOLD_S: int = 300,
     READ: str = "venues.read",
     CONFIGURE: str = "venues.configure";

class Refused(ValueError) {
    # A request refused with a code and message the UI can show.
    def init(self: Refused, code: str, message: str) {
        super.init(message);
        self.code = code;
        self.message = message;
    }
}

def _answer(work: any) -> dict[str, any] {  # jac:ignore[W1037]
    # Runs an endpoint's work, turning its refusals into the shared response shapes.
    try {
        return work();
    } except NotFound {
        return NOT_FOUND;
    } except NoShift {
        return NO_SHIFT;
    } except Forbidden {
        return FORBIDDEN;
    } except Refused as e {
        return refused(e.code, e.message);
    }
}

def _clean(text: str) -> str {
    # Trimmed, with runs of spaces collapsed: "  Screen   1 " -> "Screen 1".
    return " ".join(text.split());
}

def _name(text: str) -> str {
    name = _clean(text);
    if not name or len(name) > NAME_MAX {
        raise Refused("invalid_name", f"Enter a name of 1 to {NAME_MAX} characters.");
    }
    return name;
}

def _key(scope_id: str, name: str) -> str {
    # The uniqueness key: case and spacing don't make a different name.
    return f"{scope_id}:{name.casefold()}";
}

def _principal(scope: TenantScope) -> str {
    # Switches to the cinema's principal; returns the caller's root id to restore.
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    return me;
}

def _find(scope: TenantScope, node_ref: str) -> any {  # jac:ignore[W1037]
    # The node with id `node_ref`, read as the cinema's principal; None if it doesn't
    # exist or isn't valid.
    me = _principal(scope);
    try {
        found: any = jobj(node_ref);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found;
}

def _venue(scope: TenantScope, venue_id: str) -> Venue {
    found = _find(scope, venue_id) if venue_id else None;
    if not isinstance(found, Venue) or found.tenant_id != scope.ctx.tenant_id {
        raise NotFound();
    }
    return found as Venue;
}

def _auditorium(scope: TenantScope, auditorium_id: str) -> Auditorium {
    found = _find(scope, auditorium_id) if auditorium_id else None;
    if not isinstance(found, Auditorium) or found.tenant_id != scope.ctx.tenant_id {
        raise NotFound();
    }
    return found as Auditorium;
}

def _screens(scope: TenantScope, venue: Venue) -> list[Auditorium] {
    me = _principal(scope);
    try {
        found = [venue-->[?:Auditorium]];
    } finally {
        restore(me);
    }
    return sorted(
        found, key=lambda (a: Auditorium) -> str { return a.name.casefold(); }
    );  # jac:ignore[W1037]
}

def _screen_view(a: Auditorium) -> dict[str, str] {
    return {"auditorium_id": node_id(a), "venue_id": a.venue_id, "name": a.name};
}

def _venue_view(scope: TenantScope, v: Venue) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "venue_id": node_id(v),
        "name": v.name,
        "city": v.city,
        "address": v.address,
        "auditoriums": [_screen_view(a) for a in _screens(scope, v)]
    };
}

def _claim_name(namespace: str, key: str, owner: str, label: str) {
    # Claims `key` for `owner`, or refuses with name_taken. Made permanent on commit.
    if claim(namespace, key, owner, CLAIM_HOLD_S) != owner {
        raise Refused("name_taken", f"{label} already exists.");
    }
    on_commit(lambda { make_permanent(namespace, key, owner); });
}

def _details(city: str, address: str) -> tuple[str, str] {
    clean_city = _clean(city);
    if len(clean_city) > NAME_MAX {
        raise Refused("invalid_city", f"Enter a city of up to {NAME_MAX} characters.");
    }
    clean_address = _clean(address);
    if len(clean_address) > ADDRESS_MAX {
        raise Refused(
            "invalid_address", f"Enter an address of up to {ADDRESS_MAX} characters."
        );
    }
    return (clean_city, clean_address);
}

def _create_venue(tenant: str, name: str, city: str, address: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    clean = _name(name);
    (clean_city, clean_address) = _details(city, address);
    venue_id = fresh_node_id();
    key = _key(scope.ctx.tenant_id, clean);
    _claim_name(VENUE_NAMES, key, venue_id, f"A venue called '{clean}'");
    me = _principal(scope);
    try {
        venue = Venue(
            tenant_id=scope.ctx.tenant_id,
            name=clean,
            city=clean_city,
            address=clean_address,
            created_at=now().isoformat()
        );
        assign_id(venue, venue_id);
        scope.tenant ++> venue;
        attach_to_tenant(venue, scope.tenant);
        flush_now();
    } except Exception as e {
        release(VENUE_NAMES, key, venue_id);
        raise e;
    } finally {
        restore(me);
    }
    return {"ok": True, "venue": _venue_view(scope, venue)};
}

def _list_venues(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    if not any(READ in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments) {
        raise Forbidden(READ);
    }
    me = _principal(scope);
    try {
        venues = [scope.tenant-->[?:Venue]];
    } finally {
        restore(me);
    }
    visible = [
        v
        for v in venues
        if authorize(
            scope.ctx,
            READ,
            Resource(tenant_id=scope.ctx.tenant_id, venue_id=node_id(v))
        )
    ];
    ordered = sorted(
        visible, key=lambda (v: Venue) -> str { return v.name.casefold(); }
    );  # jac:ignore[W1037]
    return {"ok": True, "venues": [_venue_view(scope, v) for v in ordered]};
}

def _update_venue(
    tenant: str, venue_id: str, name: str, city: str, address: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE, venue_id);
    venue = _venue(scope, venue_id);
    clean = _name(name);
    (clean_city, clean_address) = _details(city, address);
    old_key = _key(scope.ctx.tenant_id, venue.name);
    new_key = _key(scope.ctx.tenant_id, clean);
    if new_key != old_key {
        _claim_name(VENUE_NAMES, new_key, venue_id, f"A venue called '{clean}'");
        on_commit(lambda { release(VENUE_NAMES, old_key, venue_id); });
    }
    me = _principal(scope);
    try {
        venue.name = clean;
        venue.city = clean_city;
        venue.address = clean_address;
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "venue": _venue_view(scope, venue)};
}

def _delete_venue(tenant: str, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    venue = _venue(scope, venue_id);
    if _screens(scope, venue) {
        raise Refused(
            "venue_not_empty", "Delete this venue's screens before deleting the venue."
        );
    }
    key = _key(scope.ctx.tenant_id, venue.name);
    me = _principal(scope);
    try {
        Jac.destroy([venue]);
        flush_now();
    } finally {
        restore(me);
    }
    on_commit(lambda { release(VENUE_NAMES, key, venue_id); });
    return {"ok": True};
}

def _create_auditorium(tenant: str, venue_id: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE, venue_id);
    venue = _venue(scope, venue_id);
    clean = _name(name);
    auditorium_id = fresh_node_id();
    key = _key(venue_id, clean);
    _claim_name(
        AUDITORIUM_NAMES, key, auditorium_id, f"A screen called '{clean}' at this venue"
    );
    me = _principal(scope);
    try {
        screen = Auditorium(
            tenant_id=scope.ctx.tenant_id,
            venue_id=venue_id,
            name=clean,
            created_at=now().isoformat()
        );
        assign_id(screen, auditorium_id);
        venue ++> screen;
        attach_to_tenant(screen, scope.tenant);
        flush_now();
    } except Exception as e {
        release(AUDITORIUM_NAMES, key, auditorium_id);
        raise e;
    } finally {
        restore(me);
    }
    return {"ok": True, "auditorium": _screen_view(screen)};
}

def _auditorium_scope(
    tenant: str, auditorium_id: str
) -> tuple[TenantScope, Auditorium] {
    # The caller's scope and the auditorium, once they may configure its venue.
    scope = on_shift(tenant);
    screen = _auditorium(scope, auditorium_id);
    return (scoped(tenant, CONFIGURE, screen.venue_id), screen);
}

def _rename_auditorium(tenant: str, auditorium_id: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, screen) = _auditorium_scope(tenant, auditorium_id);
    clean = _name(name);
    old_key = _key(screen.venue_id, screen.name);
    new_key = _key(screen.venue_id, clean);
    if new_key != old_key {
        _claim_name(
            AUDITORIUM_NAMES,
            new_key,
            auditorium_id,
            f"A screen called '{clean}' at this venue"
        );
        on_commit(lambda { release(AUDITORIUM_NAMES, old_key, auditorium_id); });
    }
    me = _principal(scope);
    try {
        screen.name = clean;
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "auditorium": _screen_view(screen)};
}

def _delete_auditorium(tenant: str, auditorium_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, screen) = _auditorium_scope(tenant, auditorium_id);
    key = _key(screen.venue_id, screen.name);
    me = _principal(scope);
    try {
        Jac.destroy([screen]);
        flush_now();
    } finally {
        restore(me);
    }
    on_commit(lambda { release(AUDITORIUM_NAMES, key, auditorium_id); });
    return {"ok": True};
}

def:priv create_venue(
    tenant: str, name: str, city: str, address: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return _answer(
        lambda -> any { return _create_venue(tenant, name, city, address); }
    );  # jac:ignore[W1037]
}

def:priv list_venues(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _answer(lambda -> any { return _list_venues(tenant); });  # jac:ignore[W1037]
}

def:priv update_venue(
    tenant: str, venue_id: str, name: str, city: str, address: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return _answer(
        lambda -> any { return _update_venue(tenant, venue_id, name, city, address); }  # jac:ignore[W1037]
    );
}

def:priv delete_venue(tenant: str, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _answer(lambda -> any { return _delete_venue(tenant, venue_id); });  # jac:ignore[W1037]
}

def:priv create_auditorium(tenant: str, venue_id: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _answer(
        lambda -> any { return _create_auditorium(tenant, venue_id, name); }  # jac:ignore[W1037]
    );
}

def:priv rename_auditorium(
    tenant: str, auditorium_id: str, name: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return _answer(
        lambda -> any { return _rename_auditorium(tenant, auditorium_id, name); }  # jac:ignore[W1037]
    );
}

def:priv delete_auditorium(tenant: str, auditorium_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _answer(
        lambda -> any { return _delete_auditorium(tenant, auditorium_id); }  # jac:ignore[W1037]
    );
}
