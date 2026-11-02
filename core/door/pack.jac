"""The door copy and its sync (plan 17.2b part 1; docs/specs/offline-scanner.md §7).

door_pack(tenant, device_id, grant_id): the whole copy for a device's live grant: the
showtimes at the grant's venues whose door opens within 6 hours or is open (grants.jac's
window), and their tickets, each by the hash of its reference under a new salt (§7.2),
never the reference itself, the booker or the price. With it, a cursor.

door_pack_changes(tenant, device_id, cursor): what changed since the cursor, less 5
minutes of overlap for work that committed late: showtimes and tickets whose version
rose, showtimes newly in the window with all their tickets, and showtimes that left it
(removed). In pages of PAGE tickets (more: true, and a cursor to continue). It answers
resync instead when the cursor is over 30 minutes old, the copy over 2 hours, or the
caller's venues changed: the device then fetches a new copy.

The cursor isn't stored: it's signed with the ticket key and carries the cinema, copy,
grant, device, venues, salt and times, so a changed copy hashes with the same salt.
Both endpoints need the caller on shift with the device's live grant (grants.jac), at a
cinema scanning offline.
"""

import base64;
import hashlib;
import hmac;
import json;
import secrets;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.authz.context { TenantScope }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore, fresh_node_id }
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Screening }
import from core.catalog.venues { find_movie, find_venue, find_auditorium }
import from core.catalog.storefront_api { cinema_timezone }
import from core.booking.models { Order, Ticket }
import from core.booking.ticket_codes { ticket_key }
import from core.door.grants {
    DoorDevice,
    DoorGrant,
    door_scope,
    live_grant,
    scan_venues,
    window_showtimes
}

glob PACK_VERSION: str = "door-pack/1",
     CURSOR_VERSION: int = 1,
     PAGE: int = 1000,
     OVERLAP_S: int = 300,
     CURSOR_MAX_AGE_S: int = 1800,
     PACK_MAX_AGE_S: int = 7200;

def door_hash(salt: str, reference: str) -> str {
    # §7.2: lowercase hex SHA-256 of "door1|<salt>|<reference, upper-case, no dashes>".
    compact = reference.upper().replace("-", "").replace(" ", "");
    return hashlib.sha256(f"door1|{salt}|{compact}".encode("utf-8")).hexdigest();
}

def new_salt -> str {
    # 32 random bytes, base64url without padding.
    return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode("ascii").rstrip(
        "="
    );
}

def _sign(body: str) -> str {
    return hmac.new(
        ticket_key(), f"door-cursor|{body}".encode("utf-8"), hashlib.sha256
    ).hexdigest()[:32];
}

def make_cursor(state: dict[str, any]) -> str {  # jac:ignore[W1037]
    body = base64.urlsafe_b64encode(
        json.dumps(state, sort_keys=True).encode("utf-8")
    ).decode(
        "ascii"
    ).rstrip(
        "="
    );
    return f"{body}.{_sign(body)}";
}

def read_cursor(cursor: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    # The cursor's state when this server signed it; None otherwise.
    (body, _, given) = cursor.strip().partition(".");
    if not body or not hmac.compare_digest(_sign(body), given) {
        return None;
    }
    try {
        state = json.loads(
            base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)).decode("utf-8")
        );
    } except Exception {
        return None;
    }
    return state
        if isinstance(state, dict) and state.get("v") == CURSOR_VERSION
        else None;
}

def _when(stamp: str, fallback: str = "") -> datetime | None {
    text = stamp or fallback;
    return datetime.fromisoformat(text) if text else None;
}

def _showtime_row(cinema: Tenant, screening: Screening) -> dict[str, any] {  # jac:ignore[W1037]
    movie = find_movie(cinema, screening.movie_id);
    venue = find_venue(cinema, screening.venue_id);
    screen = find_auditorium(cinema, screening.auditorium_id);
    return {
        "screening_id": node_id(screening),
        "movie_title": movie.title if movie is not None else "",
        "starts_at": screening.starts_at,
        "ends_at": screening.ends_at,
        "screen": screen.name if screen is not None else "",
        "venue_id": screening.venue_id,
        "venue": venue.name if venue is not None else "",
        "state": screening.state,
        "version": screening.version
    };
}

def _tickets_of(cinema: Tenant, screening: Screening) -> list[Ticket] {
    # The showtime's tickets, of confirmed orders (snack batches have none).
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: list[Ticket] = [];
        for order in [screening-->[?:Order]] {
            if order.status == "confirmed" and not order.booking_id {
                found.extend([order-->[?:Ticket]]);
            }
        }
    } finally {
        restore(me);
    }
    return found;
}

def _ticket_row(salt: str, ticket: Ticket) -> dict[str, any] {  # jac:ignore[W1037]
    # What a device knows of a ticket: never its reference (§7.1).
    return {
        "tid": node_id(ticket),
        "h": door_hash(salt, ticket.reference),
        "screening_id": ticket.screening_id,
        "seat": ticket.seat_label,
        "ticket_name": ticket.ticket_name,
        "format": ticket.format,
        "glasses": ticket.glasses_bought,
        "status": ticket.status,
        "used_at": ticket.used_at if ticket.status == "used" else "",
        "used_where": "",
        "version": ticket.version
    };
}

def _settings(cinema: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    # What changes the device's decisions; sent with every answer (§7.3).
    return {
        "name": cinema.name,
        "timezone": cinema_timezone(cinema),
        "doors_open_minutes": cinema.doors_open_minutes
    };
}

def _venues_now(scope: TenantScope, grant: DoorGrant) -> list[str] {
    # The grant's venues where the caller may still scan.
    allowed = scan_venues(scope);
    return sorted(
        [
            v
            for v in grant.venue_ids
            if v in allowed
        ]
    );
}

def _pack(tenant: str, device_id: str, grant_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = door_scope(tenant);
    (device, grant) = live_grant(scope, device_id.strip(), grant_id.strip());
    at = now();
    venues = _venues_now(scope, grant);
    salt = new_salt();
    pack_id = fresh_node_id();
    shows = window_showtimes(scope.tenant, venues, at);
    tickets: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in shows {
        tickets.extend([_ticket_row(salt, t) for t in _tickets_of(scope.tenant, s)]);
    }
    stamp = at.isoformat();
    cursor = make_cursor(
        {
            "v": CURSOR_VERSION,
            "t": node_id(scope.tenant),
            "p": pack_id,
            "g": node_id(grant),
            "d": device.device_id,
            "vs": venues,
            "s": salt,
            "at": stamp,
            "made": stamp,
            "o": 0
        }
    );
    return {
        "ok": True,
        "pack_version": PACK_VERSION,
        "pack_id": pack_id,
        "grant_id": node_id(grant),
        "tenant_id": node_id(scope.tenant),
        "server_time": stamp,
        "salt": salt,
        "cursor": cursor,
        "cinema": _settings(scope.tenant),
        "showtimes": [_showtime_row(scope.tenant, s) for s in shows],
        "tickets": tickets
    };
}

def _resync(scope: TenantScope, at: datetime) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "resync": True,
        "server_time": at.isoformat(),
        "cinema": _settings(scope.tenant)
    };
}

def _changes(tenant: str, device_id: str, cursor: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = door_scope(tenant);
    state = read_cursor(cursor);
    if state is None
        or state["t"] != node_id(scope.tenant)
        or state["d"] != device_id.strip() {
        raise Refused(
            "invalid_cursor", "This device's copy isn't this cinema's. Resync."
        );
    }
    (device, grant) = live_grant(scope, state["d"], state["g"]);
    at = now();
    last = datetime.fromisoformat(state["at"]);
    made = datetime.fromisoformat(state["made"]);
    venues = _venues_now(scope, grant);
    if (at - last).total_seconds() > CURSOR_MAX_AGE_S
        or (at - made).total_seconds() > PACK_MAX_AGE_S
        or venues != state["vs"] {
        return _resync(scope, at);
    }
    since = last - timedelta(seconds=OVERLAP_S);
    salt = state["s"];
    shows = window_showtimes(scope.tenant, venues, at);
    shown_ids = [node_id(s) for s in shows];
    before = [node_id(s) for s in window_showtimes(scope.tenant, venues, last)];
    entering = [
        i
        for i in shown_ids
        if i not in before
    ];
    showtimes: list[dict[str, any]] = [];  # jac:ignore[W1037]
    changed: list[Ticket] = [];
    for s in shows {
        fresh = node_id(s) in entering;
        touched = _when(s.updated_at, s.created_at);
        if fresh or (touched is not None and touched >= since) {
            showtimes.append(_showtime_row(scope.tenant, s));
        }
        for t in _tickets_of(scope.tenant, s) {
            moved = _when(t.changed_at, t.issued_at);
            if fresh or (moved is not None and moved >= since) {
                changed.append(t);
            }
        }
    }
    for gone in [
        i
        for i in before
        if i not in shown_ids
    ] {
        showtimes.append({"screening_id": gone, "removed": True});
    }
    changed = sorted(
        changed,
        key=lambda (t: Ticket) -> str { return f"{t.changed_at or t.issued_at}|{node_id(
            t
        )}"; }  # jac:ignore[W1037]
    );
    offset = int(state.get("o", 0));
    page = changed[offset:offset + PAGE];
    more = len(changed) > offset + PAGE;
    following = dict(state);
    if more {
        following["o"] = offset + PAGE;
    } else {
        following["o"] = 0;
        following["at"] = at.isoformat();
    }
    return {
        "ok": True,
        "pack_id": state["p"],
        "server_time": at.isoformat(),
        "cursor": make_cursor(following),
        "more": more,
        "cinema": _settings(scope.tenant),
        "showtimes": showtimes if offset == 0 else [],
        "tickets": [_ticket_row(salt, t) for t in page]
    };
}

def:protect door_pack(tenant: str, device_id: str, grant_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The device's whole door copy (§7.1), and a cursor for its changes.
    return answer(lambda -> any { return _pack(tenant, device_id, grant_id); });  # jac:ignore[W1037]
}

def:protect door_pack_changes(
    tenant: str, device_id: str, cursor: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # What changed in the device's door copy since `cursor` (§7.3), or resync.
    return answer(lambda -> any { return _changes(tenant, device_id, cursor); });  # jac:ignore[W1037]
}
