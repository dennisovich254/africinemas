"""P12.9: collecting snacks at the snack counter, by the order's pickup code.

In-process app (payment_app.jac) with the simulated M-Pesa, Nova's snacks
(tests/support/snack_setup.jac) and a frozen clock. Ben pays for A3 with a Large Popcorn
and Butter and a Movie Night Combo: the paid order gets a pickup code (a reference, and
a QR signed as SNK1). A box office agent at the venue looks it up and hands the snacks
over once; a second handover says when, and by whom. Pickup opens two hours before the
showtime and closes when it ends. The door won't take a pickup code, the counter won't
take a ticket, and an usher may not hand snacks over. An order without snacks has no
pickup code.
"""

import os;
import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup {
    ANNA,
    paying_cinema,
    paid,
    fresh_phone,
    settle,
    hire
}
import from tests.support.snack_setup { snack_menu }

glob CLOCK: str = "AFRICINEMAS_CLOCK_CONTROL",
     BEN: str = "holder-ben-0123456789abcdefgh";

obj Counter {
    # Ben's paid order with snacks, and its showtime.
    has app: Served,
        screening: str,
        payment: dict[str, any];  # jac:ignore[W1037]
}

def _counter -> Counter {
    os.environ[CLOCK] = "1";
    (app, nova, screening) = paying_cinema(["agent", "usher"]);
    made = snack_menu(app, nova.venue);
    hire(app, "agent", "box_office_agent", nova.venue);
    hire(app, "usher", "usher", nova.venue);
    where = {"slug": "nova", "screening_id": screening, "holder": BEN};
    assert browse(app, "hold_seats", {** where, "labels": ["A3"]})["ok"];
    placed = browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": "A3", "ticket_type": "ADULT"}],
            "snacks": [
                {
                    "variant_id": made["large"],
                    "quantity": 1,
                    "addons": [made["butter"]]
                },
                {
                    "variant_id": made["combo_v"],
                    "quantity": 1,
                    "choices": [[], [made["coke_v"], made["fanta_v"]]]
                }
            ]
        }
    );
    assert placed["ok"] , placed;
    started = browse(
        app,
        "start_payment",
        {
            ** where,
            "phone": fresh_phone(),
            "email": "ben@example.com",
            "idempotency_key": f"pay-{uuid.uuid4().hex}",
            "adult": "yes"
        }
    );
    assert started["ok"] , started;
    settle(app, screening, started["payment"]["reference"]);
    mine = browse(app, "my_payment", where);
    assert mine["payment"]["state"] == "success" , mine;
    _at(app, screening, -30);
    return Counter(app=app, screening=screening, payment=mine["payment"]);
}

def _at(app: Served, screening: str, minutes: int) {
    app.call(
        "owner",
        "rd_freeze",
        {"slug": "nova", "screening_id": screening, "minutes": minutes}
    );
}

def _close(counter: Counter) {
    counter.app.call("owner", "rd_unfreeze");
    counter.app.close();
}

def _call(counter: Counter, name: str, code: str, who: str = "agent") -> any {  # jac:ignore[W1037]
    return counter.app.call(who, name, {"tenant": "nova", "code": code});
}

test "a paid order with snacks gets a pickup code, and the counter hands it over once" {
    counter = _counter();
    try {
        pickup = counter.payment["pickup"];
        assert pickup["qr"].startswith("SNK1.") , pickup;
        assert len(pickup["reference"]) == 19 , pickup;
        looked = _call(counter, "snack_pickup", pickup["qr"]);
        assert looked["ok"] , looked;
        shown = looked["pickup"];
        assert shown["window"] == "open"
            and shown["paid"]
            and not shown["collected_at"];
        assert [(s["quantity"], s["name"]) for s in shown["snacks"]]
            == [(1, "Popcorn · Large"), (1, "Movie Night Combo")] , shown;
        assert shown["snacks"][0]["addons"] == ["Butter"];
        assert shown["snacks"][1]["choices"]
            == ["Popcorn · Large", "Coca-Cola", "Fanta"];
        # The tickets page (and the email and My tickets, which share its view) lists
        # the snacks with the pickup code.
        token = counter.payment["link"].split("/")[-1];
        page = browse(counter.app, "tickets_by_link", {"slug": "nova", "token": token});
        assert page["ok"] , page;
        assert [s["name"] for s in page["booking"]["snacks"]]
            == ["Popcorn · Large", "Movie Night Combo"];
        assert page["booking"]["pickup"] == pickup;
        assert not page["booking"]["snacks_collected"];
        handed = _call(counter, "hand_over_snacks", pickup["qr"]);
        assert handed["ok"] and handed["pickup"]["collected_at"] , handed;
        after = browse(
            counter.app, "tickets_by_link", {"slug": "nova", "token": token}
        );
        assert after["booking"]["snacks_collected"];
        again = _call(counter, "hand_over_snacks", pickup["qr"]);
        assert code_of(again) == "already_collected" , again;
        assert again["error"]["collected_at"] == handed["pickup"]["collected_at"];
        assert again["error"]["collected_by"];
        # Typed in, in any case and with spaces, it's the same order.
        typed = pickup["reference"].lower().replace("-", " ");
        assert code_of(_call(counter, "hand_over_snacks", typed))
            == "already_collected";
    } finally {
        _close(counter);
    }
}

test "pickup opens two hours before the showtime and closes when it ends" {
    counter = _counter();
    try {
        qr: str = counter.payment["pickup"]["qr"];
        _at(counter.app, counter.screening, -150);
        early = _call(counter, "hand_over_snacks", qr);
        assert code_of(early) == "too_early" and early["error"]["opens_at"] , early;
        assert _call(counter, "snack_pickup", qr)["pickup"]["window"] == "early";
        _at(counter.app, counter.screening, 24 * 60);
        assert code_of(_call(counter, "hand_over_snacks", qr)) == "showtime_over";
        _at(counter.app, counter.screening, -119);
        assert _call(counter, "hand_over_snacks", qr)["ok"];
    } finally {
        _close(counter);
    }
}

test "each scanner refuses the other's codes, and only snack staff hand snacks over" {
    counter = _counter();
    try {
        pickup = counter.payment["pickup"];
        ticket = counter.payment["tickets"][0];
        door = {"tenant": "nova", "screening_id": counter.screening};
        at_door = counter.app.call(
            "usher", "redeem_ticket", {** door, "code": pickup["qr"]}
        );
        assert code_of(at_door) == "snack_code" , at_door;
        typed_at_door = counter.app.call(
            "usher", "redeem_ticket", {** door, "code": pickup["reference"]}
        );
        assert code_of(typed_at_door) == "snack_code" , typed_at_door;
        assert code_of(_call(counter, "hand_over_snacks", ticket["qr"]))
            == "ticket_code";
        assert code_of(_call(counter, "hand_over_snacks", ticket["reference"]))
            == "ticket_code";
        assert code_of(_call(counter, "hand_over_snacks", "nonsense"))
            == "invalid_code";
        assert code_of(_call(counter, "hand_over_snacks", "AAAA-BBBB-CCCC-DDDD"))
            == "unknown_pickup";
        refused = _call(counter, "hand_over_snacks", pickup["qr"], "usher");
        assert not refused["ok"] and code_of(refused) != "already_collected" , refused;
        # Anna's order has no snacks, so no pickup code. (Paid now, not at the frozen
        # time: by then her time to pay has run out.)
        counter.app.call("owner", "rd_unfreeze");
        paid(counter.app, counter.screening);
        anna = browse(
            counter.app,
            "my_payment",
            {"slug": "nova", "screening_id": counter.screening, "holder": ANNA}
        );
        assert anna["ok"] and anna["payment"]["pickup"] is None , anna;
    } finally {
        _close(counter);
    }
}
