"""P7.1: the sales report's numbers (core/reporting/aggregates.jac), on a fixture with
known answers.

Money counts on the cinema's local day it was taken (the ledger's entries); attendance
on the local day the showtime starts (ADR-0026). Two venues, three movies, in Nairobi
(UTC+3), for 5 and 6 October 2026:

- CBD, Screen 1 (10 seats each show): Rafiki on the 5th (three tickets sold, two of them
  scanned, one refunded and one voided), Supa Modo on the 6th (two), a cancelled Nairobi
  Half Life on the 5th, and a Supa Modo at 23:59 on the 4th (outside).
- Mall, Hall A (20 seats): Rafiki at 23:30 on the 6th (five), and Nairobi Half Life at
  00:30 on the 7th (outside).
"""

import from core.reporting.aggregates {
    Period,
    Show,
    SoldTicket,
    Money,
    period_of,
    sales_report
}

glob NAIROBI: str = "Africa/Nairobi";

def _show(
    sid: str,
    venue: str,
    movie: str,
    starts_at: str,
    seats: int,
    state: str = "published"
) -> Show {
    places = {"cbd": ("CBD", "x1", "Screen 1"), "mall": ("Mall", "y1", "Hall A")};
    titles = {"m1": "Rafiki", "m2": "Supa Modo", "m3": "Nairobi Half Life"};
    (venue_name, screen_id, screen_name) = places[venue];
    return Show(
        screening_id=sid,
        venue_id=venue,
        venue=venue_name,
        screen_id=screen_id,
        screen=screen_name,
        movie_id=movie,
        movie=titles[movie],
        starts_at=starts_at,
        seats_on_sale=seats,
        state=state
    );
}

def _shows -> list[Show] {
    return [
        _show("s1", "cbd", "m1", "2026-10-05T16:00:00+00:00", 10),
        _show("s2", "cbd", "m2", "2026-10-06T15:00:00+00:00", 10),
        _show("s3", "mall", "m1", "2026-10-06T20:30:00+00:00", 20),
        _show("s4", "mall", "m3", "2026-10-06T21:30:00+00:00", 20),
        _show("s5", "cbd", "m2", "2026-10-04T20:59:00+00:00", 10),
        _show("s6", "cbd", "m3", "2026-10-05T10:00:00+00:00", 10, "cancelled")
    ];
}

def _tickets -> list[SoldTicket] {
    def made(sid: str, status: str, price: int, fee: int) -> SoldTicket {
        return SoldTicket(
            screening_id=sid, status=status, price_cents=price, fee_cents=fee
        );
    }
    return [
        made("s1", "used", 930, 30),
        made("s1", "used", 930, 30),
        made("s1", "issued", 930, 30),
        made("s1", "refunded", 930, 30),
        made("s1", "voided", 930, 30),
        made("s2", "issued", 500, 30),
        made("s2", "issued", 500, 30),
        made("s3", "issued", 600, 0),
        made("s3", "issued", 600, 0),
        made("s3", "issued", 600, 0),
        made("s3", "issued", 600, 0),
        made("s3", "issued", 600, 0),
        made("s4", "issued", 930, 30),
        made("s5", "issued", 930, 30)
    ];
}

def _money -> list[Money] {
    def taking(
        sid: str,
        kind: str,
        amount: int,
        taken_at: str,
        method: str = "",
        counter: bool = False
    ) -> Money {
        return Money(
            screening_id=sid,
            kind=kind,
            amount_cents=amount,
            method=method,
            counter=counter,
            taken_at=taken_at
        );
    }
    return [
        # 00:30 on the 5th in Nairobi: in.
        taking("s1", "payment", 2790, "2026-10-04T21:30:00+00:00", "mpesa"),
        taking("s2", "payment", 1000, "2026-10-06T12:00:00+00:00", "cash", True),
        # 23:59 on the 6th: in.
        taking("s3", "payment", 3000, "2026-10-06T20:59:00+00:00", "mpesa", True),
        # 00:00 on the 7th: out.
        taking("s4", "payment", 930, "2026-10-06T21:00:00+00:00", "mpesa"),
        taking("s1", "payment", 930, "2026-10-05T08:00:00+00:00", "mpesa"),
        taking("s1", "refund_due", -930, "2026-10-05T09:00:00+00:00"),
        taking("s6", "payment", 500, "2026-10-05T07:00:00+00:00", "mpesa"),
        taking("s6", "reversal", -500, "2026-10-05T07:30:00+00:00"),
        taking("s2", "adjustment", -100, "2026-10-06T10:00:00+00:00")
    ];
}

def _report(venue_id: str = "") -> dict[str, any] {  # jac:ignore[W1037]
    return sales_report(
        period_of(NAIROBI, "2026-10-05", "2026-10-06"),
        _shows(),
        _tickets(),
        _money(),
        venue_id
    );
}

test "takings: gross, refunds and adjustments, net, by method and by channel" {
    takings = _report()["takings"];
    assert takings
        == {
            "gross_cents": 8220,
            "refunds_cents": 1430,
            "adjustments_cents": -100,
            "net_cents": 6690,
            "mpesa_cents": 7220,
            "cash_cents": 1000,
            "online_cents": 4220,
            "counter_cents": 4000
        } , takings;
}

test "attendance: the showtimes starting in the period, cancelled ones left out" {
    shown = _report()["attendance"];
    assert shown
        == {
            "showtimes": 3,
            "tickets_sold": 10,
            "tickets_scanned": 2,
            "seats_on_sale": 40,
            "occupancy_pct": 25.0,
            "tickets_per_show": 3.3,
            "ticket_revenue_cents": 6790,
            "service_fees_cents": 150,
            "average_ticket_cents": 679,
            "revenue_per_seat_cents": 170
        } , shown;
}

test "top movies and top showtimes, by revenue" {
    got = _report();
    assert [[m["title"], m["tickets"], m["revenue_cents"]] for m in got["top_movies"]]
        == [["Rafiki", 8, 5790], ["Supa Modo", 2, 1000]] , got["top_movies"];
    assert [
        [s["screening_id"], s["tickets"], s["revenue_cents"], s["occupancy_pct"]]
        for s in got["top_showtimes"]
    ]
        == [["s3", 5, 3000, 25.0], ["s1", 3, 2790, 30.0], ["s2", 2, 1000, 20.0]];
    top = got["top_showtimes"][0];
    assert [top["movie"], top["venue"], top["screen"]] == ["Rafiki", "Mall", "Hall A"];
}

test "the drill-down: venue, screen, movie, showtime, adding up to the whole cinema" {
    got = _report();
    venues = got["venues"];
    assert [
        [
            v["name"],
            v["takings_net_cents"],
            v["tickets_sold"],
            v["ticket_revenue_cents"]
        ] for v in venues
    ]
        == [["CBD", 3690, 5, 3790], ["Mall", 3000, 5, 3000]] , venues;
    assert sum([v["takings_net_cents"] for v in venues]) == got["takings"]["net_cents"];
    assert sum([v["ticket_revenue_cents"] for v in venues])
        == got["attendance"]["ticket_revenue_cents"];
    cbd = venues[0];
    assert cbd["occupancy_pct"] == 25.0 and cbd["seats_on_sale"] == 20;
    assert [s["name"] for s in cbd["screens"]] == ["Screen 1"];
    movies = cbd["screens"][0]["movies"];
    assert [[m["title"], m["tickets_sold"]] for m in movies]
        == [["Rafiki", 3], ["Supa Modo", 2]];
    rafiki = movies[0]["showtimes"];
    assert [
        [s["screening_id"], s["tickets_sold"], s["tickets_scanned"]] for s in rafiki
    ]
        == [["s1", 3, 2]];
}

test "one venue: everything counts that venue's showtimes and money only" {
    got = _report("mall");
    assert got["takings"]["gross_cents"] == 3000;
    assert got["takings"]["net_cents"] == 3000;
    assert got["takings"]["counter_cents"] == 3000;
    assert got["attendance"]["tickets_sold"] == 5;
    assert got["attendance"]["seats_on_sale"] == 20;
    assert [m["title"] for m in got["top_movies"]] == ["Rafiki"];
    assert [v["name"] for v in got["venues"]] == ["Mall"];
}

test "by day: net takings on the day taken, tickets on the showtime's day, every day listed" {
    assert _report()["by_day"]
        == [
            {"day": "2026-10-05", "takings_net_cents": 2790, "tickets_sold": 3},
            {"day": "2026-10-06", "takings_net_cents": 3900, "tickets_sold": 7}
        ] , _report()["by_day"];
    assert _report("mall")["by_day"]
        == [
            {"day": "2026-10-05", "takings_net_cents": 0, "tickets_sold": 0},
            {"day": "2026-10-06", "takings_net_cents": 3000, "tickets_sold": 5}
        ];
    assert sum([d["takings_net_cents"] for d in _report()["by_day"]])
        == _report()["takings"]["net_cents"];
}

test "the chart: one point a day up to 31 days, else one a week from the first day" {
    short = _report()["chart"];
    assert short["unit"] == "day";
    assert [
        [p["start"], p["takings_net_cents"], p["tickets_sold"]] for p in short["points"]
    ]
        == [["2026-10-05", 2790, 3], ["2026-10-06", 3900, 7]];
    month = sales_report(
        period_of(NAIROBI, "2026-10-01", "2026-10-31"), _shows(), _tickets(), _money()
    )["chart"];
    assert month["unit"] == "day" and len(month["points"]) == 31;
    long = sales_report(
        period_of(NAIROBI, "2026-10-01", "2026-11-15"), _shows(), _tickets(), _money()
    )["chart"];
    assert long["unit"] == "week";
    # 46 days: six whole weeks and a last week of four days.
    assert [p["start"] for p in long["points"]]
        == [
            "2026-10-01",
            "2026-10-08",
            "2026-10-15",
            "2026-10-22",
            "2026-10-29",
            "2026-11-05",
            "2026-11-12"
        ];
    first = long["points"][0];
    # The week of 1-7 October holds everything: the 5th and 6th (6,690 and 10 tickets),
    # the payment taken just after midnight on the 7th (930) and the shows at 23:59 on
    # the 4th and 00:30 on the 7th (a ticket each).
    assert [first["takings_net_cents"], first["tickets_sold"]]
        == [6690 + 930, 10 + 1 + 1];
    assert sum([p["takings_net_cents"] for p in long["points"]])
        == sales_report(
            period_of(NAIROBI, "2026-10-01", "2026-11-15"),
            _shows(),
            _tickets(),
            _money()
        )["takings"]["net_cents"];
}

test "nothing sold: zeros, no division by zero, empty lists" {
    got = sales_report(period_of(NAIROBI, "2026-10-05", "2026-10-06"), [], [], []);
    assert got["takings"]["net_cents"] == 0;
    shown = got["attendance"];
    assert shown["showtimes"] == 0 and shown["occupancy_pct"] == 0.0;
    assert shown["average_ticket_cents"] == 0 and shown["tickets_per_show"] == 0.0;
    assert shown["revenue_per_seat_cents"] == 0;
    assert got["top_movies"] == [] and got["venues"] == [];
    assert [d["takings_net_cents"] + d["tickets_sold"] for d in got["by_day"]]
        == [0, 0];
}

test "a period is one to 366 of the cinema's days, first to last" {
    one = period_of(NAIROBI, "2026-10-05", "2026-10-05");
    assert one.covers("2026-10-04T21:00:00+00:00");
    assert one.covers("2026-10-05T20:59:59+00:00");
    assert not one.covers("2026-10-05T21:00:00+00:00");
    assert not one.covers("2026-10-04T20:59:59+00:00");
    period_of(NAIROBI, "2025-10-06", "2026-10-06");
    for (first, last) in [
        ("2026-10-06", "2026-10-05"),
        ("2026-13-01", "2026-13-02"),
        ("", "2026-10-05"),
        ("05/10/2026", "06/10/2026"),
        ("2025-10-05", "2026-10-06")
    ] {
        try {
            period_of(NAIROBI, first, last);
            assert False , f"{first}..{last} was accepted";
        } except ValueError {}
    }
}
