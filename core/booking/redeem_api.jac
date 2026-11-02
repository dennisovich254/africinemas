"""Redeeming a ticket at the door (P6.2, architecture §47, §48; ADR-0021).

redeem_ticket(tenant, screening_id, code): staff on shift with tickets.scan at the
showtime's venue (ushers, box office managers, general managers, admins, owners; a
venue-limited role only at its venues) redeem the ticket a code names, for the
showtime they're checking. The code is a scanned QR payload (P6.1) or a typed
reference (6.4's manual entry). Refusals, in the order they're checked:

- invalid_code: not a payload this server signed, nor something that can be a reference;
- snack_code: a snack pickup code (P12.9), which is collected at the snack counter;
- unknown_ticket: no such ticket at this cinema (another cinema's gets the same answer);
- wrong_showtime: the ticket is for another showtime, named (movie and start);
- showtime_closed: the showtime isn't on (cancelled or unpublished);
- too_early / showtime_over: the door is open from the cinema's doors_open_minutes
  (45 unless it changed it) before the start
  until the showtime ends;
- ticket_voided / ticket_refunded;
- already_redeemed: with when, and who scanned it.

One redemption per ticket, however many scanners race: the ticket is claimed (USED,
an atomic claim, ADR-0007) before it is marked used. The claim's owner records who and
when, so a losing scan can say so. If saving the ticket fails, the claim is released
before the error goes on (a replayed request then claims it again, rather than finding
its own claim and refusing).

With a scan_id (and the device's id), from the offline scanner (17.2b part 2;
docs/specs/offline-scanner.md §9.1), the scan is journaled (core/door/journal.jac): a
repeat of it gets the first answer without redeeming again; a scan id reused for another
scan is refused (scan_id_conflict, invalid_scan_id for a malformed one). The claim
carries the scan id, so a retry after a crash between claiming and saving finishes its
own save, and the ticket's save and the scan's outcome commit together.
"""

import from core.accounts.profile { name_of }
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, release, holder }
import from core.authz.policy {
    Resource,
    Forbidden,
    ROLE_PERMISSIONS,
    authorize,
    require
}
import from core.authz.context { NotFound, TenantScope, on_shift }
import from core.tenancy.models { Tenant }
import from core.tenancy.membership { records_of }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id
}
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Screening, PUBLISHED }
import from core.catalog.venues {
    find_screening,
    find_movie,
    find_venue,
    find_auditorium,
    screenings_of_cinema
}
import from core.catalog.storefront_api { cinema_timezone }
import from core.booking.models { Ticket }
import from core.booking.ticket_codes {
    REFS,
    VERSION,
    PICKUPS,
    PICKUP_VERSION,
    read_qr,
    typed_reference
}
import from core.tenancy.responses { refused }
import from core.audit.log { audited }
import from core.door.journal {
    DoorScan,
    DONE,
    REDEEMED,
    REFUSED,
    valid_scan_id,
    compact,
    fingerprint,
    begin,
    write,
    settle,
    replay
}

glob SCAN: str = "tickets.scan",
     USED: str = "ticket-used";

glob SNACK_CODE: str = "This is a snack pickup code. It's collected at the snack counter.";

def reference_of(code: str) -> str {
    # The reference a scanned or typed code names.
    text = code.strip();
    if text.startswith(f"{PICKUP_VERSION}.") {
        raise Refused("snack_code", SNACK_CODE);
    }
    found = read_qr(text) if text.startswith(f"{VERSION}.") else typed_reference(text);
    if found is None {
        raise Refused("invalid_code", "This isn't a ticket code from this cinema.");
    }
    return found;
}

def ticket_of(scope: TenantScope, reference: str) -> Ticket {
    # The cinema's ticket with this reference; another cinema's reads as unknown.
    owner = holder(REFS, reference);
    unknown = Refused("unknown_ticket", "No ticket with this code at this cinema.");
    if owner is None {
        if holder(PICKUPS, reference) is not None {
            raise Refused("snack_code", SNACK_CODE);
        }
        raise unknown;
    }
    (tenant_id, _, ticket_id) = owner.partition("|");
    if tenant_id != node_id(scope.tenant) {
        raise unknown;
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found: any = jobj(ticket_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    if not isinstance(found, Ticket) {
        raise unknown;
    }
    return found as Ticket;
}

def staff_name(tenant: Tenant, member_id: str) -> str {
    # How a staff member is named to their colleagues: their email or the invite's
    # note.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found = [
            m
            for m in records_of(tenant)
            if m.staff_root_id == member_id
        ];
    } finally {
        restore(me);
    }
    # The name they gave themselves (their profile, P12.15) first.
    named = name_of(member_id);
    if named {
        return named;
    }
    if found {
        return found[0].email or found[0].label or "a staff member";
    }
    return "a staff member";
}

def _used(tenant: Tenant, used_at: str, used_by: str) -> Refused {
    return Refused(
        "already_redeemed",
        "This ticket has already been used.",
        {"used_at": used_at, "used_by": staff_name(tenant, used_by)}
    );
}

def doors_open_at(screening: Screening, minutes: int) -> datetime {
    return datetime.fromisoformat(screening.starts_at) - timedelta(minutes=minutes);
}

def door_is_open(screening: Screening, at: datetime, minutes: int) -> bool {
    # The door window: from `minutes` (the cinema's doors_open_minutes) before the
    # start until the showtime ends (its ends_at, cleaning buffer included).
    return screening.state == PUBLISHED
        and doors_open_at(screening, minutes) <= at
        and at < datetime.fromisoformat(screening.ends_at);
}

def _check_ticket(scope: TenantScope, screening: Screening, ticket: Ticket) {
    if ticket.screening_id != node_id(screening) {
        theirs = find_screening(scope.tenant, ticket.screening_id);
        movie = find_movie(scope.tenant, theirs.movie_id)
            if theirs is not None
            else None;
        raise Refused(
            "wrong_showtime",
            "This ticket is for another showtime.",
            {
                "movie_title": movie.title if movie is not None else "",
                "starts_at": theirs.starts_at if theirs is not None else ""
            }
        );
    }
    if screening.state != PUBLISHED {
        raise Refused("showtime_closed", "This showtime isn't on.");
    }
    at = now();
    opens = doors_open_at(screening, scope.tenant.doors_open_minutes);
    if at < opens {
        raise Refused(
            "too_early",
            "The doors for this showtime aren't open yet.",
            {"opens_at": opens.isoformat()}
        );
    }
    if at >= datetime.fromisoformat(screening.ends_at) {
        raise Refused("showtime_over", "This showtime has ended.");
    }
    if ticket.status == "voided" {
        raise Refused("ticket_voided", "This ticket was cancelled.");
    }
    if ticket.status == "refunded" {
        raise Refused("ticket_refunded", "This ticket was refunded.");
    }
    if ticket.status == "used" {
        raise _used(scope.tenant, ticket.used_at, ticket.used_by);
    }
}

def _admit(
    scope: TenantScope,
    screening: Screening,
    code: str,
    scan_id: str,
    record: DoorScan | None
) -> dict[str, any] {  # jac:ignore[W1037]
    ticket = ticket_of(scope, reference_of(code));
    if record is not None {
        record.ticket_id = node_id(ticket);
    }
    _check_ticket(scope, screening, ticket);
    member = scope.ctx.member_root_id;
    stamp = now().isoformat();
    mine = f"{member}|{stamp}|{scan_id or fresh_node_id()}";
    won = claim(USED, node_id(ticket), mine);
    # A claim carrying this scan id is an earlier attempt's: finish its save (R10).
    if won != mine and not (scan_id and won.rpartition("|")[2] == scan_id) {
        (scanner, _, rest) = won.partition("|");
        raise _used(scope.tenant, rest.partition("|")[0], scanner);
    }
    response = {
        "ok": True,
        "ticket": {
            "seat_label": ticket.seat_label,
            "ticket_name": ticket.ticket_name,
            "format": ticket.format,
            "glasses_bought": ticket.glasses_bought,
            "reference": ticket.reference,
            "used_at": stamp
        }
    };
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        ticket.status = "used";
        ticket.used_at = stamp;
        ticket.used_by = member;
        ticket.used_scan_id = scan_id;
        ticket.version += 1;
        ticket.changed_at = stamp;
        if record is not None {
            settle(record, REDEEMED, response=response);
        }
        commit_now();
    } except Exception as e {
        release(USED, node_id(ticket), won);
        raise e;
    } finally {
        restore(me);
    }
    return response;
}

def _journaled(
    scope: TenantScope, screening: Screening, code: str, scan_id: str, device_id: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # An online scan with its scan id (§9.1): journaled, and its first answer returned
    # again to a repeat, without redeeming again.
    if not valid_scan_id(scan_id) {
        raise Refused("invalid_scan_id", "This scan's id isn't valid. Scan again.");
    }
    try {
        subject = compact(reference_of(code));
    } except Refused {
        subject = code.strip();
    }
    member = scope.ctx.member_root_id;
    identity = fingerprint(
        node_id(scope.tenant), member, device_id, node_id(screening), "scan", subject
    );
    (record_id, found) = begin(scope.tenant, scan_id, identity);
    if found is not None and found.state == DONE {
        return replay(found);
    }
    stamp = now().isoformat();
    record = found
        or write(
            scope.tenant,
            record_id,
            screening,
            {
                "scan_id": scan_id,
                "online": True,
                "member_id": member,
                "device_id": device_id,
                "screening_id": node_id(screening),
                "event_at": stamp,
                "received_at": stamp
            }
        );
    try {
        return _admit(scope, screening, code, scan_id, record);
    } except Refused as e {
        response: dict[str, any] = refused(e.code, e.message);  # jac:ignore[W1037]
        response["error"].update(e.details);
        me = node_id(root);
        act_as(scope.tenant.principal_root_id);
        try {
            settle(record, REFUSED, e.code, response=response);
            commit_now();
        } finally {
            restore(me);
        }
        raise e;
    }
}

def _redeem(
    tenant: str, screening_id: str, code: str, scan_id: str, device_id: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screening = find_screening(scope.tenant, screening_id);
    if screening is None {
        raise NotFound();
    }
    require(
        scope.ctx,
        SCAN,
        Resource(tenant_id=scope.ctx.tenant_id, venue_id=screening.venue_id)
    );
    if not scan_id.strip() {
        return _admit(scope, screening, code, "", None);
    }
    return _journaled(scope, screening, code, scan_id.strip(), device_id.strip());
}

def _door_showtimes(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    if not any([SCAN in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments]) {
        raise Forbidden(SCAN);
    }
    at = now();
    shown: list[dict[str, str]] = [];
    for s in screenings_of_cinema(scope.tenant) {
        venue_ok = authorize(
            scope.ctx,
            SCAN,
            Resource(tenant_id=scope.ctx.tenant_id, venue_id=s.venue_id)
        );
        if not venue_ok or not door_is_open(s, at, scope.tenant.doors_open_minutes) {
            continue;
        }
        movie = find_movie(scope.tenant, s.movie_id);
        venue = find_venue(scope.tenant, s.venue_id);
        screen = find_auditorium(scope.tenant, s.auditorium_id);
        shown.append(
            {
                "screening_id": node_id(s),
                "movie_title": movie.title if movie is not None else "",
                "starts_at": s.starts_at,
                "ends_at": s.ends_at,
                "venue": venue.name if venue is not None else "",
                "screen": screen.name if screen is not None else ""
            }
        );
    }
    return {
        "ok": True,
        "timezone": cinema_timezone(scope.tenant),
        "doors_open_minutes": scope.tenant.doors_open_minutes,
        "showtimes": sorted(
            shown,
            key=lambda (s: dict[str, str]) -> str { return s["starts_at"]; }  # jac:ignore[W1037]
        )
    };
}

def:protect door_showtimes(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The showtimes whose door is open now, at the venues where the caller may scan
    # tickets (P6.4): what the scanner page offers to check.
    return answer(lambda -> any { return _door_showtimes(tenant); });  # jac:ignore[W1037]
}

def _do_redeem_ticket(
    tenant: str, screening_id: str, code: str, scan_id: str, device_id: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _redeem(
            tenant, screening_id, code, scan_id, device_id
        ); }  # jac:ignore[W1037]
    );
}

def:protect redeem_ticket(
    tenant: str, screening_id: str, code: str, scan_id: str = "", device_id: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # scan_id and device_id: the offline scanner's (§9.1); without them, as before.
    return audited(
        tenant,
        "ticket.scanned",
        "showtime",
        screening_id,
        lambda -> any { return _do_redeem_ticket(  # jac:ignore[W1037]
            tenant, screening_id, code, scan_id, device_id
        ); }
    );
}
