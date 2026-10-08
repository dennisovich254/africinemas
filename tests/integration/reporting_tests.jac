"""P7.1: the sales report against real sales (core/reporting/report_api.jac).

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa. Nova's five-seat
screen at Westgate shows Rafiki two days ahead, each Adult ticket KES 930 (800, a 100
evening extra and a 30 service fee). Anna buys A1 and A2 online with M-Pesa; at the box
office the agent sells A3 and A4 for cash and A5 with M-Pesa. The report counts the
money on the day it was taken (today) and the tickets on the day of the showtime, so a
period from yesterday to three days ahead has both. Owners and finance managers may read
it; box office agents and ushers may not.
"""

import uuid;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup {
    paying_cinema,
    hire,
    fresh_phone,
    paid,
    settle
}

glob TICKET: int = 93000;

def _counter_order(app: Served, screening: str, labels: list[str]) -> str {
    # The agent holds `labels` for a walk-in customer and orders an Adult each; returns
    # the counter holder id.
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": "nova", "screening_id": screening, "holder": holder};
    assert browse(app, "hold_seats", {** where, "labels": labels})["ok"];
    ordered = browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": x, "ticket_type": "ADULT"} for x in labels]
        }
    );
    assert ordered["ok"] , ordered;
    return holder;
}

def _sold_out(app: Served, screening: str) {
    # Anna's two seats online, two for cash and one with M-Pesa at the counter.
    paid(app, screening);
    cash = _counter_order(app, screening, ["A3", "A4"]);
    sold = app.call(
        "agent",
        "sell_for_cash",
        {"tenant": "nova", "screening_id": screening, "holder": cash, "email": ""}
    );
    assert sold["ok"] , sold;
    mpesa = _counter_order(app, screening, ["A5"]);
    started = app.call(
        "agent",
        "sell_with_mpesa",
        {
            "tenant": "nova",
            "screening_id": screening,
            "holder": mpesa,
            "phone": fresh_phone(),
            "email": ""
        }
    );
    assert started["ok"] , started;
    settle(app, screening, started["payment"]["reference"]);
}

def _days(start: int, end: int) -> dict[str, str] {
    # From `start` to `end` days after today, Nairobi's today: the cinema's days.
    today = datetime.now(ZoneInfo("Africa/Nairobi")).date();
    return {
        "date_from": (today + timedelta(days=start)).isoformat(),
        "date_to": (today + timedelta(days=end)).isoformat()
    };
}

def _report(
    app: Served, who: str, venue_id: str = "", start: int = -1, end: int = 3
) -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "sales_report",
        {"tenant": "nova", "venue_id": venue_id, ** _days(start, end)}
    );
}

test "the report matches the day's sales: online and counter, M-Pesa and cash" {
    (app, nova, screening) = paying_cinema(["agent"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        _sold_out(app, screening);
        got = _report(app, "owner");
        assert got["ok"] , got;
        sales = got["report"];
        assert sales["takings"]
            == {
                "gross_cents": 5 * TICKET,
                "refunds_cents": 0,
                "adjustments_cents": 0,
                "net_cents": 5 * TICKET,
                "mpesa_cents": 3 * TICKET,
                "cash_cents": 2 * TICKET,
                "online_cents": 2 * TICKET,
                "counter_cents": 3 * TICKET
            } , sales["takings"];
        shown = sales["attendance"];
        assert [
            shown["showtimes"],
            shown["tickets_sold"],
            shown["tickets_scanned"],
            shown["seats_on_sale"],
            shown["occupancy_pct"]
        ]
            == [1, 5, 0, 5, 100.0] , shown;
        assert shown["ticket_revenue_cents"] == 5 * TICKET;
        assert shown["service_fees_cents"] == 5 * 3000;
        assert shown["average_ticket_cents"] == TICKET;
        assert [[m["title"], m["tickets"]] for m in sales["top_movies"]]
            == [["Rafiki", 5]];
        assert [s["screening_id"] for s in sales["top_showtimes"]] == [screening];
        venues = sales["venues"];
        assert [[v["name"], v["takings_net_cents"]] for v in venues]
            == [["Westgate", 5 * TICKET]];
        showtimes = venues[0]["screens"][0]["movies"][0]["showtimes"];
        assert [[s["screening_id"], s["tickets_sold"]] for s in showtimes]
            == [[screening, 5]];
        # The venue's own report is the same; days with neither money nor the showtime
        # have nothing.
        assert _report(app, "owner", nova.venue)["report"]["takings"]
            == sales["takings"];
        empty = _report(app, "owner", "", -10, -5)["report"];
        assert empty["takings"]["net_cents"] == 0;
        assert empty["attendance"]["tickets_sold"] == 0 and empty["venues"] == [];
        # Today only: the money, but not the showtime two days ahead.
        today = _report(app, "owner", "", 0, 0)["report"];
        assert today["takings"]["net_cents"] == 5 * TICKET;
        assert today["attendance"]["showtimes"] == 0;
    } finally {
        app.close();
    }
}

test "finance managers may read the report; box office agents and ushers may not" {
    (app, nova, screening) = paying_cinema(["agent", "usher", "finance"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "usher", "usher", nova.venue);
        hire(app, "finance", "finance_manager", "");
        paid(app, screening);
        assert code_of(_report(app, "agent")) == "forbidden";
        assert code_of(_report(app, "usher")) == "forbidden";
        read = _report(app, "finance");
        assert read["ok"] , read;
        assert read["report"]["takings"]["net_cents"] == 2 * TICKET;
    } finally {
        app.close();
    }
}

test "a bad period or another cinema's venue is refused" {
    (app, nova, screening) = paying_cinema([]);
    try {
        assert code_of(_report(app, "owner", "", 3, -1)) == "bad_period";
        assert code_of(_report(app, "owner", "", -400, 0)) == "bad_period";
        garbled = app.call(
            "owner",
            "sales_report",
            {"tenant": "nova", "date_from": "yesterday", "date_to": "today"}
        );
        assert code_of(garbled) == "bad_period";
        assert code_of(_report(app, "owner", "not-a-venue")) == "not_found";
        assert code_of(_report(app, "owner", screening)) == "not_found";
    } finally {
        app.close();
    }
}
