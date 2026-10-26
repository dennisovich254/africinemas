"""P12.14: separate payments, shared pickup, no duplicate collection, and access."""

import uuid;
import os;
import from tests.support.payment_setup {
    paying_cinema,
    paid,
    hire,
    ANNA,
    fresh_phone,
    settle
}
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.snack_setup { snack_menu, owner_call }

test "paid additions keep the booking and pickup, including after collection" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, cinema, screening) = paying_cinema(["clara", "rival"]);
    try {
        hire(app, "clara", "box_office_agent", cinema.venue);
        made = snack_menu(app, cinema.venue);
        paid(app, screening);
        original = browse(
            app,
            "my_payment",
            {"slug": "nova", "screening_id": screening, "holder": ANNA}
        )["payment"];
        token = original["link"].split("/")[-1];
        before = browse(app, "tickets_by_link", {"slug": "nova", "token": token})[
            "booking"
        ];
        args = {
            "slug": "nova",
            "token": token,
            "action": "place",
            "holder": f"extra-{uuid.uuid4().hex}",
            "key": f"extra-{uuid.uuid4().hex}",
            "lines": [{"variant_id": made["coke_v"], "quantity": 1}]
        };
        first = browse(app, "more_snacks", args);
        assert first["ok"] and first["order"]["total_cents"] == 15000 , first;
        assert browse(app, "more_snacks", args)["order"]["reference"]
            == first["order"]["reference"];
        levels = owner_call(app, "snack_stock_levels", {"venue_id": cinema.venue})[
            "levels"
        ];
        assert [
            l
            for l in levels
            if l["variant_id"] == made["coke_v"]
        ][0]["reserved"]
            == 1;
        assert browse(app, "tickets_by_link", {"slug": "nova", "token": token})[
            "booking"
        ]["snacks"]
            == [];
        args["action"] = "pay";
        args["phone"] = fresh_phone();
        args["email"] = "anna@example.com";
        payment = browse(app, "more_snacks", args);
        assert payment["ok"] and payment["payment"]["amount_cents"] == 15000 , payment;
        settle(app, screening, payment["payment"]["reference"]);
        after = browse(app, "tickets_by_link", {"slug": "nova", "token": token})[
            "booking"
        ];
        assert after["tickets"] == before["tickets"];
        assert len(after["snacks"]) == 1;
        pickup = after["pickup"]["reference"];
        # Staff may add by the reference, but only staff of this cinema at this venue.
        counter = {
            "tenant": "nova",
            "reference": after["reference"],
            "action": "place",
            "holder": f"extra-{uuid.uuid4().hex}",
            "key": f"extra-{uuid.uuid4().hex}",
            "lines": [{"variant_id": made["coke_v"], "quantity": 1}]
        };
        assert not app.call("rival", "counter_more_snacks", counter)["ok"];
        assert code_of(browse(app, "more_snacks", {"slug": "nova", "token": "wrong"}))
            == "not_found";
        app.call(
            "owner",
            "rd_freeze",
            {"slug": "nova", "screening_id": screening, "minutes": -30}
        );
        assert app.call("clara", "hand_over_snacks", {"tenant": "nova", "code": pickup})[
            "ok"
        ];
        assert app.call("clara", "counter_more_snacks", counter)["ok"];
        counter["action"] = "cash";
        sold = app.call("clara", "counter_more_snacks", counter);
        assert sold["ok"] , sold;
        assert sold["order"]["pickup_reference"] == pickup;
        waiting = app.call("clara", "snack_pickup", {"tenant": "nova", "code": pickup})[
            "pickup"
        ];
        assert len(waiting["snacks"]) == 1 and waiting["snacks"][0]["quantity"] == 1;
        assert not waiting["collected_at"];
        assert app.call("clara", "hand_over_snacks", {"tenant": "nova", "code": pickup})[
            "ok"
        ];
        assert code_of(
            app.call("clara", "hand_over_snacks", {"tenant": "nova", "code": pickup})
        )
            == "already_collected";
        app.call(
            "owner",
            "rd_freeze",
            {"slug": "nova", "screening_id": screening, "minutes": 0}
        );
        counter["action"] = "place";
        counter["key"] = f"extra-{uuid.uuid4().hex}";
        assert code_of(app.call("clara", "counter_more_snacks", counter))
            == "showtime_started";
    } finally {
        app.call("owner", "rd_unfreeze");
        app.close();
    }
}
