"""The data protection registers (P15.0): requests from people about their data, and
breaches, kept in the platform console (docs/legal/data-requests-procedure.md and
docs/legal/breach-procedure.md).

Super admins (platform.settings) log and update them; every change goes to the platform
audit log, and nothing is deleted or rewritten: an entry's `events` are its record of
what was done and when, which the registers are kept for (s.43(8); the Commissioner).

- **Requests**: when it arrived, who, how to reach them, what they ask, its kind, and
  who answers it (AfriCinemas, or a cinema for its customers, which we pass it to
  within PASS_DAYS working days). Its deadline is the kind's (KINDS). A step: identity
  checked, passed to the cinema, answered, declined (the last two close it, with what
  was done and why).
- **Breaches**: when we became aware and what happened, and our role, which starts the
  clocks: the cinemas told within 48 hours (processor), the Commissioner notified
  within 72 (controller). Its assessment (the data, how many people, which cinemas,
  whether it's notifiable and why) and each step: contained, assessed, cinemas told,
  Commissioner notified, people told, fixed, closed, or a note.

Each entry is a permanent claim, numbered in order (R-001, B-001), as JSON.
"""

import json;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, holder, take_claim, claims_in }
import from core.catalog.answers { Refused, answer }
import from core.platform.staff_api { require_platform }
import from core.audit.log { platform_audited }

glob REQUESTS: str = "dp-request",
     BREACHES: str = "dp-breach",
     TEXT_MAX: int = 2000,
     SHORT_MAX: int = 200,
     PASS_DAYS: int = 2,
     # kind: (what it's called, days to answer), from the procedure's section 3.
     KINDS: dict[str, tuple[str, int]] = {
         "access": ("Access: a copy of their data", 7),
         "rectification": ("Rectification: correct it", 14),
         "erasure": ("Erasure: delete it", 14),
         "restriction": ("Restriction: stop using it for now", 14),
         "objection": ("Objection to how it's used", 14),
         "portability": ("Portability: a copy to take elsewhere", 30),
         "stop_disclosure": ("Stop disclosure for others' marketing", 7)
     },
     REQUEST_STEPS: dict[str, str] = {
         "note": "Note",
         "identity_checked": "Identity checked",
         "passed_to_cinema": "Passed to the cinema",
         "answered": "Answered",
         "declined": "Declined"
     },
     REQUEST_CLOSING: list[str] = ["answered", "declined"],
     ROLES: dict[str, str] = {
         "processor": "Processor: a cinema's customers",
         "controller": "Controller: our own data",
         "both": "Both"
     },
     BREACH_STEPS: dict[str, str] = {
         "note": "Note",
         "contained": "Contained",
         "assessed": "Assessed",
         "cinemas_told": "Cinemas told",
         "commissioner_notified": "Commissioner notified",
         "people_told": "People affected told",
         "fixed": "Cause fixed",
         "closed": "Closed"
     };

def _text(value: any, most: int) -> str {  # jac:ignore[W1037]
    return value.strip()[:most] if isinstance(value, str) else "";
}

def _when(value: any) -> datetime {  # jac:ignore[W1037]
    # An ISO time from the form (local, with its offset), or now when it's left out.
    if not isinstance(value, str) or not value.strip() {
        return now();
    }
    try {
        return datetime.fromisoformat(value.strip());
    } except ValueError {
        raise Refused("invalid_time", "Enter the date and time.");
    }
}

def _next(space: str, prefix: str, record: dict[str, any]) -> str {  # jac:ignore[W1037]
    # Keeps `record` under the next free number.
    n = len(claims_in(space)) + 1;
    while True {
        key = f"{prefix}-{n:03d}";
        kept = json.dumps({** record, "id": key}, sort_keys=True);
        if claim(space, key, kept) == kept {
            return key;
        }
        n += 1;
    }
}

def _read(space: str, key: str) -> dict[str, any] {  # jac:ignore[W1037]
    kept = holder(space, str(key));
    if not kept {
        raise Refused("not_found", "There's no such entry.");
    }
    return json.loads(kept);
}

def _write(space: str, record: dict[str, any]) {  # jac:ignore[W1037]
    take_claim(space, record["id"]);
    claim(space, record["id"], json.dumps(record, sort_keys=True));
}

def _event(step: str, note: str, who: str) -> dict[str, str] {
    return {"at": now().isoformat(), "step": step, "note": note, "by": who};
}

def request_view(r: dict[str, any], at: datetime) -> dict[str, any] {  # jac:ignore[W1037]
    open = r["status"] not in REQUEST_CLOSING;
    due = datetime.fromisoformat(r["due"]);
    return {
        ** r,
        "kind_label": KINDS[r["kind"]][0],
        "open": open,
        "overdue": open and at > due
    };
}

def breach_view(b: dict[str, any], at: datetime) -> dict[str, any] {  # jac:ignore[W1037]
    done = [e["step"] for e in b["events"]];
    late: list[str] = [];
    if b["cinemas_by"]
        and "cinemas_told" not in done
        and at > datetime.fromisoformat(b["cinemas_by"]) {
        late.append("cinemas_told");
    }
    if b["commissioner_by"]
        and "commissioner_notified" not in done
        and at > datetime.fromisoformat(b["commissioner_by"]) {
        late.append("commissioner_notified");
    }
    return {
        ** b,
        "role_label": ROLES[b["role"]],
        "open": "closed" not in done,
        "done": done,
        "late": late
    };
}

def _received(r: dict[str, any]) -> str {  # jac:ignore[W1037]
    return r["received_at"];
}

def _aware(b: dict[str, any]) -> str {  # jac:ignore[W1037]
    return b["aware_at"];
}

def _registers -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.settings");
    at = now();
    requests = [request_view(json.loads(k), at) for (_, k, _) in claims_in(REQUESTS)];
    breaches = [breach_view(json.loads(k), at) for (_, k, _) in claims_in(BREACHES)];
    # Open first, then newest.
    requests = sorted(requests, key=_received, reverse=True);
    requests = [
        r
        for r in requests
        if r["open"]
    ]
        + [
            r
            for r in requests
            if not r["open"]
        ];
    breaches = sorted(breaches, key=_aware, reverse=True);
    breaches = [
        b
        for b in breaches
        if b["open"]
    ]
        + [
            b
            for b in breaches
            if not b["open"]
        ];
    return {
        "ok": True,
        "requests": requests,
        "breaches": breaches,
        # [key, label] pairs, in order, for the page's choices.
        "kinds": [[k, v[0]] for (k, v) in KINDS.items()],
        "request_steps": [[k, v] for (k, v) in REQUEST_STEPS.items()],
        "roles": [[k, v] for (k, v) in ROLES.items()],
        "breach_steps": [[k, v] for (k, v) in BREACH_STEPS.items()]
    };
}

def _log_request(fields: dict[str, any], who: str) -> dict[str, any] {  # jac:ignore[W1037]
    if not isinstance(fields, dict) {
        raise Refused("invalid_request", "Fill in the request.");
    }
    kind = str(fields.get("kind", ""));
    if kind not in KINDS {
        raise Refused("invalid_kind", "Choose what they're asking for.");
    }
    person = _text(fields.get("person"), SHORT_MAX);
    asked = _text(fields.get("asked"), TEXT_MAX);
    if not person or not asked {
        raise Refused("invalid_request", "Say who asked, and what they asked.");
    }
    received = _when(fields.get("received_at"));
    cinema = _text(fields.get("cinema"), SHORT_MAX);
    record = {
        "received_at": received.isoformat(),
        "person": person,
        "contact": _text(fields.get("contact"), SHORT_MAX),
        "cinema": cinema,
        "kind": kind,
        "asked": asked,
        "due": (received + timedelta(days=KINDS[kind][1])).isoformat(),
        # A cinema's customers are the cinema's to answer: passed on within 2 working
        # days (the procedure's section 1).
        "pass_by": (received + timedelta(days=PASS_DAYS + 2)).isoformat()
            if cinema
            else "",
        "status": "open",
        "events": [_event("logged", "", who)]
    };
    key = _next(REQUESTS, "R", record);
    return {"ok": True, "request": request_view(_read(REQUESTS, key), now())};
}

def _request_step(key: str, step: str, note: str, who: str) -> dict[str, any] {  # jac:ignore[W1037]
    record = _read(REQUESTS, key);
    if step not in REQUEST_STEPS {
        raise Refused("invalid_step", "Choose what was done.");
    }
    if record["status"] in REQUEST_CLOSING {
        raise Refused("closed", "This request was answered: it can't change now.");
    }
    said = _text(note, TEXT_MAX);
    if step in REQUEST_CLOSING + ["note"] and not said {
        raise Refused("invalid_note", "Say what was done, and why.");
    }
    record["events"] = record["events"] + [_event(step, said, who)];
    if step != "note" {
        record["status"] = step;
    }
    _write(REQUESTS, record);
    return {"ok": True, "request": request_view(record, now())};
}

def _log_breach(fields: dict[str, any], who: str) -> dict[str, any] {  # jac:ignore[W1037]
    if not isinstance(fields, dict) {
        raise Refused("invalid_breach", "Fill in the breach.");
    }
    role = str(fields.get("role", ""));
    if role not in ROLES {
        raise Refused("invalid_role", "Choose whose data it is.");
    }
    what = _text(fields.get("what"), TEXT_MAX);
    if not what {
        raise Refused("invalid_breach", "Say what happened.");
    }
    aware = _when(fields.get("aware_at"));
    record = {
        "aware_at": aware.isoformat(),
        "what": what,
        "role": role,
        # The clocks (the procedure's section 2).
        "cinemas_by": (aware + timedelta(hours=48)).isoformat()
            if role in ["processor", "both"]
            else "",
        "commissioner_by": (aware + timedelta(hours=72)).isoformat()
            if role in ["controller", "both"]
            else "",
        "data": "",
        "people": "",
        "cinemas": "",
        "notifiable": "unsure",
        "why": "",
        "events": [_event("logged", "", who)]
    };
    key = _next(BREACHES, "B", record);
    return {"ok": True, "breach": breach_view(_read(BREACHES, key), now())};
}

def _assess(key: str, fields: dict[str, any], who: str) -> dict[str, any] {  # jac:ignore[W1037]
    record = _read(BREACHES, key);
    if not isinstance(fields, dict) {
        raise Refused("invalid_breach", "Fill in the assessment.");
    }
    notifiable = str(fields.get("notifiable", ""));
    if notifiable not in ["yes", "no", "unsure"] {
        raise Refused("invalid_notifiable", "Say whether it's notifiable.");
    }
    why = _text(fields.get("why"), TEXT_MAX);
    if notifiable != "unsure" and not why {
        raise Refused("invalid_note", "Say why it is, or isn't, notifiable.");
    }
    for field in ["data", "people", "cinemas"] {
        record[field] = _text(fields.get(field), TEXT_MAX);
    }
    record["notifiable"] = notifiable;
    record["why"] = why;
    record["events"] = record["events"]
        + [_event("assessed", f"Notifiable: {notifiable}. {why}".strip(), who)];
    _write(BREACHES, record);
    return {"ok": True, "breach": breach_view(record, now())};
}

def _breach_step(key: str, step: str, note: str, who: str) -> dict[str, any] {  # jac:ignore[W1037]
    record = _read(BREACHES, key);
    if step not in BREACH_STEPS or step == "assessed" {
        raise Refused("invalid_step", "Choose what was done.");
    }
    if "closed" in [e["step"] for e in record["events"]] {
        raise Refused("closed", "This breach is closed: it can't change now.");
    }
    said = _text(note, TEXT_MAX);
    if not said {
        raise Refused("invalid_note", "Say what was done.");
    }
    record["events"] = record["events"] + [_event(step, said, who)];
    _write(BREACHES, record);
    return {"ok": True, "breach": breach_view(record, now())};
}

def _audited(action: str, kind: str, key: str, work: any) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.settings");
    } except Refused as e {
        return {"ok": False, "error": {"code": e.code, "message": e.message}};
    }
    return platform_audited(
        me.root_id,
        me.email,
        action,
        kind,
        str(key),
        lambda -> any { return work(me.email); }  # jac:ignore[W1037]
    );
}

def:protect dp_registers -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_registers);
}

def:protect log_data_request(fields: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return _audited(
        "platform.data_request_logged",
        "data_request",
        "",
        lambda (who: str) -> any { return answer(
            lambda -> any { return _log_request(fields, who); }
        ); }  # jac:ignore[W1037]
    );
}

def:protect data_request_step(request_id: str, step: str, note: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _audited(
        "platform.data_request_updated",
        "data_request",
        request_id,
        lambda (who: str) -> any { return answer(
            lambda -> any { return _request_step(request_id, step, note, who); }
        ); }  # jac:ignore[W1037]
    );
}

def:protect log_breach(fields: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return _audited(
        "platform.breach_logged",
        "breach",
        "",
        lambda (who: str) -> any { return answer(
            lambda -> any { return _log_breach(fields, who); }
        ); }  # jac:ignore[W1037]
    );
}

def:protect assess_breach(breach_id: str, fields: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return _audited(
        "platform.breach_assessed",
        "breach",
        breach_id,
        lambda (who: str) -> any { return answer(
            lambda -> any { return _assess(breach_id, fields, who); }
        ); }  # jac:ignore[W1037]
    );
}

def:protect breach_step(breach_id: str, step: str, note: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _audited(
        "platform.breach_updated",
        "breach",
        breach_id,
        lambda (who: str) -> any { return answer(
            lambda -> any { return _breach_step(breach_id, step, note, who); }
        ); }  # jac:ignore[W1037]
    );
}
