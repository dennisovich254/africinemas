"""The staff home page's data (P7.4): one request for the back office's Overview.

staff_home(tenant) answers what the caller's roles allow, for the cinema's today:

- setup (venues.configure): seven steps (venue, screen with a published seat layout,
  prices, movie, published showtime, published branding, a second member of staff),
  each done or not, with the back-office section that does it;
- showtimes: today's showtimes that were put on sale and not cancelled, at the venues
  where the caller may read showtimes, earliest first, each with seats sold and on sale
  and whether the caller may sell (bookings.create) or scan (tickets.scan) there;
- figures (financial_reports.read): today's net takings, tickets for today's showtimes,
  their occupancy (the sales report's numbers, ADR-0026);
- activity (audit.read): the last ACTIVITY audit events.

A part the caller may not see is None. It needs a login and an open shift (ADR-0006).
"""

import from datetime { datetime }
import from zoneinfo { ZoneInfo }
import from core.clock { now }
import from core.authz.context { TenantScope, on_shift }
import from core.authz.policy { Resource, authorize }
import from core.catalog.answers { answer }
import from core.catalog.models {
    Venue,
    Auditorium,
    Movie,
    Screening,
    SeatLayout,
    SeatSlot,
    PUBLISHED
}
import from core.catalog.storefront_api { cinema_timezone }
import from core.catalog.pricing { CURRENCY }
import from core.booking.availability { SeatState }
import from core.tenancy.models { Tenant }
import from core.tenancy.membership { records_of }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.theming.models { Branding }
import from core.reporting.aggregates { period_of, sales_report as counted }
import from core.reporting.report_api { cinema_records }
import from core.audit.log { events }

glob ACTIVITY: int = 5,
     NOT_SHOWN: list[str] = ["draft", "scheduled", "cancelled"],
     # (key, label, back-office section) in the order a new cinema does them.
     STEPS: list[tuple[str, str, str]] = [
         ("venue", "Add a venue", "venues"),
         ("screen", "Publish a screen's seat layout", "screens"),
         ("prices", "Set your ticket prices", "prices"),
         ("movie", "Add a movie", "movies"),
         ("showtime", "Publish a showtime", "screenings"),
         ("branding", "Publish your branding", "settings"),
         ("team", "Invite your team", "staff")
     ];

def _may(scope: TenantScope, action: str, venue_id: str | None = None) -> bool {
    return authorize(
        scope.ctx, action, Resource(tenant_id=scope.ctx.tenant_id, venue_id=venue_id)
    );
}

def _setup(cinema: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    # Which setup steps the cinema has done. Call as the cinema's principal.
    venues = [cinema-->[?:Venue]];
    screens = [s for v in venues for s in [v-->[?:Auditorium]]];
    laid_out = any(
        [l.status == PUBLISHED for s in screens for l in [s-->[?:SeatLayout]]]
    );
    shows = [x for s in screens for x in [s-->[?:Screening]]];
    branded = False;
    if cinema.branding_id {
        try {
            found: any = jobj(cinema.branding_id);  # jac:ignore[W1037]
            branded = isinstance(found, Branding) and (found as Branding).version > 0;
        } except Exception {
            branded = False;
        }
    }
    done = {
        "venue": len(venues) > 0,
        "screen": laid_out,
        "prices": bool(cinema.price_list_id),
        "movie": len([cinema-->[?:Movie]]) > 0,
        "showtime": any([x.state not in NOT_SHOWN for x in shows]),
        "branding": branded,
        "team": len(
            [
                m
                for m in records_of(cinema)
                if m.status == "active"
            ]
        )
            > 1
    };
    steps = [
        {"key": key, "label": label, "section": section, "done": done[key]}
        for (key, label, section) in STEPS
    ];
    return {
        "done": len(
            [
                s
                for s in steps
                if s["done"]
            ]
        ),
        "total": len(steps),
        "steps": steps
    };
}

def _showtimes(scope: TenantScope, timezone: str, today: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Today's showtimes the caller may see, with seats sold and what they may do there.
    cinema = scope.tenant;
    zone = ZoneInfo(timezone);
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        titles = {node_id(m): m.title for m in [cinema-->[?:Movie]]};
        for venue in [cinema-->[?:Venue]] {
            venue_id = node_id(venue);
            for screen in [venue-->[?:Auditorium]] {
                for s in [screen-->[?:Screening]] {
                    if s.state in NOT_SHOWN {
                        continue;
                    }
                    day = datetime.fromisoformat(s.starts_at).astimezone(zone).date();
                    if day.isoformat() != today {
                        continue;
                    }
                    slots = [
                        x
                        for x in [s-->[?:SeatSlot]]
                        if x.state != SeatState.NOT_FOR_SALE.value
                    ];
                    rows.append(
                        {
                            "screening_id": node_id(s),
                            "starts_at": s.starts_at,
                            "movie_title": titles.get(s.movie_id, ""),
                            "venue_id": venue_id,
                            "venue": venue.name,
                            "screen": screen.name,
                            "seats_sold": len(
                                [
                                    x
                                    for x in slots
                                    if x.state == SeatState.SOLD.value
                                ]
                            ),
                            "seats_on_sale": len(slots)
                        }
                    );
                }
            }
        }
    } finally {
        restore(me);
    }
    shown: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for row in rows {
        venue_id = str(row["venue_id"]);
        if not _may(scope, "showtimes.read", venue_id) {
            continue;
        }
        row["can_sell"] = _may(scope, "bookings.create", venue_id);
        row["can_scan"] = _may(scope, "tickets.scan", venue_id);
        shown.append(row);
    }
    return sorted(
        shown,
        key=lambda (r: dict[str, any]) -> str { return str(r["starts_at"]); }  # jac:ignore[W1037]
    );
}

def _figures(cinema: Tenant, timezone: str, today: str) -> dict[str, any] {  # jac:ignore[W1037]
    found = cinema_records(cinema);
    sales = counted(
        period_of(timezone, today, today), found.shows, found.tickets, found.money
    );
    return {
        "takings_net_cents": sales["takings"]["net_cents"],
        "tickets_sold": sales["attendance"]["tickets_sold"],
        "showtimes": sales["attendance"]["showtimes"],
        "occupancy_pct": sales["attendance"]["occupancy_pct"],
        "currency": CURRENCY
    };
}

def _staff_home(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    cinema = scope.tenant;
    timezone = cinema_timezone(cinema);
    today = now().astimezone(ZoneInfo(timezone)).date().isoformat();
    setup: dict[str, any] | None = None;  # jac:ignore[W1037]
    if _may(scope, "venues.configure") {
        me = node_id(root);
        act_as(cinema.principal_root_id);
        try {
            setup = _setup(cinema);
        } finally {
            restore(me);
        }
    }
    return {
        "ok": True,
        "cinema": {
            "name": cinema.name,
            "slug": cinema.slug,
            "timezone": timezone,
            "today": today
        },
        "setup": setup,
        "showtimes": _showtimes(scope, timezone, today),
        "figures": _figures(cinema, timezone, today)
            if _may(scope, "financial_reports.read")
            else None,
        "activity": events(scope.ctx.tenant_id, "", ACTIVITY, "")
            if _may(scope, "audit.read")
            else None
    };
}

def:priv staff_home(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _staff_home(tenant); });  # jac:ignore[W1037]
}
