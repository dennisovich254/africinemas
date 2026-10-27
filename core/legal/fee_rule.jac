"""AfriCinemas' fee rule (P15.1, P15.2; ADR-0079, ADR-0080): the rates, versioned by the
day each version applies from, the platform's standard and any cinema's own.

**Rates** are a table keyed "<channel>:<category>": the channel is "online" (the
storefront, an AI app) or "counter" (the box office, cash or M-Pesa); the category is
"tickets" (with the cinema's booking fee), "glasses" (3D glasses) or "snacks". Each rate
is {"bp": basis points (700 = 7%), "per_unit_cents": a flat amount per item, 0 so far}.
"<channel>:*" covers the categories a version doesn't name, so new categories and
other structures (a flat fee per ticket, say) need no change to orders already paid.

**Versions**: the platform's standard (model C, owner 2026-10-26: online 7% on tickets,
glasses and the booking fee, 20% on snacks; box office 3% on everything) and, for a
cinema that negotiated other terms, its own versions. A cinema's version either sets its
own rates or returns it to the standard ("standard": True). rule_for(cinema, day) is the
version in force for that cinema on that day: its own latest applying by then, unless
that returns it to the standard, else the platform's. P15.2 freezes it on every paid
order (core/payments/fees.jac), so a later version never changes one.

Platform staff (platform.read) read every version; super admins (platform.settings)
add them, from today or a later day (Africa/Nairobi), never twice for one day, with
rates between 0% and 50%: in the platform audit log. A cinema's own staff with the
reports permission see the rates in force for them (my_fee_rates).

A change of rates is a change to the cinema agreement (schedule 1, clause 5.10), so a
cinema whose rates differ gets them in writing too.
"""

import json;
import math;
import from datetime { date }
import from zoneinfo { ZoneInfo }
import from core.clock { now }
import from core.claims { claim, holder, take_claim }
import from core.catalog.answers { Refused, answer }
import from core.platform.staff_api { require_platform }
import from core.audit.log { platform_audited }
import from core.authz.context { scoped }
import from core.tenancy.registry { lookup_slug }

glob SPACE: str = "fee-rule",
     PLATFORM_KEY: str = "versions",
     TIMEZONE: str = "Africa/Nairobi",
     MAX_BP: int = 5000,
     NOTE_MAX: int = 300,
     CHANNELS: list[str] = ["online", "counter"],
     CATEGORIES: list[str] = ["tickets", "glasses", "snacks"],
     FIRST_DAY: str = "2026-10-26",
     READ_RATES: str = "financial_reports.read";

def today -> str {
    return now().astimezone(ZoneInfo(TIMEZONE)).date().isoformat();
}

def rates_from(
    ticket_bp: int, snack_bp: int, counter_bp: int
) -> dict[str, dict[str, int]] {
    # The table for the three numbers the console asks for: online tickets and glasses,
    # online snacks, and everything at the box office.
    return {
        "online:tickets": {"bp": ticket_bp, "per_unit_cents": 0},
        "online:glasses": {"bp": ticket_bp, "per_unit_cents": 0},
        "online:snacks": {"bp": snack_bp, "per_unit_cents": 0},
        "counter:*": {"bp": counter_bp, "per_unit_cents": 0}
    };
}

def _first -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "version": 1,
        "scope": "platform",
        "applies_from": FIRST_DAY,
        "standard": False,
        "rates": rates_from(700, 2000, 300),
        "note": "Model C",
        "set_by": "",
        "set_at": ""
    };
}

def rate_of(rates: dict[str, any], channel: str, category: str) -> dict[str, int] {  # jac:ignore[W1037]
    # The rate for `category` sold through `channel`: its own entry, else the
    # channel's "*", else nothing.
    found = rates.get(f"{channel}:{category}") or rates.get(f"{channel}:*") or {};
    return {
        "bp": int(found.get("bp", 0)),
        "per_unit_cents": int(found.get("per_unit_cents", 0))
    };
}

def _summary(v: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # A version as the console shows it: the three headline rates beside the table.
    rates: dict[str, any] = v.get("rates") or {};  # jac:ignore[W1037]
    return {
        ** v,
        "online_ticket_bp": rate_of(rates, "online", "tickets")["bp"],
        "online_snack_bp": rate_of(rates, "online", "snacks")["bp"],
        "counter_bp": rate_of(rates, "counter", "tickets")["bp"]
    };
}

def _normal(v: dict[str, any], scope: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A stored version in the current shape (P15.1 kept three numbers, no table).
    made = dict(v);
    made.setdefault("scope", scope);
    made.setdefault("standard", False);
    made.setdefault("note", "");
    if "rates" not in made and "online_ticket_bp" in made {
        made["rates"] = rates_from(
            int(made["online_ticket_bp"]),
            int(made["online_snack_bp"]),
            int(made["counter_bp"])
        );
    }
    return made;
}

def _order(v: dict[str, any]) -> tuple[str, int] {  # jac:ignore[W1037]
    return (str(v["applies_from"]), int(v["version"]));
}

def _versions(
    key: str,
    scope: str,
    otherwise: list[dict[str, any]]  # jac:ignore[W1037]
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    kept = holder(SPACE, key);
    found: list[dict[str, any]] = json.loads(kept) if kept else otherwise;  # jac:ignore[W1037]
    return sorted([_normal(v, scope) for v in found], key=_order);
}

def _cinema_key(tenant_id: str) -> str {
    return f"cinema:{tenant_id}";
}

def versions -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The platform's standard versions, oldest first.
    return _versions(PLATFORM_KEY, "platform", [_first()]);
}

def cinema_versions(tenant_id: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # A cinema's own versions, oldest first: none for a cinema on the standard.
    return _versions(_cinema_key(tenant_id), "cinema", []);
}

def _latest(found: list[dict[str, any]], day: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    best: dict[str, any] | None = None;  # jac:ignore[W1037]
    for v in found {
        if v["applies_from"] <= day {
            best = v;
        }
    }
    return best;
}

def rule_on(day: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The platform's standard in force on `day` (an ISO date).
    found = versions();
    return _latest(found, day) or found[0];
}

def rule_for(tenant_id: str, day: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The version in force for a cinema on `day`: its own, unless it went back to the
    # standard, else the platform's.
    agreed = _latest(cinema_versions(tenant_id), day) if tenant_id else None;
    if agreed is not None and not agreed["standard"] {
        return agreed;
    }
    return rule_on(day);
}

def _basis_points(value: any, label: str) -> int {  # jac:ignore[W1037]
    try {
        number = float(value);
    } except (TypeError, ValueError) {
        raise Refused(
            "invalid_rate", f"Enter the {label} as a percentage, like 7 or 2.5."
        );
    }
    if not math.isfinite(number) {
        raise Refused(
            "invalid_rate", f"Enter the {label} as a percentage, like 7 or 2.5."
        );
    }
    bp = round(number * 100);
    if bp < 0 or bp > MAX_BP or abs(number * 100 - bp) > 1e-6 {
        raise Refused(
            "invalid_rate",
            f"The {label} must be between 0% and {MAX_BP
                // 100}%, with at most two decimals."
        );
    }
    return int(bp);
}

def _day(applies_from: str, found: list[dict[str, any]]) -> str {  # jac:ignore[W1037]
    try {
        day = date.fromisoformat(str(applies_from)).isoformat();
    } except ValueError {
        raise Refused("invalid_date", "Choose the day the new rates apply from.");
    }
    if day < today() {
        raise Refused(
            "date_in_past",
            "New rates can only apply from today or a later day, never to orders already paid."
        );
    }
    if [
        v
        for v in found
        if v["applies_from"] == day
    ] {
        raise Refused(
            "date_taken", "A version already applies from that day. Choose another."
        );
    }
    return day;
}

def _note(text: str) -> str {
    note = " ".join(str(text or "").split());
    if len(note) > NOTE_MAX or "<" in note or ">" in note {
        raise Refused(
            "invalid_note", f"Keep the note to {NOTE_MAX} characters of plain text."
        );
    }
    return note;
}

def _save(key: str, found: list[dict[str, any]]) {  # jac:ignore[W1037]
    take_claim(SPACE, key);
    claim(SPACE, key, json.dumps(found));
}

def _rules -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    return {
        "ok": True,
        "versions": [_summary(v) for v in versions()],
        "current": _summary(rule_on(today())),
        "today": today()
    };
}

def _set(
    online_ticket_percent: float,
    online_snack_percent: float,
    counter_percent: float,
    applies_from: str,
    who: str
) -> dict[str, any] {  # jac:ignore[W1037]
    found = versions();
    made = {
        "version": max([v["version"] for v in found]) + 1,
        "scope": "platform",
        "applies_from": _day(applies_from, found),
        "standard": False,
        "rates": rates_from(
            _basis_points(online_ticket_percent, "online ticket rate"),
            _basis_points(online_snack_percent, "online snack rate"),
            _basis_points(counter_percent, "box office rate")
        ),
        "note": "",
        "set_by": who,
        "set_at": now().isoformat()
    };
    _save(PLATFORM_KEY, found + [made]);
    return {"ok": True, "rule": _summary(made)};
}

def _tenant_of(slug: str) -> str {
    tenant_id = lookup_slug(str(slug or "").strip().lower());
    if not tenant_id {
        raise Refused("not_found", "No such cinema.");
    }
    return tenant_id;
}

def _cinema_terms(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    tenant_id = _tenant_of(slug);
    return {
        "ok": True,
        "versions": [_summary(v) for v in cinema_versions(tenant_id)],
        "current": _summary(rule_for(tenant_id, today())),
        "today": today()
    };
}

def _set_cinema(  # jac:ignore[W3030] a cinema's terms: which, the three rates, from when, why, by whom
    slug: str,
    standard: bool,
    online_ticket_percent: float,
    online_snack_percent: float,
    counter_percent: float,
    applies_from: str,
    note: str,
    who: str
) -> dict[str, any] {  # jac:ignore[W1037]
    tenant_id = _tenant_of(slug);
    found = cinema_versions(tenant_id);
    made = {
        "version": (max([v["version"] for v in found]) + 1) if found else 1,
        "scope": "cinema",
        "applies_from": _day(applies_from, found),
        "standard": bool(standard),
        "rates": {}
            if standard
            else rates_from(
                _basis_points(online_ticket_percent, "online ticket rate"),
                _basis_points(online_snack_percent, "online snack rate"),
                _basis_points(counter_percent, "box office rate")
            ),
        "note": _note(note),
        "set_by": who,
        "set_at": now().isoformat()
    };
    _save(_cinema_key(tenant_id), found + [made]);
    return {"ok": True, "rule": _summary(made)};
}

def _mine(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ_RATES);
    rule = rule_for(scope.ctx.tenant_id, today());
    return {"ok": True, "rule": _summary(rule), "agreed": rule["scope"] == "cinema"};
}

def:protect fee_rules -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_rules);
}

def:protect cinema_fee_terms(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _cinema_terms(slug); });  # jac:ignore[W1037]
}

def:protect my_fee_rates(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _mine(tenant); });  # jac:ignore[W1037]
}

def:protect set_fee_rule(
    online_ticket_percent: float,
    online_snack_percent: float,
    counter_percent: float,
    applies_from: str
) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.settings");
    } except Refused as e {
        return {"ok": False, "error": {"code": e.code, "message": e.message}};
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.fee_rule_set",
        "fee_rule",
        str(applies_from),
        lambda -> any { return _set(
            online_ticket_percent,
            online_snack_percent,
            counter_percent,
            applies_from,
            me.email
        ); },  # jac:ignore[W1037]
        detail=f"{online_ticket_percent}% / {online_snack_percent}% / {counter_percent}%"
    );
}

def:protect set_cinema_fee_terms(
    slug: str,
    standard: bool,
    online_ticket_percent: float,
    online_snack_percent: float,
    counter_percent: float,
    applies_from: str,
    note: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # A cinema's own rates from a day (negotiated terms), or back to the standard
    # (`standard`: the rates are then ignored). Every parameter is required: an
    # omitted default reaches an endpoint as text (JI-060).
    try {
        me = require_platform("platform.settings");
    } except Refused as e {
        return {"ok": False, "error": {"code": e.code, "message": e.message}};
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.cinema_fee_set",
        "fee_rule",
        str(slug),
        lambda -> any { return _set_cinema(
            slug,
            standard,
            online_ticket_percent,
            online_snack_percent,
            counter_percent,
            applies_from,
            note,
            me.email
        ); },  # jac:ignore[W1037]
        detail="standard"
            if standard
            else f"{online_ticket_percent}% / {online_snack_percent}% / {counter_percent}% from {applies_from}"
    );
}
