"""The door journal (plan 17.2b part 2; docs/specs/offline-scanner.md §9.1, §11.2, §12).

Every scan that carries a scan id, online or uploaded from a phone that scanned offline,
is one DoorScan: who, which device and grant, the showtime, the ticket, the event's
time as the device saw it and when it reached us, the device's decision and ours.
Append-only; reconciliation (part 5) reads it.

A scan id is claimed first (`door-scan`, ADR-0007), with a fingerprint of the scan's
identity (cinema, member, device, showtime, kind and the reference or M-Pesa code) and
the id its record will have. So, whatever crashes part-way (R11):
- the same scan sent again finds its own claim: its record, if it was written; if it was
  settled (state done), its original answer;
- a scan id reused for another scan is refused (scan_id_conflict);
- a claim without a record means an attempt died before writing: the next writes it.

A record is settled (outcome, state done) in the same transaction as the ticket's save.
"""

import hashlib;
import json;
import re;
import from core.claims { claim }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id,
    assign_id
}
import from core.catalog.answers { Refused }
import from core.catalog.models { Screening }

glob SCANS: str = "door-scan",
     SCAN_ID: str = r"^[A-Za-z0-9-]{8,64}$",
     RECEIVED: str = "received",
     DONE: str = "done",
     # Outcomes (§11.3). Part 5 adds the let-in matches and the exceptions list.
     REDEEMED: str = "redeemed",
     REFUSED: str = "refused",
     DOUBLE_ENTRY: str = "double_entry",
     AFTER_REFUND: str = "admitted_after_refund",
     AFTER_REVOCATION: str = "admitted_after_revocation",
     LET_IN_PENDING: str = "let_in_pending",
     REJECTED: str = "rejected",
     EXCEPTIONS: list[str] = [DOUBLE_ENTRY, AFTER_REFUND, AFTER_REVOCATION];

node DoorScan {
    # One door event (§8.2, §12). kind: "scan" or "let_in" (§10). decision: the
    # device's ("admit", "refuse" with decision_code, "let_in"); empty online, where
    # the server decides. outcome: ours, with outcome_code; answer_json: an online
    # scan's response, returned again to a repeat.
    has tenant_id: str,
        scan_id: str,
        kind: str = "scan",
        online: bool = False,
        member_id: str = "",
        device_id: str = "",
        grant_id: str = "",
        screening_id: str = "",
        ticket_id: str = "",
        seq: int = 0,
        decision: str = "",
        decision_code: str = "",
        event_at: str = "",
        uncertainty_ms: int = 0,
        pack_id: str = "",
        data_age_s: int = 0,
        received_at: str = "",
        mpesa_code: str = "",
        people: int = 0,
        seats: list[str] = [],
        state: str = RECEIVED,
        outcome: str = "",
        outcome_code: str = "",
        detail: str = "",
        answer_json: str = "";
}

def valid_scan_id(scan_id: str) -> bool {
    return bool(re.match(SCAN_ID, scan_id));
}

def compact(reference: str) -> str {
    return reference.upper().replace("-", "").replace(" ", "");
}

def fingerprint(
    tenant_id: str,
    member_id: str,
    device_id: str,
    screening_id: str,
    kind: str,
    subject: str
) -> str {
    # The scan's identity (§9.1): what a repeated scan id must match.
    text = "|".join([tenant_id, member_id, device_id, screening_id, kind, subject]);
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:32];
}

def _record(cinema: Tenant, record_id: str) -> DoorScan | None {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(record_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found if isinstance(found, DoorScan) else None;
}

def begin(cinema: Tenant, scan_id: str, identity: str) -> tuple[str, DoorScan | None] {
    # Claims the scan id for this identity (R11 step 1): the record's id, and the record
    # if an earlier attempt wrote it. Refused as scan_id_conflict for another identity.
    mine = f"{identity}|{fresh_node_id()}";
    won = claim(SCANS, f"{node_id(cinema)}|{scan_id}", mine);
    (held, _, record_id) = won.partition("|");
    if held != identity {
        raise Refused(
            "scan_id_conflict", "This scan's id was already used for another scan."
        );
    }
    return (record_id, _record(cinema, record_id));
}

def write(
    cinema: Tenant,
    record_id: str,
    screening: Screening | None,
    fields: dict[str, any]  # jac:ignore[W1037]
) -> DoorScan {
    # The scan's record, state received (R11 step 2), under its showtime when there's
    # one. Written in the request's transaction.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        made = DoorScan(tenant_id=node_id(cinema), **fields);
        assign_id(made, record_id);
        if screening is not None {
            screening ++> made;
        } else {
            cinema ++> made;
        }
        attach_to_tenant(made, cinema);
        flush_now();
    } finally {
        restore(me);
    }
    return made;
}

def settle(
    record: DoorScan,
    outcome: str,
    code: str = "",
    detail: str = "",
    response: dict[str, any] | None = None  # jac:ignore[W1037]
) {
    # Sets the outcome (R11 step 4). The caller commits it, with the ticket's save.
    record.outcome = outcome;
    record.outcome_code = code;
    record.detail = detail;
    if response is not None {
        record.answer_json = json.dumps(response);
    }
    record.state = DONE;
}

def replay(record: DoorScan) -> dict[str, any] {  # jac:ignore[W1037]
    # An online scan's original answer.
    return json.loads(record.answer_json);
}

def verdict(record: DoorScan) -> dict[str, any] {  # jac:ignore[W1037]
    # An upload's answer for a settled record (§11.1).
    if record.outcome == REJECTED {
        return {
            "scan_id": record.scan_id,
            "answer": "rejected",
            "reason": record.outcome_code
        };
    }
    if record.outcome in EXCEPTIONS {
        return {
            "scan_id": record.scan_id,
            "answer": "exception",
            "kind": record.outcome
        };
    }
    return {"scan_id": record.scan_id, "answer": "recorded", "outcome": record.outcome};
}
