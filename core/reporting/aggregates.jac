"""The sales report's numbers (P7.1, architecture §76, §77; ADR-0026), from plain records.

report_api.jac collects the records from the cinema's graph; this module only counts, so
its numbers are tested against fixtures with known answers.

- Takings count on the cinema's local day the money was taken: the ledger's entries.
  gross is the payments; refunds are the money owed or paid back (refund_due, refund,
  reversal), shown as a positive amount; adjustments are added as they are; net is the
  sum of every entry. Payments split by method (M-Pesa, cash) and by channel (online,
  or the box office: an entry recorded by a member of staff).
- Attendance counts on the cinema's local day the showtime starts, cancelled showtimes
  left out: tickets sold (issued or used; refunded and voided ones aren't), scanned
  (used), the seats on sale, and the revenue of the tickets sold (their prices,
  service fee included).
- by_day lists every day of the period: its net takings and the tickets sold for its
  showtimes; chart groups it by week past 31 days (the dashboard's chart, P7.3).
- The drill-down goes venue, screen, movie, showtime, each with the attendance numbers;
  a venue also has its takings. Top movies and showtimes are by revenue.

Amounts are in cents; percentages and tickets per show have one decimal.
"""

import from datetime { date, datetime, timedelta }
import from zoneinfo { ZoneInfo }

glob MAX_DAYS: int = 366,
     CHART_DAYS: int = 31,
     TOP: int = 5,
     SOLD: list[str] = ["issued", "used"],
     USED: str = "used",
     CANCELLED: str = "cancelled",
     REFUNDS: list[str] = ["refund_due", "refund", "reversal"];

obj Period {
    # The cinema's local days first..last, both included.
    has timezone: str,
        first: date,
        last: date;

    def day_of(stamp: str) -> date {
        # The cinema's local day of the UTC ISO time `stamp`.
        return datetime.fromisoformat(stamp).astimezone(ZoneInfo(self.timezone)).date();
    }

    def covers(stamp: str) -> bool {
        # Whether the UTC ISO time `stamp` falls on one of the period's local days.
        return self.first <= self.day_of(stamp) <= self.last;
    }

    def days -> list[date] {
        return [
            self.first + timedelta(days=n)
            for n in range((self.last - self.first).days + 1)
        ];
    }
}

obj Show {
    has screening_id: str,
        venue_id: str,
        venue: str,
        screen_id: str,
        screen: str,
        movie_id: str,
        movie: str,
        starts_at: str,
        seats_on_sale: int,
        state: str;
}

obj SoldTicket {
    # price_cents is what the ticket cost, its service fee (fee_cents) included.
    has screening_id: str,
        status: str,
        price_cents: int,
        fee_cents: int = 0;
}

obj Money {
    # A ledger entry: counter is True when a member of staff took it at the box office.
    has screening_id: str,
        kind: str,
        amount_cents: int,
        taken_at: str,
        method: str = "",
        counter: bool = False;
}

def period_of(timezone: str, date_from: str, date_to: str) -> Period {
    # The period from `date_from` to `date_to` (YYYY-MM-DD, the cinema's local days).
    # Raises ValueError for dates that aren't, an end before the start, or more than
    # MAX_DAYS days.
    first = date.fromisoformat(date_from.strip());
    last = date.fromisoformat(date_to.strip());
    if len(date_from.strip()) != 10 or len(date_to.strip()) != 10 {
        raise ValueError("dates are YYYY-MM-DD");
    }
    if last < first {
        raise ValueError("the period ends before it starts");
    }
    if (last - first).days + 1 > MAX_DAYS {
        raise ValueError(f"a period is at most {MAX_DAYS} days");
    }
    return Period(timezone=timezone, first=first, last=last);
}

def _share(part: int, whole: int) -> float {
    # part as a percentage of whole, one decimal; 0.0 when there's no whole.
    return round(100 * part / whole, 1) if whole else 0.0;
}

def _per(total: int, count: int) -> int {
    # total / count rounded to the nearest cent; 0 when there's nothing to divide by.
    return round(total / count) if count else 0;
}

def _attendance(
    shows: list[Show], sold: dict[str, list[SoldTicket]]
) -> dict[str, any] {  # jac:ignore[W1037]
    # The attendance numbers of `shows`, from each showtime's sold tickets.
    tickets = [t for s in shows for t in sold.get(s.screening_id, [])];
    revenue = sum([t.price_cents for t in tickets]);
    seats = sum([s.seats_on_sale for s in shows]);
    return {
        "showtimes": len(shows),
        "tickets_sold": len(tickets),
        "tickets_scanned": len(
            [
                t
                for t in tickets
                if t.status == USED
            ]
        ),
        "seats_on_sale": seats,
        "occupancy_pct": _share(len(tickets), seats),
        "tickets_per_show": round(len(tickets) / len(shows), 1) if shows else 0.0,
        "ticket_revenue_cents": revenue,
        "service_fees_cents": sum([t.fee_cents for t in tickets]),
        "average_ticket_cents": _per(revenue, len(tickets)),
        "revenue_per_seat_cents": _per(revenue, seats)
    };
}

def _takings(entries: list[Money]) -> dict[str, int] {
    payments = [
        e
        for e in entries
        if e.kind == "payment"
    ];
    return {
        "gross_cents": sum([e.amount_cents for e in payments]),
        "refunds_cents": -sum(
            [
                e.amount_cents
                for e in entries
                if e.kind in REFUNDS
            ]
        ),
        "adjustments_cents": sum(
            [
                e.amount_cents
                for e in entries
                if e.kind == "adjustment"
            ]
        ),
        "net_cents": sum([e.amount_cents for e in entries]),
        "mpesa_cents": sum(
            [
                e.amount_cents
                for e in payments
                if e.method == "mpesa"
            ]
        ),
        "cash_cents": sum(
            [
                e.amount_cents
                for e in payments
                if e.method == "cash"
            ]
        ),
        "online_cents": sum(
            [
                e.amount_cents
                for e in payments
                if not e.counter
            ]
        ),
        "counter_cents": sum(
            [
                e.amount_cents
                for e in payments
                if e.counter
            ]
        )
    };
}

def _grouped(shows: list[Show], key: any) -> list[list[Show]] {  # jac:ignore[W1037]
    # `shows` in groups sharing key(show), in order of first appearance.
    groups: dict[str, list[Show]] = {};
    for s in shows {
        groups.setdefault(key(s), []).append(s);
    }
    return list(groups.values());
}

def _by_name(rows: list[dict[str, any]], field: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    def name(r: dict[str, any]) -> str {  # jac:ignore[W1037]
        return str(r[field]).lower();
    }
    return sorted(rows, key=name);
}

def _ranked(rows: list[dict[str, any]], name: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The TOP rows by revenue, then tickets; ties by name.
    def rank(r: dict[str, any]) -> tuple[int, int, str] {  # jac:ignore[W1037]
        return (-int(r["revenue_cents"]), -int(r["tickets"]), str(r[name]).lower());
    }
    return sorted(rows, key=rank)[:TOP];
}

def _drill_down(
    shows: list[Show], sold: dict[str, list[SoldTicket]], net_by_venue: dict[str, int]
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    by_time = sorted(shows, key=lambda (s: Show) -> str { return s.starts_at; });  # jac:ignore[W1037]
    venues: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for at_venue in _grouped(by_time, lambda (s: Show) -> str { return s.venue_id; }) {  # jac:ignore[W1037]
        screens: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for on_screen in _grouped(
            at_venue, lambda (s: Show) -> str { return s.screen_id; }
        ) {  # jac:ignore[W1037]
            movies: list[dict[str, any]] = [];  # jac:ignore[W1037]
            for of_movie in _grouped(
                on_screen, lambda (s: Show) -> str { return s.movie_id; }
            ) {  # jac:ignore[W1037]
                times = [
                    {
                        "screening_id": s.screening_id,
                        "starts_at": s.starts_at,
                        ** _attendance([s], sold)
                    } for s in of_movie
                ];
                movies.append(
                    {
                        "movie_id": of_movie[0].movie_id,
                        "title": of_movie[0].movie,
                        ** _attendance(of_movie, sold),
                        "showtimes": times
                    }
                );
            }
            screens.append(
                {
                    "screen_id": on_screen[0].screen_id,
                    "name": on_screen[0].screen,
                    ** _attendance(on_screen, sold),
                    "movies": _by_name(movies, "title")
                }
            );
        }
        venue_id = at_venue[0].venue_id;
        venues.append(
            {
                "venue_id": venue_id,
                "name": at_venue[0].venue,
                "takings_net_cents": net_by_venue.get(venue_id, 0),
                ** _attendance(at_venue, sold),
                "screens": _by_name(screens, "name")
            }
        );
    }
    return _by_name(venues, "name");
}

def _by_day(
    period: Period,
    shows: list[Show],
    sold: dict[str, list[SoldTicket]],
    taken: list[Money]
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Every day of the period, first to last: the net takings of the money taken that
    # day, and the tickets sold for the showtimes starting that day.
    net: dict[str, int] = {};
    for m in taken {
        key = period.day_of(m.taken_at).isoformat();
        net[key] = net.get(key, 0) + m.amount_cents;
    }
    tickets: dict[str, int] = {};
    for s in shows {
        key = period.day_of(s.starts_at).isoformat();
        tickets[key] = tickets.get(key, 0) + len(sold.get(s.screening_id, []));
    }
    return [
        {
            "day": d.isoformat(),
            "takings_net_cents": net.get(d.isoformat(), 0),
            "tickets_sold": tickets.get(d.isoformat(), 0)
        } for d in period.days()
    ];
}

def _chart(days: list[dict[str, any]]) -> dict[str, any] {  # jac:ignore[W1037]
    # The dashboard's chart: a point a day up to CHART_DAYS days, else a point a week,
    # weeks counted from the period's first day (the last one may be shorter).
    if len(days) <= CHART_DAYS {
        return {
            "unit": "day",
            "points": [
                {
                    "start": d["day"],
                    "takings_net_cents": d["takings_net_cents"],
                    "tickets_sold": d["tickets_sold"]
                } for d in days
            ]
        };
    }
    points: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for at in range(0, len(days), 7) {
        week = days[at:at + 7];
        points.append(
            {
                "start": week[0]["day"],
                "takings_net_cents": sum([d["takings_net_cents"] for d in week]),
                "tickets_sold": sum([d["tickets_sold"] for d in week])
            }
        );
    }
    return {"unit": "week", "points": points};
}

def sales_report(
    period: Period,
    shows: list[Show],
    tickets: list[SoldTicket],
    money: list[Money],
    venue_id: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # The report for `period`, of one venue's showtimes and money when `venue_id` is
    # given. `shows` are every showtime the tickets and money belong to.
    show_of = {s.screening_id: s for s in shows};
    def in_venue(sid: str) -> bool {
        found = show_of.get(sid);
        return not venue_id or (found is not None and found.venue_id == venue_id);
    }
    counted = [
        s
        for s in shows
        if s.state != CANCELLED
            and period.covers(s.starts_at)
            and in_venue(s.screening_id)
    ];
    sold: dict[str, list[SoldTicket]] = {};
    for t in tickets {
        if t.status in SOLD {
            sold.setdefault(t.screening_id, []).append(t);
        }
    }
    taken = [
        m
        for m in money
        if period.covers(m.taken_at) and in_venue(m.screening_id)
    ];
    net_by_venue: dict[str, int] = {};
    for m in taken {
        found = show_of.get(m.screening_id);
        if found is not None {
            net_by_venue[found.venue_id] = net_by_venue.get(found.venue_id, 0)
                + m.amount_cents;
        }
    }
    movie_rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for of_movie in _grouped(counted, lambda (s: Show) -> str { return s.movie_id; }) {  # jac:ignore[W1037]
        shown = _attendance(of_movie, sold);
        movie_rows.append(
            {
                "movie_id": of_movie[0].movie_id,
                "title": of_movie[0].movie,
                "tickets": shown["tickets_sold"],
                "revenue_cents": shown["ticket_revenue_cents"]
            }
        );
    }
    show_rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in counted {
        shown = _attendance([s], sold);
        show_rows.append(
            {
                "screening_id": s.screening_id,
                "movie": s.movie,
                "venue": s.venue,
                "screen": s.screen,
                "starts_at": s.starts_at,
                "tickets": shown["tickets_sold"],
                "revenue_cents": shown["ticket_revenue_cents"],
                "occupancy_pct": shown["occupancy_pct"]
            }
        );
    }
    days = _by_day(period, counted, sold, taken);
    return {
        "first": period.first.isoformat(),
        "last": period.last.isoformat(),
        "timezone": period.timezone,
        "takings": _takings(taken),
        "attendance": _attendance(counted, sold),
        "top_movies": _ranked(movie_rows, "title"),
        "top_showtimes": _ranked(show_rows, "movie"),
        "venues": _drill_down(counted, sold, net_by_venue),
        "by_day": days,
        "chart": _chart(days)
    };
}
