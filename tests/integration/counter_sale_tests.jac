"""P6.5: a walk-in sale at the box office, paid in cash or with M-Pesa at the counter.

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa. The agent books
for the customer through the storefront's own hold and order endpoints, under a counter
holder id, then takes the money: sell_for_cash confirms the order at once (seats sold,
tickets issued) with a ledger entry of the whole amount, method "cash", recorded by the
agent; sell_with_mpesa sends the customer the M-Pesa prompt, an email being optional at
the counter. Selling needs bookings.create at the showtime's venue: an agent limited to
another venue, or an usher, is refused. An order is paid once.
"""

import os;
import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { paying_cinema, hire, fresh_phone, settle }

def _counter_order(app: Served, screening: str) -> str {
    # The agent holds A3 and A4 for a walk-in customer and orders two Adults; returns
    # the counter holder id.
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": "nova", "screening_id": screening, "holder": holder};
    assert browse(app, "hold_seats", {** where, "labels": ["A3", "A4"]})["ok"];
    ordered = browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [
                {"seat_label": "A3", "ticket_type": "ADULT"},
                {"seat_label": "A4", "ticket_type": "ADULT"}
            ]
        }
    );
    assert ordered["ok"] , ordered;
    return holder;
}

def _cash(app: Served, who: str, screening: str, holder: str, email: str = "") -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "sell_for_cash",
        {"tenant": "nova", "screening_id": screening, "holder": holder, "email": email}
    );
}

test "a cash sale is a confirmed booking, with a ledger entry recorded by the agent" {
    (app, nova, screening) = paying_cinema(["agent"]);
    try {
        agent = hire(app, "agent", "box_office_agent", nova.venue);
        holder = _counter_order(app, screening);
        sold = _cash(app, "agent", screening, holder);
        assert sold["ok"] , sold;
        paid = sold["payment"];
        assert paid["state"] == "success";
        assert [t["seat_label"] for t in paid["tickets"]] == ["A3", "A4"];
        assert all([t["qr"].startswith("TKT1.") for t in paid["tickets"]]);
        assert paid["link"].startswith("/c/nova/tickets/");
        stored = app.call(
            "owner", "pay_overview", {"slug": "nova", "screening_id": screening}
        );
        assert stored["seats"]["A3"] == "sold" and stored["seats"]["A4"] == "sold";
        assert "confirmed" in stored["orders"];
        entries = app.call(
            "owner", "bo_ledger", {"slug": "nova", "screening_id": screening}
        );
        assert entries == [["payment", paid["amount_cents"], "cash", agent]] , entries;
        # Paid once: asking again changes nothing.
        assert code_of(_cash(app, "agent", screening, holder)) == "no_order";
        assert len(
            app.call("owner", "bo_ledger", {"slug": "nova", "screening_id": screening})
        )
            == 1;
    } finally {
        app.close();
    }
}

test "only staff who may sell at the showtime's venue can take the money" {
    (app, nova, screening) = paying_cinema(["elsewhere", "usher"]);
    try {
        mall = app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Mall", "city": "", "address": ""}
        )["venue"]["venue_id"];
        hire(app, "elsewhere", "box_office_agent", mall);
        hire(app, "usher", "usher", nova.venue);
        holder = _counter_order(app, screening);
        assert code_of(_cash(app, "elsewhere", screening, holder)) == "forbidden";
        assert code_of(_cash(app, "usher", screening, holder)) == "forbidden";
        stored = app.call(
            "owner", "pay_overview", {"slug": "nova", "screening_id": screening}
        );
        assert stored["seats"]["A3"] == "payment_pending";
        assert app.call(
            "owner", "bo_ledger", {"slug": "nova", "screening_id": screening}
        )
            == [];
    } finally {
        app.close();
    }
}

test "M-Pesa at the counter: the customer's prompt, no email needed; cash then waits" {
    (app, nova, screening) = paying_cinema(["agent"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        holder = _counter_order(app, screening);
        started = app.call(
            "agent",
            "sell_with_mpesa",
            {
                "tenant": "nova",
                "screening_id": screening,
                "holder": holder,
                "phone": fresh_phone(),
                "email": ""
            }
        );
        assert started["ok"]
            and started["payment"]["state"] == "stk_requested" , started;
        # While the prompt is on the customer's phone, cash can't pay the order too.
        assert code_of(_cash(app, "agent", screening, holder)) == "payment_in_progress";
    } finally {
        app.close();
    }
}

test "an M-Pesa sale at the counter is recorded as taken by the agent" {
    (app, nova, screening) = paying_cinema(["agent"]);
    try {
        agent = hire(app, "agent", "box_office_agent", nova.venue);
        holder = _counter_order(app, screening);
        started = app.call(
            "agent",
            "sell_with_mpesa",
            {
                "tenant": "nova",
                "screening_id": screening,
                "holder": holder,
                "phone": fresh_phone(),
                "email": ""
            }
        );
        assert started["ok"] , started;
        settle(app, screening, started["payment"]["reference"]);
        entries = app.call(
            "owner", "bo_ledger", {"slug": "nova", "screening_id": screening}
        );
        assert entries == [["payment", 186000, "mpesa", agent]] , entries;
    } finally {
        app.close();
    }
}

test "the box office lists showtimes on sale at the caller's venues only" {
    (app, nova, screening) = paying_cinema(["agent", "elsewhere"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        mall = app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Mall", "city": "", "address": ""}
        )["venue"]["venue_id"];
        hire(app, "elsewhere", "box_office_agent", mall);
        mine = app.call("agent", "counter_showtimes", {"tenant": "nova"});
        assert mine["ok"] and mine["timezone"] , mine;
        assert [s["screening_id"] for s in mine["showtimes"]] == [screening];
        assert mine["showtimes"][0]["movie_title"] == "Rafiki";
        assert app.call("elsewhere", "counter_showtimes", {"tenant": "nova"})[
            "showtimes"
        ]
            == [];
    } finally {
        app.close();
    }
}

test "without a ticket key, cash is refused up front and nothing changes" {
    (app, nova, screening) = paying_cinema(["agent"]);
    before = os.environ.pop("AFRICINEMAS_TICKET_KEY", None);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        holder = _counter_order(app, screening);
        refused = _cash(app, "agent", screening, holder);
        assert code_of(refused) == "tickets_unavailable" , refused;
        stored = app.call(
            "owner", "pay_overview", {"slug": "nova", "screening_id": screening}
        );
        assert stored["seats"]["A3"] == "payment_pending";
        assert app.call(
            "owner", "bo_ledger", {"slug": "nova", "screening_id": screening}
        )
            == [];
    } finally {
        if before is not None {
            os.environ["AFRICINEMAS_TICKET_KEY"] = before;
        }
        app.close();
    }
}
