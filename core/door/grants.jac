"""Offline grants (plan 17.2b part 1; docs/specs/offline-scanner.md §6).

A grant lets one member's phone (a door device) admit people with no connection, at the
venues where they may scan tickets. It lasts until the earliest of: their shift ending,
an hour after the last showtime in the device's door copy (§7.1), and 14 hours.

door_grant(tenant, device_id, device_name): the scanner asks on every sync. The
device's grant is renewed while it's the same member's, unrevoked and unexpired;
otherwise a new one replaces it. Refused without a shift and tickets.scan at some
venue, when the cinema hasn't turned offline scanning on (offline_scanning_off), and for
a revoked device (device_revoked). The first grant each day per device is audited
(door_grant.issued).

revoke_door_device(tenant, device_id): a manager who may invalidate tickets stops a
device. Its grant ends at once; a device that's offline learns of it at its next
contact (§6.3). A revoked device gets no more grants: clearing the phone's storage
makes it a new device, which staff name again.

Devices hang off the cinema, and a device's grants off it. A device's id is claimed
first (ADR-0007), so two syncs from one phone at once make one device.
"""

import re;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, holder }
import from core.authz.policy { Resource, Forbidden, ROLE_PERMISSIONS, authorize }
import from core.authz.context { NotFound, TenantScope, on_shift, scoped }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.shifts { shift_left_s }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id,
    assign_id
}
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Screening, Venue }
import from core.catalog.venues { screenings_of_cinema }
import from core.booking.redeem_api { doors_open_at }
import from core.audit.log { audited, record }

glob SCAN: str = "tickets.scan",
     REVOKE: str = "tickets.invalidate",
     POLICY: str = "door-policy/1",
     # A door copy holds the showtimes whose door opens within this many hours (O5).
     WINDOW_HOURS: int = 6,
     MAX_GRANT_HOURS: int = 14,
     AFTER_LAST_MINUTES: int = 60,
     NAME_MAX: int = 40,
     DEVICES: str = "door-device",
     # One door_grant.issued per device and day.
     GRANT_DAYS: str = "door-grant-day",
     DEVICE_ID: str = r"^[A-Za-z0-9-]{8,64}$",
     # Showtimes not yet on sale have no door.
     NOT_AT_DOOR: list[str] = ["draft", "scheduled"];

node DoorDevice {
    # A phone that scans at a cinema's door, as its staff named it ("Main door").
    # grant_id: its current grant.
    has tenant_id: str,
        device_id: str,
        name: str,
        created_at: str = "",
        last_seen_at: str = "",
        grant_id: str = "",
        revoked_at: str = "",
        revoked_by: str = "";
}

node DoorGrant {
    # Leave for one member's device to admit people offline, at venue_ids, until
    # expires_at (§6.1).
    has tenant_id: str,
        member_id: str,
        device_id: str,
        venue_ids: list[str] = [],
        issued_at: str = "",
        expires_at: str = "",
        policy: str = POLICY,
        revoked_at: str = "";
}

def in_window(screening: Screening, at: datetime, doors_minutes: int) -> bool {
    # A door copy's showtime: on sale (or since closed or cancelled, so the scanner can
    # say so), its door opening within WINDOW_HOURS of `at`, or open, and not ended.
    if screening.state in NOT_AT_DOOR {
        return False;
    }
    return doors_open_at(screening, doors_minutes) <= at + timedelta(hours=WINDOW_HOURS)
        and at < datetime.fromisoformat(screening.ends_at);
}

def window_showtimes(
    cinema: Tenant, venue_ids: list[str], at: datetime
) -> list[Screening] {
    return [
        s
        for s in screenings_of_cinema(cinema)
        if s.venue_id in venue_ids and in_window(s, at, cinema.doors_open_minutes)
    ];
}

def scan_venues(scope: TenantScope) -> list[str] {
    # The cinema's venues where the caller may scan tickets, sorted.
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        venues = [node_id(v) for v in [scope.tenant-->[?:Venue]]];
    } finally {
        restore(me);
    }
    return sorted(
        [
            v
            for v in venues
            if authorize(
                scope.ctx, SCAN, Resource(tenant_id=scope.ctx.tenant_id, venue_id=v)
            )
        ]
    );
}

def door_scope(tenant: str) -> TenantScope {
    # The caller on shift, able to scan somewhere, at a cinema scanning offline.
    scope = on_shift(tenant);
    if not any([SCAN in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments]) {
        raise Forbidden(SCAN);
    }
    if not scope.tenant.offline_scanning {
        raise Refused(
            "offline_scanning_off",
            "Offline scanning is off at this cinema. A manager can turn it on in Settings."
        );
    }
    return scope;
}

def _device_key(cinema: Tenant, device_id: str) -> str {
    return f"{node_id(cinema)}|{device_id}";
}

def _jobj(cinema: Tenant, found_id: str) -> any {  # jac:ignore[W1037]
    # The node with this id, read as the cinema's principal; None if there's none.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(found_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found;
}

def find_device(cinema: Tenant, device_id: str) -> DoorDevice | None {
    held = holder(DEVICES, _device_key(cinema, device_id));
    if not held {
        return None;
    }
    found = _jobj(cinema, held);
    return found if isinstance(found, DoorDevice) else None;
}

def find_grant(cinema: Tenant, grant_id: str) -> DoorGrant | None {
    if not grant_id {
        return None;
    }
    found = _jobj(cinema, grant_id);
    if not isinstance(found, DoorGrant) or found.tenant_id != node_id(cinema) {
        return None;
    }
    return found;
}

def _device(scope: TenantScope, device_id: str, name: str) -> DoorDevice {
    # The cinema's device with this id, made the first time it asks.
    found = find_device(scope.tenant, device_id);
    if found is not None {
        return found;
    }
    mine = fresh_node_id();
    if claim(DEVICES, _device_key(scope.tenant, device_id), mine) != mine {
        found = find_device(scope.tenant, device_id);
        if found is None {
            raise Refused("try_again", "This device is being set up. Try again.");
        }
        return found;
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        made = DoorDevice(
            tenant_id=node_id(scope.tenant),
            device_id=device_id,
            name=name,
            created_at=now().isoformat()
        );
        assign_id(made, mine);
        scope.tenant ++> made;
        attach_to_tenant(made, scope.tenant);
        flush_now();
    } finally {
        restore(me);
    }
    return made;
}

def _expiry(scope: TenantScope, venue_ids: list[str], at: datetime) -> datetime {
    # The earliest of the shift's end, an hour after the copy's last showtime, and
    # MAX_GRANT_HOURS (§6.1).
    left = shift_left_s(scope.ctx.tenant_id, scope.ctx.member_root_id);
    ends = min(at + timedelta(hours=MAX_GRANT_HOURS), at + timedelta(seconds=left));
    shown = window_showtimes(scope.tenant, venue_ids, at);
    if shown {
        last = max([datetime.fromisoformat(s.ends_at) for s in shown]);
        ends = min(ends, last + timedelta(minutes=AFTER_LAST_MINUTES));
    }
    return ends;
}

def grant_view(device: DoorDevice, grant: DoorGrant) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "grant_id": node_id(grant),
        "device_id": device.device_id,
        "device_name": device.name,
        "venue_ids": list(grant.venue_ids),
        "issued_at": grant.issued_at,
        "expires_at": grant.expires_at,
        "policy": grant.policy
    };
}

def _grant(tenant: str, device_id: str, device_name: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = door_scope(tenant);
    clean_id = device_id.strip();
    if not re.match(DEVICE_ID, clean_id) {
        raise Refused(
            "invalid_device", "This device's id isn't valid. Reopen the scanner."
        );
    }
    name = " ".join(device_name.split());
    if not name or len(name) > NAME_MAX {
        raise Refused(
            "invalid_name",
            f"Name this device in 1 to {NAME_MAX} characters, like Main door."
        );
    }
    venues = scan_venues(scope);
    if not venues {
        raise Forbidden(SCAN);
    }
    device = _device(scope, clean_id, name);
    if device.revoked_at {
        raise Refused(
            "device_revoked", "A manager has stopped this device from scanning offline."
        );
    }
    at = now();
    ends = _expiry(scope, venues, at).isoformat();
    member = scope.ctx.member_root_id;
    current = find_grant(scope.tenant, device.grant_id);
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        if current is not None
            and current.member_id == member
            and not current.revoked_at
            and datetime.fromisoformat(current.expires_at) > at {
            current.venue_ids = venues;
            current.expires_at = ends;
            grant = current;
        } else {
            grant = DoorGrant(
                tenant_id=node_id(scope.tenant),
                member_id=member,
                device_id=clean_id,
                venue_ids=venues,
                issued_at=at.isoformat(),
                expires_at=ends
            );
            device ++> grant;
            attach_to_tenant(grant, scope.tenant);
            device.grant_id = node_id(grant);
        }
        device.name = name;
        device.last_seen_at = at.isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    day = f"{_device_key(scope.tenant, clean_id)}|{at.date().isoformat()}";
    first = fresh_node_id();
    if claim(GRANT_DAYS, day, first, 2 * 86400) == first {
        record(tenant, "door_grant.issued", "door_device", clean_id, "success");
    }
    return {
        "ok": True,
        "grant": grant_view(device, grant),
        "server_time": at.isoformat()
    };
}

def live_grant(
    scope: TenantScope, device_id: str, grant_id: str
) -> tuple[DoorDevice, DoorGrant] {
    # The caller's device and its current grant, unrevoked and unexpired; refused as
    # grant_revoked or grant_expired, which stop the device's offline admissions.
    device = find_device(scope.tenant, device_id);
    grant = find_grant(scope.tenant, grant_id);
    if device is None
        or grant is None
        or device.revoked_at
        or grant.revoked_at
        or device.grant_id != grant_id
        or grant.device_id != device_id
        or grant.member_id != scope.ctx.member_root_id {
        raise Refused(
            "grant_revoked", "This device can no longer scan offline. Go online again."
        );
    }
    if datetime.fromisoformat(grant.expires_at) <= now() {
        raise Refused(
            "grant_expired",
            "Offline scanning has ended for this device: use the door list or go online."
        );
    }
    return (device, grant);
}

def _revoke(tenant: str, device_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, REVOKE);
    device = find_device(scope.tenant, device_id.strip());
    if device is None {
        raise NotFound();
    }
    grant = find_grant(scope.tenant, device.grant_id);
    stamp = now().isoformat();
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        if not device.revoked_at {
            device.revoked_at = stamp;
            device.revoked_by = scope.ctx.member_root_id;
        }
        if grant is not None and not grant.revoked_at {
            grant.revoked_at = stamp;
        }
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "device_id": device.device_id, "revoked_at": device.revoked_at};
}

def:protect door_grant(
    tenant: str, device_id: str, device_name: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # Issues or renews the device's offline grant (§6). Audits door_grant.issued itself,
    # the first time each day per device; a refused request records nothing.
    return answer(lambda -> any { return _grant(tenant, device_id, device_name); });  # jac:ignore[W1037]
}

def _do_revoke(tenant: str, device_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _revoke(tenant, device_id); });  # jac:ignore[W1037]
}

def:protect revoke_door_device(tenant: str, device_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Stops a device scanning offline (§6.3).
    return audited(
        tenant,
        "door_grant.revoked",
        "door_device",
        device_id,
        lambda -> any { return _do_revoke(tenant, device_id); }  # jac:ignore[W1037]
    );
}
