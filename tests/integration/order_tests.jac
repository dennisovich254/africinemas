"""P4.5: orders, through the production app (main.jac).

A visitor holding seats (P4.3) places an order: a ticket type for each held seat. The
order snapshots the server's prices (architecture §27): each line's price, extras and
fee, the total, the currency and the price list version, so a later price edit never
changes it. It waits for payment (Phase 5); its seats are paying (PAYMENT_PENDING), so
nobody else can hold them, even after the hold's time.

The browser sends an idempotency key with the order (§26): the same key again returns
the same order, never a second one; the same key with different seats is refused.
Racing requests: order_concurrency_tests.jac.
"""

import os;
import time;
import from os { path }
import from tests.support.served { Served, served }
import from tests.support.storefront_setup {
    Cinema,
    open_cinema_for,
    add_movie,
    add_screening,
    set_prices,
    browse,
    code_of
}

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     HOLD_ENV: str = "AFRICINEMAS_HOLD_SECONDS",
     ANNA: str = "holder-anna-0123456789abcdef",
     BEN: str = "holder-ben-0123456789abcdefgh",
     KEY: str = "order-key-anna-0123456789abcdef",
     ADULT_A1: dict[str, str] = {"seat_label": "A1", "ticket_type": "ADULT"},
     CHILD_A2: dict[str, str] = {"seat_label": "A2", "ticket_type": "CHILD"};

def _setup -> tuple[Served, Cinema, str] {  # jac:ignore[W1037]
    app = served(MAIN, ["owner"]);
    nova = open_cinema_for(app, "owner", "nova", "Nova Cinemas");
    add_movie(app, "owner", nova, "Rafiki");
    set_prices(app, "owner", nova);
    return (app, nova, add_screening(app, "owner", nova, "Rafiki", 0));
}

def _hold(app: Served, screening: str, holder: str, labels: list[str]) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "hold_seats",
        {"slug": "nova", "screening_id": screening, "holder": holder, "labels": labels}
    );
}

def _order(
    app: Served,
    screening: str,
    items: list[dict[str, any]],  # jac:ignore[W1037]
    holder: str = ANNA,
    key: str = KEY
) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "place_order",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": holder,
            "idempotency_key": key,
            "items": items
        }
    );
}

def _mine(app: Served, screening: str, holder: str = ANNA) -> any {  # jac:ignore[W1037]
    return browse(
        app, "my_order", {"slug": "nova", "screening_id": screening, "holder": holder}
    );
}

def _states(app: Served, screening: str) -> dict[str, str] {
    seats = browse(
        app, "public_seat_availability", {"slug": "nova", "screening_id": screening}
    )["seats"];
    return {s["label"]: s["state"] for s in seats};
}

test "an order prices each held seat on the server and waits for payment" {
    (app, nova, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1", "A2"])["ok"];
        # Prices a browser sends are ignored.
        sent = [
            {"seat_label": "A1", "ticket_type": "ADULT", "total_cents": 1},
            CHILD_A2
        ];
        placed = _order(app, screening, sent);
        assert placed["ok"] , placed;
        order = placed["order"];
        assert order["status"] == "pending_payment";
        assert order["seats"] == ["A1", "A2"];
        assert order["currency"] == "KES" and order["price_list_version"] == 1;
        assert [
            (
                l["seat_label"],
                l["ticket_name"],
                l["unit_price_cents"],
                l["surcharge_cents"],
                l["service_fee_cents"],
                l["total_cents"]
            ) for l in order["lines"]
        ]
            == [
                ("A1", "Adult", 80000, 10000, 3000, 93000),
                ("A2", "Child", 50000, 10000, 3000, 63000)
            ] , order["lines"];
        assert order["lines"][0]["rules"] == ["Evening"];
        assert order["total_cents"] == 156000;
        assert order["reference"] and order["pay_by"];
        assert _mine(app, screening)["order"] == order;
        # Its seats are paying: held to everyone else, and no longer a hold to extend.
        assert _states(app, screening)["A1"] == "held";
        assert code_of(
            browse(
                app,
                "my_hold",
                {"slug": "nova", "screening_id": screening, "holder": ANNA}
            )
        )
            == "no_hold";
        assert code_of(_mine(app, screening, BEN)) == "no_order";
    } finally {
        app.close();
    }
}

test "the same key returns the same order; with different seats it is refused" {
    (app, nova, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1", "A2"])["ok"];
        first = _order(app, screening, [ADULT_A1, CHILD_A2]);
        assert first["ok"] , first;
        # The network dropped the answer; the browser sends the order again.
        again = _order(app, screening, [ADULT_A1, CHILD_A2]);
        assert again["ok"] and again["order"] == first["order"] , again;
        changed = _order(
            app, screening, [ADULT_A1, {"seat_label": "A2", "ticket_type": "ADULT"}]
        );
        assert code_of(changed) == "key_reused" , changed;
        # A new key can't turn the same seats into a second order.
        other = _order(
            app, screening, [ADULT_A1, CHILD_A2], key="another-key-0123456789abcdef"
        );
        assert code_of(other) == "no_hold" , other;
        assert _mine(app, screening)["order"] == first["order"];
    } finally {
        app.close();
    }
}

test "a price edit after the order leaves the order's prices as they were" {
    (app, nova, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1"])["ok"];
        placed = _order(app, screening, [ADULT_A1])["order"];
        set_prices(app, "owner", nova, adult=95000);
        mine = _mine(app, screening)["order"];
        assert mine == placed;
        assert mine["lines"][0]["unit_price_cents"] == 80000;
        assert mine["price_list_version"] == 1 and mine["total_cents"] == 93000;
    } finally {
        app.close();
    }
}

test "an order needs a live hold on exactly its seats, and valid ticket types" {
    (app, nova, screening) = _setup();
    try {
        assert code_of(_order(app, screening, [ADULT_A1])) == "no_hold";
        assert _hold(app, screening, ANNA, ["A1", "A2"])["ok"];
        assert code_of(_order(app, screening, [ADULT_A1])) == "seats_not_held";
        assert code_of(
            _order(
                app, screening, [ADULT_A1, {"seat_label": "A3", "ticket_type": "ADULT"}]
            )
        )
            == "seats_not_held";
        assert code_of(
            _order(
                app,
                screening,
                [ADULT_A1, {"seat_label": "A2", "ticket_type": "SENIOR"}]
            )
        )
            == "unknown_ticket_type";
        assert code_of(_order(app, screening, [ADULT_A1, ADULT_A1]))
            == "duplicate_seat";
        assert code_of(_order(app, screening, [ADULT_A1, CHILD_A2], key="short"))
            == "invalid_key";
        assert code_of(_order(app, screening, [ADULT_A1, CHILD_A2], holder="short"))
            == "invalid_holder";
        # Nothing was ordered: the seats are still Anna's hold.
        assert code_of(_mine(app, screening)) == "no_order";
        assert _states(app, screening)["A1"] == "held";
        assert _order(app, screening, [ADULT_A1, CHILD_A2])["ok"];
    } finally {
        app.close();
    }
}

test "a paying seat stays taken after the hold's time is up" {
    os.environ[HOLD_ENV] = "1";
    (app, nova, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1"])["ok"];
        assert _order(app, screening, [ADULT_A1])["ok"];
        time.sleep(2.2);
        assert _states(app, screening)["A1"] == "held";
        refused = _hold(app, screening, BEN, ["A1"]);
        assert code_of(refused) == "seats_taken" , refused;
        assert _mine(app, screening)["order"]["status"] == "pending_payment";
    } finally {
        os.environ.pop(HOLD_ENV, None);
        app.close();
    }
}

test "an order can't be placed once the hold's time is up" {
    os.environ[HOLD_ENV] = "1";
    (app, nova, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1"])["ok"];
        time.sleep(2.2);
        assert code_of(_order(app, screening, [ADULT_A1])) == "no_hold";
    } finally {
        os.environ.pop(HOLD_ENV, None);
        app.close();
    }
}
