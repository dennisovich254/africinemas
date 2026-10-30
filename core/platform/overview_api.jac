"""The platform overview (P13.4): the console's home, across every cinema.

platform_overview() answers, for any platform role (platform.read):
- how many cinemas there are, and how many are in each state;
- how many signed up this week (the last 7 days);
- bookings and net takings across the platform for each of the last DAYS days, and in
  all over them, by the day the money was taken: a booking is a payment (an online
  order paid, or a box office sale), and takings are every payment less refunds, from
  the same ledger entries as each cinema's own sales report (core/reporting).

Days are the platform's (PLATFORM_TIMEZONE), the same for every cinema, so they line
up. Cinemas with technical problems (13.5) and reviews waiting (Phase 14) are added
when those exist. Counts and sums only: no cinema's own records, no customer's.
"""

import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from core.clock { now }
import from core.catalog.pricing { CURRENCY }
import from core.catalog.answers { answer }
import from core.reporting.report_api { cinema_records }
import from core.reporting.aggregates { period_of }
import from core.platform.staff_api { require_platform }
import from core.platform.cinemas_api { all_cinemas, STATE_LABELS }
import from core.support.health { health_of }
import from core.platform.jobs { job_status }
import from core.platform.mpesa_watch { mpesa_state }

glob PLATFORM_TIMEZONE: str = "Africa/Nairobi",
     DAYS: int = 14,
     WEEK_DAYS: int = 7;

def _local_day(at: str, zone: ZoneInfo) -> str {
    # The platform's day of an ISO time, or "" when there's none.
    if not at {
        return "";
    }
    try {
        return datetime.fromisoformat(at).astimezone(zone).date().isoformat();
    } except ValueError {
        return "";
    }
}

def _overview -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    zone = ZoneInfo(PLATFORM_TIMEZONE);
    today = now().astimezone(zone).date();
    first = (today - timedelta(days=DAYS - 1)).isoformat();
    week_start = (today - timedelta(days=WEEK_DAYS - 1)).isoformat();
    period = period_of(PLATFORM_TIMEZONE, first, today.isoformat());
    states = {key: 0 for key in STATE_LABELS};
    signed_up = 0;
    takings: dict[str, int] = {};
    bookings: dict[str, int] = {};
    cinemas = all_cinemas();
    troubled: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for cinema in cinemas {
        health = health_of(cinema);
        if health["problems"] {
            troubled.append(
                {
                    "name": cinema.name,
                    "slug": cinema.slug,
                    "problems": health["problems"]
                }
            );
        }
        states[cinema.state] = states[cinema.state] + 1;
        if _local_day(cinema.created_at, zone) >= week_start {
            signed_up += 1;
        }
        for m in cinema_records(cinema).money {
            day = period.day_of(m.taken_at).isoformat();
            takings[day] = takings.get(day, 0) + m.amount_cents;
            if m.kind == "payment" {
                bookings[day] = bookings.get(day, 0) + 1;
            }
        }
    }
    days = [
        {
            "start": d.isoformat(),
            "takings_net_cents": takings.get(d.isoformat(), 0),
            "bookings": bookings.get(d.isoformat(), 0)
        } for d in period.days()
    ];
    return {
        "ok": True,
        "cinemas": len(cinemas),
        "states": [
            {"key": key, "label": label, "count": states[key]}
            for (key, label) in STATE_LABELS.items()
        ],
        "signed_up_this_week": signed_up,
        # Cinemas with technical problems (P13.5c), the most first.
        "with_problems": sorted(
            troubled,
            key=lambda (c: dict[str, any]) -> int { return 0 - int(c["problems"]); }  # jac:ignore[W1037]
        ),
        "days": days,
        "takings_net_cents": sum([d["takings_net_cents"] for d in days]),
        "bookings": sum([d["bookings"] for d in days]),
        "first": first,
        "last": today.isoformat(),
        "timezone": PLATFORM_TIMEZONE,
        "currency": CURRENCY,
        # The background jobs (P16.2): running, silent or waiting.
        "jobs": job_status(now()),
        # M-Pesa failing across the platform (P16.3), counts only.
        "mpesa": mpesa_state(now(), cinemas)
    };
}

def:protect platform_overview -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_overview);
}
