"""The sales report endpoint (P7.1, architecture §76, §77; ADR-0026).

sales_report(tenant, date_from, date_to, venue_id) answers the cinema's takings and
attendance for its local days date_from..date_to (empty: today; the answer's `today` is
the cinema's day, for the dashboard's "last 7 days"), of one venue when venue_id is given,
with the drill-down venue, screen, movie, showtime. It needs a login, an open shift
(ADR-0006) and financial_reports.read: owners, general managers, finance managers and
auditors. The numbers come from core/reporting/aggregates.jac; this module collects the
records from the cinema's graph:

- every showtime that was put on sale (never a draft or one only scheduled), with its
  seats on sale (its seat slots that aren't blocked or house seats);
- the tickets of its orders, priced from their order's lines (service fee included);
- the ledger entries of showtime and snacks-only venue orders: a payment recorded
  by a member of staff is a box office sale;
- paid snack snapshots for product/variant rankings, and current stock alerts.
"""

import from datetime { timedelta }
import from zoneinfo { ZoneInfo }
import from core.clock { now }
import from core.authz.context { NotFound, scoped }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Venue, Auditorium, Movie, Screening, SeatSlot }
import from core.catalog.venues { find_venue }
import from core.catalog.storefront_api { cinema_timezone }
import from core.catalog.pricing { CURRENCY }
import from core.booking.models { Order, Ticket }
import from core.booking.availability { SeatState }
import from core.payments.ledger { LedgerEntry }
import from core.payments.fees { fee_entries }
import from core.reporting.aggregates {
    Show,
    SoldTicket,
    Money,
    SnackSold,
    snack_share,
    Period,
    period_of,
    sales_report as counted
}

import from core.snacks.models { SnackProduct, SnackVariant }
import from core.snacks.inventory_api { level_of }
import from core.snacks.stock { FEW_LEFT }
import from core.snacks.catalog { variant_label }

glob READ: str = "financial_reports.read",
     NEVER_ON_SALE: list[str] = ["draft", "scheduled"];

obj Records {
    has shows: list[Show] = [],
        tickets: list[SoldTicket] = [],
        money: list[Money] = [],
        # AfriCinemas' fees (P15.2), in the same shape as money.
        fees: list[Money] = [],
        snacks: list[SnackSold] = [],
        venues: dict[str, str] = {};
}

def _of_order(order: Order, into: Records, venue_id: str, products: dict[str, str]) {
    # The order's tickets, ledger and paid snacks. Call as the cinema's principal.
    lines = {str(line.get("seat_label", "")): line for line in order.lines};
    for t in [order-->[?:Ticket]] {
        line = lines.get(t.seat_label, {});
        into.tickets.append(
            SoldTicket(
                screening_id=t.screening_id,
                status=t.status,
                price_cents=int(line.get("total_cents", 0)),
                fee_cents=int(line.get("service_fee_cents", 0))
            )
        );
    }
    for f in fee_entries(order) {
        into.fees.append(
            Money(
                screening_id=order.screening_id,
                kind=f.kind,
                amount_cents=f.amount_cents,
                taken_at=f.created_at,
                counter=f.channel == "counter",
                venue_id=venue_id,
                order_ref=order.reference
            )
        );
    }
    entries = [order-->[?:LedgerEntry]];
    for e in entries {
        into.money.append(
            Money(
                screening_id=order.screening_id,
                kind=e.kind,
                amount_cents=e.amount_cents,
                taken_at=e.created_at,
                method=e.method,
                counter=bool(e.recorded_by),
                venue_id=venue_id,
                snacks_cents=snack_share(
                    e.amount_cents, order.snacks_cents, order.total_cents
                ),
                order_ref=order.reference
            )
        );
    }
    # Failed payments owed back are not sales. Count each confirmed order's snack
    # snapshots once, even if it has more than one ledger entry.
    refunded = {
        e.intent_id
        for e in entries
        if e.kind == "refund_due"
    };
    paid_at = sorted(
        [
            e.created_at
            for e in entries
            if e.kind == "payment"
                and e.amount_cents > 0
                and e.intent_id not in refunded
        ]
    );
    if order.status == "confirmed" and paid_at {
        for line in order.snack_lines {
            pid = str(line.get("product_id", ""));
            name = str(line.get("name", "Snack"));
            into.snacks.append(
                SnackSold(
                    venue_id=venue_id,
                    product_id=pid,
                    variant_id=str(line.get("variant_id", "")),
                    name=name,
                    quantity=int(line.get("quantity", 0)),
                    line_cents=int(line.get("line_cents", 0)),
                    sold_at=paid_at[0],
                    product_name=products.get(pid, name)
                )
            );
        }
    }
}

def cinema_records(cinema: Tenant) -> Records {
    # Showtimes, their orders, and venue-owned snacks-only orders (the sales report
    # and the staff home page).
    found = Records();
    titles: dict[str, str] = {};
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        products = {node_id(p): p.name for p in [cinema-->[?:SnackProduct]]};
        for m in [cinema-->[?:Movie]] {
            titles[node_id(m)] = m.title;
        }
        for venue in [cinema-->[?:Venue]] {
            vid = node_id(venue);
            found.venues[vid] = venue.name;
            for order in [venue-->[?:Order]] {
                _of_order(order, found, vid, products);
            }
            for screen in [venue-->[?:Auditorium]] {
                for s in [screen-->[?:Screening]] {
                    if s.state in NEVER_ON_SALE {
                        continue;
                    }
                    seats = [
                        x
                        for x in [s-->[?:SeatSlot]]
                        if x.state != SeatState.NOT_FOR_SALE.value
                    ];
                    found.shows.append(
                        Show(
                            screening_id=node_id(s),
                            venue_id=node_id(venue),
                            venue=venue.name,
                            screen_id=node_id(screen),
                            screen=screen.name,
                            movie_id=s.movie_id,
                            movie=titles.get(s.movie_id, ""),
                            starts_at=s.starts_at,
                            seats_on_sale=len(seats),
                            state=s.state
                        )
                    );
                    for order in [s-->[?:Order]] {
                        _of_order(order, found, vid, products);
                    }
                }
            }
        }
    } finally {
        restore(me);
    }
    return found;
}

def _low_stock(cinema: Tenant, venue_id: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Current inventory, not a historical count. Called after financial_reports.read.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    try {
        venues = [
            v
            for v in [cinema-->[?:Venue]]
            if not venue_id or node_id(v) == venue_id
        ];
        for p in [cinema-->[?:SnackProduct]] {
            if p.status == "archived" {
                continue;
            }
            for v in [p-->[?:SnackVariant]] {
                if not v.track_stock {
                    continue;
                }
                for venue in venues {
                    vid = node_id(venue);
                    if vid in p.off_at or vid in v.off_at {
                        continue;
                    }
                    level = level_of(cinema, v, vid);
                    few = level["available"] > 0 and level["available"] <= FEW_LEFT;
                    if level["status"] == "ok" and not few {
                        continue;
                    }
                    # Reports and the sales menu share the same "Few left" cutoff.
                    # A cinema's configured threshold can add alerts, but a zero/default
                    # threshold must not hide stock the menu already calls scarce.
                    status = "low"
                        if few and level["status"] == "ok"
                        else level["status"];
                    label = p.name
                        if p.kind != "variants"
                        else f"{p.name} · {variant_label(v.option_values)}";
                    rows.append(
                        {
                            "venue_id": vid,
                            "venue": venue.name,
                            "product_id": node_id(p),
                            "variant_id": node_id(v),
                            "name": label,
                            ** level,
                            "status": status,
                            "few_left": few
                        }
                    );
                }
            }
        }
    } finally {
        restore(me);
    }
    def by_venue(row: dict[str, any]) -> tuple[str, int, str, str] {  # jac:ignore[W1037]
        return (
            str(row["venue"]),
            int(row["available"]),
            str(row["name"]),
            str(row["variant_id"])
        );
    }
    return sorted(rows, key=by_venue);
}

def _sales_report(
    tenant: str, date_from: str, date_to: str, venue_id: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ);
    if venue_id and find_venue(scope.tenant, venue_id) is None {
        raise NotFound();
    }
    timezone = cinema_timezone(scope.tenant);
    today = now().astimezone(ZoneInfo(timezone)).date().isoformat();
    try {
        # No dates: today where the cinema is (the dashboard's first request).
        period = period_of(timezone, date_from or today, date_to or today);
    } except ValueError {
        raise Refused(
            "bad_period",
            "Choose a start and an end date, the end not before the start, at most a year apart."
        );
    }
    found = cinema_records(scope.tenant);
    result = counted(
        period,
        found.shows,
        found.tickets,
        found.money,
        venue_id,
        found.snacks,
        found.venues,
        found.fees
    );
    # The same number of days just before, for the headline's trend (owner, 2026-10-27).
    days = (period.last - period.first).days + 1;
    before = Period(
        timezone=timezone,
        first=period.first - timedelta(days=days),
        last=period.first - timedelta(days=1)
    );
    earlier = counted(
        before,
        found.shows,
        found.tickets,
        found.money,
        venue_id,
        found.snacks,
        found.venues
    );
    result["previous"] = {
        "first": before.first.isoformat(),
        "last": before.last.isoformat(),
        "days": days,
        "net_cents": earlier["takings"]["net_cents"],
        "tickets_sold": earlier["attendance"]["tickets_sold"]
    };
    result["snacks"]["low_stock"] = _low_stock(scope.tenant, venue_id);
    result["snacks"]["stock_as_of"] = now().isoformat();
    return {
        "ok": True,
        "today": today,
        "currency": CURRENCY,
        "venues": [
            {"venue_id": vid, "name": name} for (vid, name) in found.venues.items()
        ],
        "report": result
    };
}

def:protect sales_report(
    tenant: str, date_from: str, date_to: str, venue_id: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _sales_report(tenant, date_from, date_to, venue_id); }  # jac:ignore[W1037]
    );
}
