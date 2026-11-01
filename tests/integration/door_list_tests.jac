"""P17.2: the door list (core/booking/door_list.jac).

In-process app (payment_app.jac) with the simulated M-Pesa. Nova's five-seat screen
shows Rafiki two days ahead: Anna buys A1 and A2 online, the box office sells A3 and
A4 for cash and A5 with M-Pesa. The list opens at noon the day before (the clock is
moved there); it holds the five tickets and nothing else about the bookers. Who may scan
or sell at the venue gets it; a finance manager doesn't.
"""

import os;
import uuid;
import base64;
import from datetime { datetime, timedelta }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup {
    paying_cinema,
    hire,
    fresh_phone,
    paid,
    settle
}

def _counter_order(app: Served, screening: str, labels: list[str]) -> str {
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

def _shifts(app: Served, who: list[str]) {
    # After the clock moves, everyone starts a shift again.
    for w in who {
        assert app.call(w, "start_shift", {"tenant": "nova"})["ok"] , w;
    }
}

test "the door list holds every paid ticket, for who may scan or sell, from noon the day before" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, screening) = paying_cinema(["agent", "usher", "finance"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "usher", "usher", nova.venue);
        hire(app, "finance", "finance_manager", "");
        anna_phone = fresh_phone();
        paid(app, screening);
        cash = _counter_order(app, screening, ["A3", "A4"]);
        assert app.call(
            "agent",
            "sell_for_cash",
            {"tenant": "nova", "screening_id": screening, "holder": cash, "email": ""}
        )["ok"];
        mpesa = _counter_order(app, screening, ["A5"]);
        started = app.call(
            "agent",
            "sell_with_mpesa",
            {
                "tenant": "nova",
                "screening_id": screening,
                "holder": mpesa,
                "phone": anna_phone,
                "email": ""
            }
        );
        assert started["ok"] , started;
        settle(app, screening, started["payment"]["reference"]);
        where = {"tenant": "nova", "screening_id": screening};
        # Two days ahead: not yet, and the day's showtimes say from when.
        assert code_of(app.call("owner", "door_list", where)) == "not_yet";
        listing = app.call(
            "owner", "door_lists", {"tenant": "nova", "day": "2000-01-01"}
        );
        assert listing["ok"] and listing["showtimes"] == [] , listing;
        # The day of the showtime, cinema time, from the refusal's opening time.
        opens = app.call("owner", "door_list", where)["error"]["opens_at"];
        show_day = (
            datetime.fromisoformat(opens) + timedelta(days=1)
        ).date().isoformat();
        listing = app.call("owner", "door_lists", {"tenant": "nova", "day": show_day});
        assert [[s["screening_id"], s["ready"]] for s in listing["showtimes"]]
            == [[screening, False]] , listing;
        # Noon the day before: ready.
        assert app.call(
            "owner",
            "t_clock_at",
            {"at": (datetime.fromisoformat(opens) + timedelta(minutes=1)).isoformat()}
        );
        _shifts(app, ["owner", "agent", "usher", "finance"]);
        listing = app.call("owner", "door_lists", {"tenant": "nova", "day": show_day});
        assert [[s["ready"], s["tickets"]] for s in listing["showtimes"]]
            == [[True, 5]] , listing;
        got = app.call("owner", "door_list", where);
        assert got["ok"] , got;
        tickets = got["tickets"];
        assert [t["seat"] for t in tickets] == ["A1", "A2", "A3", "A4", "A5"];
        assert [t["paid_with"] for t in tickets]
            == ["M-Pesa", "M-Pesa", "Cash", "Cash", "M-Pesa"];
        assert all(
            [
                len(t["code"]) > 0
                for t in tickets
                if t["paid_with"] == "M-Pesa"
            ]
        );
        assert tickets[4]["phone_end"] == anna_phone[-3:];
        assert tickets[2]["phone_end"] == "" and tickets[2]["code"] == "";
        assert len(set([t["reference"] for t in tickets])) == 5;
        assert all([t["used_at"] == "" for t in tickets]);
        # Nothing else about the bookers: no email, no full phone number.
        said = str(got);
        assert "@" not in said and anna_phone not in said , said;
        # Who scans or sells at the venue gets it; finance doesn't.
        for who in ["agent", "usher"] {
            assert app.call(who, "door_list", where)["ok"] , who;
        }
        assert code_of(app.call("finance", "door_list", where)) == "forbidden";
        # The PDFs: one showtime, and the day.
        one = app.call("usher", "door_list_pdf", where);
        assert one["ok"] and one["filename"].startswith("door-list-") , one;
        text = base64.b64decode(one["pdf"]).decode("cp1252");
        assert text.startswith("%PDF-1.4");
        for seat in [
            "(A1)",
            "(A5)",
            "(Rafiki)",
            "(Paid during an outage, not on this list)"
        ] {
            assert seat in text , seat;
        }
        whole = app.call(
            "agent", "day_door_lists_pdf", {"tenant": "nova", "day": show_day}
        );
        assert whole["ok"] and whole["filename"] == f"door-lists-{show_day}.pdf";
        assert code_of(
            app.call(
                "agent", "day_door_lists_pdf", {"tenant": "nova", "day": "2000-01-01"}
            )
        )
            == "nothing_yet";
        # Scanned at the door: the list says when.
        starts = datetime.fromisoformat(
            app.call("owner", "door_list", where)["showtime"]["starts_at"]
        );
        assert app.call(
            "owner", "t_clock_at", {"at": (starts - timedelta(minutes=10)).isoformat()}
        );
        _shifts(app, ["owner", "usher"]);
        assert app.call(
            "usher", "redeem_ticket", {** where, "code": tickets[0]["reference"]}
        )["ok"];
        again = app.call("owner", "door_list", where)["tickets"];
        assert again[0]["used_at"] != "" and again[1]["used_at"] == "";
    } finally {
        app.call("owner", "t_clock_reset");
        app.close();
    }
}
