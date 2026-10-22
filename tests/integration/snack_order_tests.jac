"""P12.7: snacks in the order and the payment.

In-process app (payment_app.jac) with the simulated M-Pesa, and Nova's snacks
(tests/support/snack_setup.jac: Coca-Cola has 3 on hand at the venue). Ben holds A3 and
orders an Adult ticket with a Large Popcorn and Butter and two Coca-Colas: the server
prices the snacks at the venue (KES 480 + KES 300) and adds them to the total, and two
Coca-Colas are set aside. A price change afterwards changes nothing; the same key with
other snacks is refused. Paying sells the Coca-Colas once, however often M-Pesa calls
back; an order that ends unpaid gives them back; the last ones can't be sold twice.
"""

import os;
import time;
import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { paying_cinema, fresh_phone, settle }
import from tests.support.snack_setup { owner_call, snack_menu }

glob BEN: str = "holder-ben-0123456789abcdefgh",
     CARL: str = "holder-carl-0123456789abcdefg",
     PAY_TIME: str = "AFRICINEMAS_PAY_SECONDS";

def _order(
    app: Served,
    screening: str,
    holder: str,
    seat: str,
    snacks: list[dict[str, any]],  # jac:ignore[W1037]
    key: str = "",
    hold: bool = True
) -> any {  # jac:ignore[W1037]
    if hold {
        held = browse(
            app,
            "hold_seats",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": holder,
                "labels": [seat]
            }
        );
        assert held["ok"] , held;
    }
    return browse(
        app,
        "place_order",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": holder,
            "idempotency_key": key or f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": seat, "ticket_type": "ADULT"}],
            "snacks": snacks
        }
    );
}

def _cart(made: dict[str, any], cokes: int = 2) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return [
        {"variant_id": made["large"], "quantity": 1, "addons": [made["butter"]]},
        {"variant_id": made["coke_v"], "quantity": cokes}
    ];
}

def _coke(app: Served, venue: str, made: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    levels = owner_call(app, "snack_stock_levels", {"venue_id": venue})["levels"];
    return [
        l
        for l in levels
        if l["variant_id"] == made["coke_v"]
    ][0];
}

def _pay(app: Served, screening: str, holder: str) -> str {
    started = browse(
        app,
        "start_payment",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": holder,
            "phone": fresh_phone(),
            "email": "ben@example.com",
            "idempotency_key": f"pay-{uuid.uuid4().hex}"
        }
    );
    assert started["ok"] , started;
    return started["payment"]["reference"];
}

test "an order's total includes its snacks, priced when it's placed" {
    (app, nova, screening) = paying_cinema([]);
    try {
        made = snack_menu(app, nova.venue);
        key = f"order-{uuid.uuid4().hex}";
        placed = _order(app, screening, BEN, "A3", _cart(made), key);
        assert placed["ok"] , placed;
        order = placed["order"];
        assert order["snacks_cents"] == 48000 + 30000 , order;
        tickets = sum(l["total_cents"] for l in order["lines"]);
        assert order["total_cents"] == tickets + 78000;
        assert [s["name"] for s in order["snacks"]] == ["Popcorn · Large", "Coca-Cola"];
        assert order["snacks"][0]["addons"][0]["name"] == "Butter";
        # Two Coca-Colas are set aside.
        coke = _coke(app, nova.venue, made);
        assert (coke["on_hand"], coke["reserved"], coke["available"])
            == (3, 2, 1) , coke;
        # The same key again: the same order; with other snacks: refused.
        again = _order(app, screening, BEN, "A3", _cart(made), key, False);
        assert again["order"]["reference"] == order["reference"];
        assert code_of(_order(app, screening, BEN, "A3", _cart(made, 1), key, False))
            == "key_reused";
        # A price change afterwards changes nothing.
        owner_call(
            app,
            "set_snack_venue_price",
            {
                "product_id": made["popcorn"],
                "variant_id": made["large"],
                "venue_id": nova.venue,
                "price_cents": 50000
            }
        );
        mine = browse(
            app, "my_order", {"slug": "nova", "screening_id": screening, "holder": BEN}
        );
        assert mine["order"]["snacks_cents"] == 78000 , mine;
    } finally {
        app.close();
    }
}

test "paying sells the snacks once, however often M-Pesa calls back" {
    (app, nova, screening) = paying_cinema([]);
    try {
        made = snack_menu(app, nova.venue);
        placed = _order(app, screening, BEN, "A3", _cart(made));
        assert placed["ok"] , placed;
        reference = _pay(app, screening, BEN);
        settle(app, screening, reference);
        # Settling again and resolving change nothing.
        app.call("owner", "pay_process");
        app.call("owner", "pay_resolve");
        coke = _coke(app, nova.venue, made);
        assert (coke["on_hand"], coke["reserved"], coke["available"])
            == (1, 0, 1) , coke;
        sales = [
            m
            for m in owner_call(
                app,
                "snack_stock_history",
                {"venue_id": nova.venue, "variant_id": made["coke_v"], "limit": 20}
            )["movements"]
            if m["reason"] == "sale"
        ];
        every = owner_call(
            app,
            "snack_stock_history",
            {"venue_id": nova.venue, "variant_id": "", "limit": 50}
        )["movements"];
        assert len(sales) == 1 and sales[0]["change"] == -2 , every;
        assert placed["order"]["reference"] in sales[0]["note"];
    } finally {
        app.close();
    }
}

test "an order that ends unpaid gives its snacks back" {
    os.environ[PAY_TIME] = "1";
    (app, nova, screening) = paying_cinema([]);
    try {
        made = snack_menu(app, nova.venue);
        assert _order(app, screening, BEN, "A3", _cart(made))["ok"];
        assert _coke(app, nova.venue, made)["available"] == 1;
        time.sleep(1.5);
        assert app.call("owner", "pay_resolve")["expired"] >= 1;
        coke = _coke(app, nova.venue, made);
        assert (coke["on_hand"], coke["reserved"], coke["available"])
            == (3, 0, 3) , coke;
    } finally {
        os.environ.pop(PAY_TIME, None);
        app.close();
    }
}

test "the last Coca-Colas can't be sold twice" {
    (app, nova, screening) = paying_cinema([]);
    try {
        made = snack_menu(app, nova.venue);
        assert _order(app, screening, BEN, "A3", _cart(made))["ok"];
        late = _order(app, screening, CARL, "A4", _cart(made));
        assert code_of(late) == "snacks_unavailable" , late;
        assert "Only 1 Coca-Cola left." in late["error"]["message"] , late;
        assert _order(app, screening, CARL, "A4", _cart(made, 1), "", False)["ok"];
        assert _coke(app, nova.venue, made)["available"] == 0;
    } finally {
        app.close();
    }
}
