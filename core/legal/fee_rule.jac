"""AfriCinemas' fee rule (P15.1, ADR-0079): the rates, versioned by the date each
version applies from.

Model C (owner, 2026-10-26): online, 7% on tickets, 3D glasses and the cinema's
booking fee, and 20% on snacks; at the box office, 3% on everything. Rates are kept in
basis points (700 = 7%). The first version applies from 2026-10-26 until a super admin
sets another.

- fee_rules(): the versions and the one in force, for platform staff (platform.read).
- set_fee_rule(...): super admins only (platform.settings). A new version applies from a
  day not in the past, so no order already paid is ever charged differently; days are
  the platform's (Africa/Nairobi). Recorded in the platform audit log.
- rule_on(day): the version that applies on `day`, for P15.2 to freeze on each order.

A change of rates is a change to the cinema agreement (its schedule 1), so it also
needs a new agreement version for cinemas to accept (clause 5.10).
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

glob SPACE: str = "fee-rule",
     KEY: str = "versions",
     TIMEZONE: str = "Africa/Nairobi",
     MAX_BP: int = 5000,
     FIRST: dict[str, any] = {  # jac:ignore[W1037]
         "version": 1,
         "online_ticket_bp": 700,
         "online_snack_bp": 2000,
         "counter_bp": 300,
         "applies_from": "2026-10-26",
         "set_by": "",
         "set_at": ""
     };

def today -> str {
    return now().astimezone(ZoneInfo(TIMEZONE)).date().isoformat();
}

def _order(v: dict[str, any]) -> tuple[str, int] {  # jac:ignore[W1037]
    return (str(v["applies_from"]), int(v["version"]));
}

def versions -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Every version, oldest first.
    kept = holder(SPACE, KEY);
    found: list[dict[str, any]] = json.loads(kept) if kept else [dict(FIRST)];  # jac:ignore[W1037]
    return sorted(found, key=_order);
}

def rule_on(day: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The version in force on `day` (an ISO date): the latest that applies by then.
    found = versions()[0];
    for v in versions() {
        if v["applies_from"] <= day {
            found = v;
        }
    }
    return found;
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

def _rules -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    return {
        "ok": True,
        "versions": versions(),
        "current": rule_on(today()),
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
    found = versions();
    if [
        v
        for v in found
        if v["applies_from"] == day
    ] {
        raise Refused(
            "date_taken", "A version already applies from that day. Choose another."
        );
    }
    made = {
        "version": max([v["version"] for v in found]) + 1,
        "online_ticket_bp": _basis_points(online_ticket_percent, "online ticket rate"),
        "online_snack_bp": _basis_points(online_snack_percent, "online snack rate"),
        "counter_bp": _basis_points(counter_percent, "box office rate"),
        "applies_from": day,
        "set_by": who,
        "set_at": now().isoformat()
    };
    found.append(made);
    take_claim(SPACE, KEY);
    claim(SPACE, KEY, json.dumps(found));
    return {"ok": True, "rule": made};
}

def:protect fee_rules -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_rules);
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
