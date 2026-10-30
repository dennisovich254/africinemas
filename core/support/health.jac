"""A cinema's technical health (P13.5c): the problems our support team should know about.

health_of(cinema) counts, from the cinema's own records:
- **payments needing attention**: M-Pesa took money that couldn't be settled on its own
  (PaymentState.NEEDS_ATTENTION, ADR-0015), in the last ATTENTION_DAYS days;
- **refunds due**: open RefundTasks (money that bought nothing), and how much;
- **M-Pesa failures**: attempts in the last FAILURE_DAYS days that failed, timed out or
  whose prompt may not have arrived, out of all attempts then. Customers cancel and
  mistype PINs, so failures count as a problem only when they're most attempts
  (FAILURE_SHARE, at least FAILURE_MIN of them);
- **M-Pesa keys refused**: Daraja refused the cinema's own keys on a payment (P16.3),
  which the cinema fixes in Settings → Payments;
- **stuck payments and orders**: a payment still waiting on M-Pesa, or an unpaid order
  past its time, more than STUCK_MINUTES after it should have been settled or released
  (the resolver and the sweeper do that within minutes, P5.5);
- **emails not sent**: ticket and support emails still queued MAIL_LATE_S after they
  were queued (a failed send stays queued for the next try).

Counts and sums only: no customer, phone, email or booking. `problems` is how many
signals are up. Storefront errors aren't recorded anywhere yet, so they aren't here.
"""

import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.catalog.pricing { CURRENCY }
import from core.claims { claims_in }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.models { Venue, Auditorium, Screening }
import from core.booking.models { Order }
import from core.payments.models { PaymentIntent, RefundTask }
import from core.booking.ticket_delivery { MAIL_QUEUE }
import from core.support.names { REPLY_MAIL }

glob ATTENTION_DAYS: int = 30,
     FAILURE_DAYS: int = 7,
     FAILURE_MIN: int = 5,
     FAILURE_SHARE: float = 0.5,
     STUCK_MINUTES: int = 30,
     MAIL_LATE_S: int = 600,
     FAILED_STATES: list[str] = ["failed", "timeout", "unknown"],
     WAITING_STATES: list[str] = ["created", "stk_requested", "timeout", "unknown"];

def _at(stamp: str) -> datetime | None {
    try {
        return datetime.fromisoformat(stamp) if stamp else None;
    } except ValueError {
        return None;
    }
}

def _since(stamp: str, cutoff: datetime) -> bool {
    found = _at(stamp);
    return found is not None and found >= cutoff;
}

def _before(stamp: str, cutoff: datetime) -> bool {
    found = _at(stamp);
    return found is not None and found < cutoff;
}

def _late_mail(tenant_id: str) -> int {
    # The cinema's ticket and support emails still queued long after they were.
    late = 0;
    for space in [MAIL_QUEUE, REPLY_MAIL] {
        for (_, queued, age) in claims_in(space) {
            if queued.startswith(f"{tenant_id}|") and age > MAIL_LATE_S {
                late += 1;
            }
        }
    }
    return late;
}

def health_of(cinema: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    at = now();
    attention_from = at - timedelta(days=ATTENTION_DAYS);
    failure_from = at - timedelta(days=FAILURE_DAYS);
    stuck_before = at - timedelta(minutes=STUCK_MINUTES);
    attention = 0;
    attempts = 0;
    failures = 0;
    refused_keys = 0;
    stuck = 0;
    refunds = 0;
    refund_cents = 0;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        for venue in [cinema-->[?:Venue]] {
            for screen in [venue-->[?:Auditorium]] {
                for screening in [screen-->[?:Screening]] {
                    for order in [screening-->[?:Order]] {
                        if order.status == "pending_payment"
                            and _before(order.pay_by, stuck_before) {
                            stuck += 1;
                        }
                        for intent in [order-->[?:PaymentIntent]] {
                            if intent.state == "needs_attention"
                                and _since(intent.updated_at, attention_from) {
                                attention += 1;
                            }
                            if _since(intent.created_at, failure_from) {
                                attempts += 1;
                                if intent.state in FAILED_STATES
                                    or intent.push_uncertain {
                                    failures += 1;
                                }
                                if intent.push_error == "credentials" {
                                    refused_keys += 1;
                                }
                            }
                            if intent.state in WAITING_STATES
                                and _before(
                                    intent.updated_at or intent.created_at, stuck_before
                                ) {
                                stuck += 1;
                            }
                            for task in [intent-->[?:RefundTask]] {
                                if task.status == "open" {
                                    refunds += 1;
                                    refund_cents += task.amount_cents;
                                }
                            }
                        }
                    }
                }
            }
        }
    } finally {
        restore(me);
    }
    emails = _late_mail(node_id(cinema));
    failing = attempts >= FAILURE_MIN and failures >= attempts * FAILURE_SHARE;
    signals = [
        {
            "key": "payments_attention",
            "label": "Payments needing attention",
            "count": attention,
            "note": f"Last {ATTENTION_DAYS} days",
            "up": attention > 0
        },
        {
            "key": "refunds_due",
            "label": "Refunds due",
            "count": refunds,
            "amount_cents": refund_cents,
            "note": "Open",
            "up": refunds > 0
        },
        {
            "key": "mpesa_failures",
            "label": "M-Pesa attempts that failed",
            "count": failures,
            "note": f"Of {attempts} in the last {FAILURE_DAYS} days",
            "up": failing
        },
        {
            # The cinema's own M-Pesa keys refused by Daraja (P16.3): the cinema's to fix
            # in Settings → Payments, never Safaricom being down.
            "key": "mpesa_keys",
            "label": "M-Pesa refused the cinema's keys",
            "count": refused_keys,
            "note": f"Last {FAILURE_DAYS} days",
            "up": refused_keys > 0
        },
        {
            "key": "stuck",
            "label": "Stuck payments and orders",
            "count": stuck,
            "note": f"Unsettled after {STUCK_MINUTES} minutes",
            "up": stuck > 0
        },
        {
            "key": "emails_late",
            "label": "Emails not sent",
            "count": emails,
            "note": f"Queued over {MAIL_LATE_S // 60} minutes",
            "up": emails > 0
        }
    ];
    up = [
        s
        for s in signals
        if s["up"]
    ];
    return {"signals": signals, "problems": len(up), "currency": CURRENCY};
}
