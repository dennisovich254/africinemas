"""M-Pesa failing across the platform (P16.3): likely Safaricom, not the cinemas.

One cinema's payments failing is that cinema's problem (its keys, its paybill: its
health, 13.5c). Most cinemas' failing within the same hour is M-Pesa's. mpesa_watch
counts, for the last WINDOW_MINUTES, each cinema's M-Pesa attempts and failures (failed,
timed out, or a prompt that may not have arrived, as health.jac counts them):
- a cinema is **failing** when it tried at least MIN_ATTEMPTS times and at least
  FAILING_SHARE of them failed;
- M-Pesa is **likely down** when at least MIN_CINEMAS cinemas are failing, and they're
  at least OUTAGE_SHARE of the cinemas that tried.
The console's overview says so, with Safaricom's own channels (it has no public status
page: it announces outages on X); job_alerts.jac emails the team when it starts and when
it's over. Counts only: no cinema's customers, phones or amounts.
"""

import from datetime { datetime, timedelta }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.models { Venue, Auditorium, Screening }
import from core.booking.models { Order }
import from core.payments.models { PaymentIntent }
import from core.platform.cinemas_api { all_cinemas }

glob WINDOW_MINUTES: int = 60,
     MIN_ATTEMPTS: int = 2,
     FAILING_SHARE: float = 0.5,
     MIN_CINEMAS: int = 3,
     OUTAGE_SHARE: float = 0.5,
     FAILED_STATES: list[str] = ["failed", "timeout", "unknown"],
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

def tries_of(cinema: Tenant, since: datetime) -> tuple[int, int] {
    # The cinema's M-Pesa attempts since `since`, and how many failed.
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
                    if intent.state in FAILED_STATES or intent.push_uncertain {
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

def mpesa_state(at: datetime, cinemas: list[Tenant] | None = None) -> dict[str, any] {  # jac:ignore[W1037]
    # Across the platform, the last WINDOW_MINUTES: {"likely_down", "trying",
    # "failing", "attempts", "failures", "since", "links"}.
    since = at - timedelta(minutes=WINDOW_MINUTES);
    trying = 0;
    failing = 0;
    attempts = 0;
    failures = 0;
    for cinema in (cinemas if cinemas is not None else all_cinemas()) {
        (tried, failed) = tries_of(cinema, since);
        if tried == 0 {
            continue;
        }
        trying += 1;
        attempts += tried;
        failures += failed;
        if tried >= MIN_ATTEMPTS and failed >= tried * FAILING_SHARE {
            failing += 1;
        }
    }
    return {
        "likely_down": failing >= MIN_CINEMAS and failing >= trying * OUTAGE_SHARE,
        "trying": trying,
        "failing": failing,
        "attempts": attempts,
        "failures": failures,
        "since": since.isoformat(),
        "links": SAFARICOM_LINKS
    };
}
