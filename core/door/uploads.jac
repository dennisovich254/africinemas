"""Uploading the door journal (plan 17.2b part 2; docs/specs/offline-scanner.md §11).

upload_door_scans(tenant, device_id, protocol, entries): a phone's door events, oldest
first, up to BATCH_MAX. The caller on shift, able to scan, uploads their own device's
entries: a cinema that turns offline scanning off still gets what its phones scanned.
Each entry gets its own answer (§11.1):
- recorded (outcome: redeemed, refused, let_in_pending), or exception (kind:
  double_entry, admitted_after_refund, admitted_after_revocation): final;
- rejected (reason): final, kept for review: an entry that isn't valid, another
  member's or device's grant, a ticket that isn't the showtime's, a reused scan id;
- retry (update_required): every entry, for a protocol this server doesn't speak.
The phone deletes an entry only on a final answer (R2). A batch that fails part-way
answers nothing, and is sent again: each entry is journaled under its scan id
(core/door/journal.jac), so a repeat gets its first answer (R10, R11).

An admission redeems its ticket through the same claim as an online scan, carrying the
scan id: used_at is the event's time on the device, used_offline is set, and a
ticket.scanned event is audited with detail offline. A ticket another scan redeemed
first is a double entry; one voided or refunded, an admission after refund (the money
is untouched); one admitted after the grant's revocation or expiry isn't redeemed.
Let-ins wait for part 5, which matches their M-Pesa codes against payments.
"""

import re;
import from datetime { datetime }
import from core.clock { now }
import from core.claims { claim, release }
import from core.authz.policy { Forbidden, ROLE_PERMISSIONS }
import from core.authz.context { TenantScope, on_shift }
import from core.tenancy.principal { node_id, act_as, restore, commit_now }
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues { find_screening }
import from core.booking.redeem_api { USED, reference_of, ticket_of }
import from core.door.grants { DoorDevice, DoorGrant, find_device, find_grant }
import from core.door.journal {
    DoorScan,
    DONE,
    REDEEMED,
    REFUSED,
    DOUBLE_ENTRY,
    AFTER_REFUND,
    AFTER_REVOCATION,
    LET_IN_PENDING,
    REJECTED,
    valid_scan_id,
    compact,
    fingerprint,
    begin,
    write,
    settle,
    verdict
}
import from core.audit.log { record }

glob PROTOCOL: str = "door-upload/1",
     # The protocols this server accepts: the current and the previous (§17).
     PROTOCOLS: list[str] = [PROTOCOL],
     BATCH_MAX: int = 100,
     SCAN: str = "tickets.scan",
     MPESA_CODE: str = r"^[A-Z0-9]{8,12}$",
     PEOPLE_MAX: int = 20,
     SEAT_MAX: int = 8;

class BadEntry(ValueError) {}

def _text(raw: dict[str, any], key: str) -> str {  # jac:ignore[W1037]
    found = raw.get(key, "");
    return found.strip() if isinstance(found, str) else "";
}

def _whole(raw: dict[str, any], key: str, low: int, high: int) -> int {  # jac:ignore[W1037]
    found = raw.get(key, 0);
    if isinstance(found, bool)
        or not isinstance(found, int)
        or not low <= found <= high {
        raise BadEntry(key);
    }
    return found;
}

def _moment(text: str) -> datetime {
    try {
        at = datetime.fromisoformat(text);
    } except ValueError {
        raise BadEntry("event_at");
    }
    if at.tzinfo is None {
        raise BadEntry("event_at");
    }
    return at;
}

def _fields(raw: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # The entry's fields for its record (§8.2), checked; BadEntry names the first bad
    # one.
    kind = _text(raw, "kind");
    decision = _text(raw, "decision");
    if kind == "scan" and decision not in ["admit", "refuse"] {
        raise BadEntry("decision");
    }
    if kind == "let_in" and decision != "let_in" {
        raise BadEntry("decision");
    }
    if kind not in ["scan", "let_in"] {
        raise BadEntry("kind");
    }
    fields: dict[str, any] = {  # jac:ignore[W1037]
        "kind": kind,
        "decision": decision,
        "decision_code": _text(raw, "code")[:40],
        "grant_id": _text(raw, "grant_id"),
        "screening_id": _text(raw, "screening_id"),
        "event_at": _moment(_text(raw, "event_at")).isoformat(),
        "seq": _whole(raw, "seq", 0, 2 ** 31),
        "uncertainty_ms": _whole(raw, "uncertainty_ms", 0, 86400000),
        "pack_id": _text(raw, "pack_id")[:64],
        "data_age_s": _whole(raw, "data_age_s", 0, 86400 * 30)
    };
    if not fields["screening_id"] {
        raise BadEntry("screening_id");
    }
    if kind == "let_in" {
        code = _text(raw, "mpesa_code").upper();
        if not re.match(MPESA_CODE, code) {
            raise BadEntry("mpesa_code");
        }
        seats = raw.get("seats", []);
        if not isinstance(seats, list)
            or len(seats) > PEOPLE_MAX
            or not all(
                [isinstance(s, str) and 0 < len(s.strip()) <= SEAT_MAX for s in seats]
            ) {
            raise BadEntry("seats");
        }
        fields["mpesa_code"] = code;
        fields["people"] = _whole(raw, "people", 1, PEOPLE_MAX);
        fields["seats"] = [s.strip().upper() for s in seats];
    }
    return fields;
}

def _subject(raw: dict[str, any], fields: dict[str, any]) -> str {  # jac:ignore[W1037]
    # What the scan was of: the reference, as the online scan would read it, or the
    # let-in's M-Pesa code.
    if fields["kind"] == "let_in" {
        return fields["mpesa_code"];
    }
    given = _text(raw, "reference");
    if not given {
        raise BadEntry("reference");
    }
    try {
        return compact(reference_of(given));
    } except Refused {
        return given;
    }
}

def _rejected(scan_id: str, reason: str) -> dict[str, str] {
    return {"scan_id": scan_id, "answer": "rejected", "reason": reason};
}

def _admission(
    scope: TenantScope,
    device: DoorDevice,
    grant: DoorGrant,
    scan: DoorScan,
    reference: str
) {
    # Reconciles an offline admission (§11.3), settling its record; commits with the
    # ticket's save.
    at = datetime.fromisoformat(scan.event_at);
    stops = [
        datetime.fromisoformat(s)
        for s in [device.revoked_at, grant.revoked_at, grant.expires_at]
        if s
    ];
    if any([at >= s for s in stops]) {
        settle(scan, AFTER_REVOCATION);
        return;
    }
    try {
        ticket = ticket_of(scope, reference_of(reference));
    } except Refused {
        settle(scan, REJECTED, "unknown_ticket");
        return;
    }
    if ticket.screening_id != scan.screening_id {
        settle(scan, REJECTED, "wrong_showtime");
        return;
    }
    scan.ticket_id = node_id(ticket);
    if ticket.status in ["voided", "refunded"] {
        settle(scan, AFTER_REFUND, ticket.status);
        return;
    }
    member = scope.ctx.member_root_id;
    mine = f"{member}|{scan.event_at}|{scan.scan_id}";
    won = claim(USED, node_id(ticket), mine);
    if won != mine and won.rpartition("|")[2] != scan.scan_id {
        # Redeemed first by another scan: both events stay; attendance counts it once.
        settle(scan, DOUBLE_ENTRY, "", won);
        return;
    }
    stamp = now().isoformat();
    ticket.status = "used";
    ticket.used_at = scan.event_at;
    ticket.used_by = member;
    ticket.used_offline = True;
    ticket.used_scan_id = scan.scan_id;
    ticket.version += 1;
    ticket.changed_at = stamp;
    settle(scan, REDEEMED);
    try {
        commit_now();
    } except Exception as e {
        release(USED, node_id(ticket), won);
        raise e;
    }
}

def _one(
    scope: TenantScope,
    device: DoorDevice,
    raw: any  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # One entry's answer (§11.1, §11.2).
    if not isinstance(raw, dict) {
        return _rejected("", "invalid_entry");
    }
    scan_id = _text(raw, "scan_id");
    if not valid_scan_id(scan_id) {
        return _rejected(scan_id, "invalid_scan_id");
    }
    try {
        fields = _fields(raw);
        subject = _subject(raw, fields);
    } except BadEntry as e {
        return _rejected(scan_id, f"invalid_{e}");
    }
    member = scope.ctx.member_root_id;
    identity = fingerprint(
        node_id(scope.tenant),
        member,
        device.device_id,
        fields["screening_id"],
        fields["kind"],
        subject
    );
    try {
        (record_id, found) = begin(scope.tenant, scan_id, identity);
    } except Refused as e {
        return _rejected(scan_id, e.code);
    }
    if found is not None and found.state == DONE {
        return verdict(found);
    }
    screening = find_screening(scope.tenant, fields["screening_id"]);
    scan = found
        or write(
            scope.tenant,
            record_id,
            screening,
            {
                ** fields,
                "scan_id": scan_id,
                "member_id": member,
                "device_id": device.device_id,
                "received_at": now().isoformat()
            }
        );
    grant = find_grant(scope.tenant, scan.grant_id);
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        if grant is None
            or grant.device_id != device.device_id
            or grant.member_id != member {
            settle(scan, REJECTED, "unknown_grant");
        } elif screening is None {
            settle(scan, REJECTED, "unknown_showtime");
        } elif scan.kind == "let_in" {
            settle(scan, LET_IN_PENDING);
        } elif scan.decision == "refuse" {
            settle(scan, REFUSED, scan.decision_code);
        } else {
            _admission(scope, device, grant, scan, _text(raw, "reference"));
        }
        commit_now();
    } finally {
        restore(me);
    }
    if scan.outcome == REDEEMED {
        record(
            scope.tenant.slug,
            "ticket.scanned",
            "showtime",
            scan.screening_id,
            "success",
            "offline"
        );
    }
    return verdict(scan);
}

def _upload(
    tenant: str,
    device_id: str,
    protocol: str,
    entries: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    if not any([SCAN in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments]) {
        raise Forbidden(SCAN);
    }
    if not isinstance(entries, list) or len(entries) > BATCH_MAX {
        raise Refused(
            "batch_too_large", f"Send at most {BATCH_MAX} entries at a time."
        );
    }
    stamp = now().isoformat();
    if protocol not in PROTOCOLS {
        return {
            "ok": True,
            "server_time": stamp,
            "results": [
                {
                    "scan_id": _text(e, "scan_id") if isinstance(e, dict) else "",
                    "answer": "retry",
                    "reason": "update_required"
                } for e in entries
            ]
        };
    }
    device = find_device(scope.tenant, device_id.strip());
    if device is None {
        raise Refused(
            "unknown_device", "This device isn't known here. Reopen the scanner online."
        );
    }
    return {
        "ok": True,
        "server_time": stamp,
        "results": [_one(scope, device, e) for e in entries]
    };
}

def:protect upload_door_scans(
    tenant: str,
    device_id: str,
    protocol: str,
    entries: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # A device's door journal (§11). Audits ticket.scanned itself, per ticket redeemed.
    return answer(
        lambda -> any { return _upload(tenant, device_id, protocol, entries); }
    );  # jac:ignore[W1037]
}
