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
- the ledger entries of its orders: a payment recorded by a member of staff is a box
  office sale.
"""

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
import from core.reporting.aggregates {
    Show,
    SoldTicket,
    Money,
    period_of,
    sales_report as counted
}

glob READ: str = "financial_reports.read",
     NEVER_ON_SALE: list[str] = ["draft", "scheduled"];

obj Records {
    has shows: list[Show] = [],
        tickets: list[SoldTicket] = [],
        money: list[Money] = [];
}

def _of_order(order: Order, into: Records) {
    # The order's tickets and ledger entries. Call as the cinema's principal.
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
    for e in [order-->[?:LedgerEntry]] {
        into.money.append(
            Money(
                screening_id=order.screening_id,
                kind=e.kind,
                amount_cents=e.amount_cents,
                taken_at=e.created_at,
                method=e.method,
                counter=bool(e.recorded_by)
            )
        );
    }
}

def _records(cinema: Tenant) -> Records {
    # Every showtime the cinema put on sale, with its tickets and money.
    found = Records();
    titles: dict[str, str] = {};
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        for m in [cinema-->[?:Movie]] {
            titles[node_id(m)] = m.title;
        }
        for venue in [cinema-->[?:Venue]] {
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
                        _of_order(order, found);
                    }
                }
            }
        }
    } finally {
        restore(me);
    }
    return found;
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
    found = _records(scope.tenant);
    return {
        "ok": True,
        "today": today,
        "currency": CURRENCY,
        "report": counted(period, found.shows, found.tickets, found.money, venue_id)
    };
}

def:priv sales_report(
    tenant: str, date_from: str, date_to: str, venue_id: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _sales_report(tenant, date_from, date_to, venue_id); }  # jac:ignore[W1037]
    );
}
