"""P12.10: a walk-in buys snacks only at the box office, cash or M-Pesa.

In-process app (payment_app.jac). Nova's box office agent Clara sells at Westgate:
the venue's menu, a sale of a Large Popcorn and two Coca-Colas (set aside until paid),
cash that sells them at once with a pickup code to hand them over, M-Pesa that sells
them when Safaricom says it's paid, and a sale left unpaid that gives them back. An
usher can't sell, nor can another cinema's staff. Each sale is in the cinema's log.
"""

import os;
import time;
import uuid;
import from datetime { date, timedelta }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { paying_cinema, hire, fresh_phone, settle }
import from tests.support.snack_setup { snack_menu, owner_call }

glob PAY_TIME: str = "AFRICINEMAS_PAY_SECONDS";

def _holder -> str {
    return f"counter-{uuid.uuid4().hex}";
}

def _cart(made: dict[str, any]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return [
        {"variant_id": made["large"], "quantity": 1, "addons": []},
        {"variant_id": made["coke_v"], "quantity": 2}
    ];
}

def _coke(app: Served, venue: str, made: dict[str, any]) -> tuple[int, int, int] {
    levels = owner_call(app, "snack_stock_levels", {"venue_id": venue})["levels"];
    coke = [
        l
        for l in levels
        if l["variant_id"] == made["coke_v"]
    ][0];
    return (coke["on_hand"], coke["reserved"], coke["available"]);
}

def _place(
    app: Served, who: str, venue: str, holder: str, made: dict[str, any]
) -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "place_snack_order",
        {
            "tenant": "nova",
            "venue_id": venue,
            "holder": holder,
            "idempotency_key": f"snacks-{uuid.uuid4().hex}",
            "snacks": _cart(made)
        }
    );
}

test "cash sells the snacks at once, and the agent hands them over" {
    (app, nova, _) = paying_cinema(["clara", "usher", "rival"]);
    try {
        hire(app, "clara", "box_office_agent", nova.venue);
        hire(app, "usher", "usher", nova.venue);
        app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        made = snack_menu(app, nova.venue);
        menu = app.call(
            "clara", "counter_snack_menu", {"tenant": "nova", "venue_id": nova.venue}
        );
        assert menu["ok"] and len(menu["categories"]) > 0 , menu;
        venues = app.call("clara", "counter_snack_venues", {"tenant": "nova"})[
            "venues"
        ];
        assert [v["venue_id"] for v in venues] == [nova.venue] , venues;
        priced = app.call(
            "clara",
            "counter_price_snacks",
            {"tenant": "nova", "venue_id": nova.venue, "lines": _cart(made)}
        );
        assert priced["ok"] and priced["total_cents"] == 75000 , priced;
        assert code_of(app.call("usher", "counter_snack_venues", {"tenant": "nova"}))
            == "forbidden";
        holder = _holder();
        empty = app.call(
            "clara",
            "place_snack_order",
            {
                "tenant": "nova",
                "venue_id": nova.venue,
                "holder": holder,
                "idempotency_key": f"snacks-{uuid.uuid4().hex}",
                "snacks": []
            }
        );
        assert code_of(empty) == "no_snacks";
        placed = _place(app, "clara", nova.venue, holder, made);
        assert placed["ok"] , placed;
        assert placed["order"]["status"] == "pending_payment";
        assert placed["order"]["total_cents"] == 45000 + 2 * 15000 , placed["order"];
        assert _coke(app, nova.venue, made) == (3, 2, 1);
        paid = app.call(
            "clara",
            "sell_snacks_for_cash",
            {"tenant": "nova", "venue_id": nova.venue, "holder": holder}
        );
        assert paid["ok"] and paid["order"]["status"] == "confirmed" , paid;
        code = paid["order"]["pickup_reference"];
        assert code;
        assert _coke(app, nova.venue, made) == (1, 0, 1);
        assert code_of(
            app.call(
                "clara",
                "sell_snacks_for_cash",
                {"tenant": "nova", "venue_id": nova.venue, "holder": holder}
            )
        )
            == "no_order";
        handed = app.call(
            "clara", "hand_over_snacks", {"tenant": "nova", "code": code}
        );
        assert handed["ok"] , handed;
        # Its takings are the cinema's, in the log and the report.
        logged = [
            e["action"]
            for e in app.call("owner", "audit_log", {"tenant": "nova", "limit": 20})[
                "events"
            ]
        ];
        assert "sale.snacks_cash" in logged , logged;
        takings = app.call(
            "owner",
            "sales_report",
            {
                "tenant": "nova",
                "date_from": str(date.today() - timedelta(days=1)),
                "date_to": str(date.today() + timedelta(days=1))
            }
        );
        assert takings["ok"] , takings;
        # Only sellers at the venue.
        assert code_of(_place(app, "usher", nova.venue, _holder(), made))
            == "forbidden";
        assert code_of(_place(app, "rival", nova.venue, _holder(), made))
            == "not_found";
    } finally {
        app.close();
    }
}

test "M-Pesa sells them once Safaricom says it's paid" {
    (app, nova, _) = paying_cinema(["clara"]);
    try {
        hire(app, "clara", "box_office_agent", nova.venue);
        made = snack_menu(app, nova.venue);
        holder = _holder();
        assert _place(app, "clara", nova.venue, holder, made)["ok"];
        started = app.call(
            "clara",
            "sell_snacks_with_mpesa",
            {
                "tenant": "nova",
                "venue_id": nova.venue,
                "holder": holder,
                "phone": fresh_phone(),
                "email": "",
                "idempotency_key": f"pay-{uuid.uuid4().hex}"
            }
        );
        assert started["ok"]
            and started["payment"]["state"] == "stk_requested" , started;
        waiting = app.call(
            "clara",
            "counter_snack_payment",
            {"tenant": "nova", "venue_id": nova.venue, "holder": holder}
        );
        assert waiting["order"]["status"] == "pending_payment";
        settle(app, "", started["payment"]["reference"]);
        done = app.call(
            "clara",
            "counter_snack_payment",
            {"tenant": "nova", "venue_id": nova.venue, "holder": holder}
        );
        assert done["payment"]["state"] == "success"
            and done["order"]["status"] == "confirmed" , done;
        assert done["order"]["pickup_reference"];
        assert _coke(app, nova.venue, made) == (1, 0, 1);
    } finally {
        app.close();
    }
}

test "a sale left unpaid gives its snacks back" {
    os.environ[PAY_TIME] = "1";
    (app, nova, _) = paying_cinema(["clara"]);
    try {
        hire(app, "clara", "box_office_agent", nova.venue);
        made = snack_menu(app, nova.venue);
        assert _place(app, "clara", nova.venue, _holder(), made)["ok"];
        assert _coke(app, nova.venue, made)[2] == 1;
        time.sleep(1.5);
        assert app.call("owner", "pay_resolve")["expired"] >= 1;
        assert _coke(app, nova.venue, made) == (3, 0, 3);
    } finally {
        os.environ.pop(PAY_TIME, None);
        app.close();
    }
}
