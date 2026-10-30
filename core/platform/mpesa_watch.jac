"""Is M-Pesa down? (P16.3): Safaricom's side, not a cinema's or a customer's.

With one or two cinemas, comparing cinemas says nothing (owner, 2026-10-30), so two
signals that work with any number:

1. **Asking Daraja ourselves.** Every CHECK (job_alerts.check_jobs, every 5 minutes)
   asks Daraja for a token with AfriCinemas' own M-Pesa app (payment_provider, the
   DARAJA_* keys invoices use): no customer or cinema is needed. Two in a row without
   an answer (PROBES_DOWN) means Daraja isn't answering. Our keys refused is said apart:
   that's ours to fix, not Safaricom's.
2. **Why real payments failed.** Most failures are the customer's (cancelled, a wrong
   PIN, too little money, a phone that's off: CUSTOMER_CODES) and say nothing about
   Safaricom. A cinema's keys refused ("credentials") is that cinema's, on its health.
   What points at Safaricom: the prompt got no answer, Daraja couldn't be reached or
   answered with its own error (5xx, "system busy"), or the result was a system error
   (SYSTEM_CODES). At least MIN_FAILURES of those in the last WINDOW_MINUTES, and at
   least FAILURE_SHARE of the attempts, means M-Pesa is likely down, at one cinema
   or many.

The console's overview says so (with Safaricom's own channels: it has no public status
page and announces outages on X); job_alerts.jac emails the team when it starts and
when it's over. Counts only: no customers, phones or amounts.
"""

import json;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, holder, take_claim }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.models { Venue, Auditorium, Screening }
import from core.booking.models { Order }
import from core.payments.models { PaymentIntent }
import from core.payments.choice { payment_provider }
import from core.platform.cinemas_api { all_cinemas }

glob WINDOW_MINUTES: int = 15,
     MIN_FAILURES: int = 3,
     FAILURE_SHARE: float = 0.5,
     PROBES: str = "mpesa-probe",
     PROBES_KEPT: int = 6,
     PROBES_DOWN: int = 2,
     # Safaricom's result codes for its own errors, and for what customers do.
     SYSTEM_CODES: list[int] = [1025, 9999],
     CUSTOMER_CODES: list[int] = [1, 1001, 1019, 1032, 1037, 2001],
     # Where Safaricom says what's wrong (no live status page of its own).
     SAFARICOM_LINKS: list[list[str]] = [
         ["Safaricom on X", "https://x.com/SafaricomPLC"],
         ["Safaricom Care on X", "https://x.com/Safaricom_Care"],
         ["Daraja (the M-Pesa API)", "https://developer.safaricom.co.ke"]
     ];

def _since(stamp: str, cutoff: datetime) -> bool {
    try {
        return bool(stamp) and datetime.fromisoformat(stamp) >= cutoff;
    } except ValueError {
        return False;
    }
}

def safaricom_side(intent: PaymentIntent) -> bool {
    # Whether the attempt failed in a way that points at Safaricom.
    if intent.push_uncertain {
        return True;
    }
    error = intent.push_error;
    if error in ["unavailable", "timeout"] or error.startswith("500.003") {
        return True;
    }
    if error.isdigit() and 500 <= int(error) < 600 {
        return True;
    }
    return intent.result_code in SYSTEM_CODES;
}

def tries_of(cinema: Tenant, since: datetime) -> tuple[int, int] {
    # The cinema's M-Pesa attempts since `since`, and how many failed on Safaricom's side.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    attempts = 0;
    failures = 0;
    try {
        orders: list[Order] = [];
        for venue in [cinema-->[?:Venue]] {
            orders.extend([venue-->[?:Order]]);
            for screen in [venue-->[?:Auditorium]] {
                for s in [screen-->[?:Screening]] {
                    orders.extend([s-->[?:Order]]);
                }
            }
        }
        for order in orders {
            for intent in [order-->[?:PaymentIntent]] {
                if _since(intent.created_at, since) {
                    attempts += 1;
                    if safaricom_side(intent) {
                        failures += 1;
                    }
                }
            }
        }
    } finally {
        restore(me);
    }
    return (attempts, failures);
}

def probes -> list[dict[str, str]] {
    # The last few times we asked Daraja, newest first: {"at", "result"}.
    kept = holder(PROBES, "platform");
    return json.loads(kept) if kept else [];
}

def probe_mpesa(at: datetime) -> str {
    # Asks Daraja for a token with AfriCinemas' own app; keeps the answer: "ok",
    # "unreachable", "refused" or "not_configured" (no provider set).
    try {
        result = payment_provider().reachable();
    } except Exception {
        result = "not_configured";
    }
    kept = [{"at": at.isoformat(), "result": result}] + probes();
    take_claim(PROBES, "platform");
    claim(PROBES, "platform", json.dumps(kept[:PROBES_KEPT]));
    return result;
}

def mpesa_state(at: datetime, cinemas: list[Tenant] | None = None) -> dict[str, any] {  # jac:ignore[W1037]
    # {"likely_down", "why" (the signals up: "daraja", "payments"), "probe" (the last
    # answer and when), "our_keys_refused", "attempts", "failures", "since", "links"}.
    since = at - timedelta(minutes=WINDOW_MINUTES);
    attempts = 0;
    failures = 0;
    for cinema in (cinemas if cinemas is not None else all_cinemas()) {
        (tried, failed) = tries_of(cinema, since);
        attempts += tried;
        failures += failed;
    }
    asked = probes();
    recent = [p["result"] for p in asked[:PROBES_DOWN]];
    daraja_down = len(recent) == PROBES_DOWN
        and all([r == "unreachable" for r in recent]);
    payments_down = failures >= MIN_FAILURES and failures >= attempts * FAILURE_SHARE;
    why: list[str] = [];
    if daraja_down {
        why.append("daraja");
    }
    if payments_down {
        why.append("payments");
    }
    return {
        "likely_down": len(why) > 0,
        "why": why,
        "probe": asked[0] if asked else None,
        "our_keys_refused": bool(asked) and asked[0]["result"] == "refused",
        "attempts": attempts,
        "failures": failures,
        "since": since.isoformat(),
        "links": SAFARICOM_LINKS
    };
}
