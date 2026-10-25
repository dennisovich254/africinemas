"""P12.11: mixed and snacks-only sales reconcile; inventory is current and scoped."""

import uuid;
import from tests.support.served { Served }
import from tests.support.payment_setup { paying_cinema, fresh_phone, settle, hire }
import from tests.support.snack_setup { snack_menu, owner_call }
import from tests.support.storefront_setup { browse, code_of, open_cinema_for }

def _report(app: Served, venue: str = "", who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "sales_report",
        {"tenant": "nova", "date_from": "", "date_to": "", "venue_id": venue}
    );
}

def _snack_order(app: Served, venue: str, cart: list[dict[str, any]]) -> str {  # jac:ignore[W1037]
    holder = f"counter-{uuid.uuid4().hex}";
    owner_call(
        app,
        "place_snack_order",
        {
            "venue_id": venue,
            "holder": holder,
            "idempotency_key": f"snacks-{uuid.uuid4().hex}",
            "snacks": cart
        }
    );
    return holder;
}

test "reports split mixed M-Pesa and snacks-only cash, with stock per venue" {
    (app, nova, screening) = paying_cinema(["finance", "rival"]);
    try {
        made = snack_menu(app, nova.venue);
        hire(app, "finance", "finance_manager", "");
        kiosk = owner_call(
            app, "create_venue", {"name": "Kiosk", "city": "Nairobi", "address": ""}
        )["venue"]["venue_id"];
        owner_call(
            app,
            "adjust_snack_stock",
            {
                "product_id": made["coke"],
                "variant_id": made["coke_v"],
                "venue_id": kiosk,
                "reason": "received",
                "quantity": 2,
                "note": ""
            }
        );
        holder = f"holder-{uuid.uuid4().hex}";
        where = {"slug": "nova", "screening_id": screening, "holder": holder};
        assert browse(app, "hold_seats", {** where, "labels": ["A3"]})["ok"];
        ordered = browse(
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
                    {"variant_id": made["coke_v"], "quantity": 1}
                ]
            }
        );
        assert ordered["ok"] and ordered["order"]["total_cents"] == 156000 , ordered;
        started = browse(
            app,
            "start_payment",
            {
                ** where,
                "phone": fresh_phone(),
                "email": "buyer@example.com",
                "idempotency_key": f"pay-{uuid.uuid4().hex}"
            }
        );
        assert started["ok"] , started;
        settle(app, screening, started["payment"]["reference"]);
        cash = _snack_order(
            app,
            kiosk,
            [
                {"variant_id": made["small"], "quantity": 2},
                {"variant_id": made["coke_v"], "quantity": 1}
            ]
        );
        owner_call(app, "sell_snacks_for_cash", {"venue_id": kiosk, "holder": cash});
        # An unpaid order reserves the last Coke but must not count as a sale.
        _snack_order(app, kiosk, [{"variant_id": made["coke_v"], "quantity": 1}]);
        # Changing today's menu price cannot rewrite a paid order's amounts.
        owner_call(
            app,
            "set_snack_venue_price",
            {
                "product_id": made["popcorn"],
                "variant_id": made["large"],
                "venue_id": nova.venue,
                "price_cents": 99000
            }
        );
        got = _report(app);
        assert got["ok"] , got;
        sales = got["report"];
        money = sales["takings"];
        assert [money["net_cents"], money["tickets_cents"], money["snacks_cents"]]
            == [211000, 93000, 118000] , money;
        assert money["mpesa_cents"] == 156000 and money["cash_cents"] == 55000;
        assert money["online_cents"] == 156000 and money["counter_cents"] == 55000;
        assert sum(v["takings_net_cents"] for v in sales["venues"]) == 211000;
        snacks = sales["snacks"];
        assert snacks["units"] == 5 and snacks["sales_cents"] == 118000 , snacks;
        assert [
            [r["name"], r["quantity"], r["revenue_cents"]]
            for r in snacks["top_products"]
        ]
            == [["Popcorn", 3, 88000], ["Coca-Cola", 2, 30000]];
        assert [r["revenue_cents"] for r in snacks["top_variants"]]
            == [48000, 40000, 30000];
        levels = {r["venue_id"]: r for r in snacks["low_stock"]};
        assert levels[nova.venue]["available"] == 2;
        assert levels[nova.venue]["status"] == "low";
        assert levels[nova.venue]["few_left"];
        assert levels[nova.venue]["low_threshold"] == 0;
        assert levels[kiosk]["on_hand"] == 1 and levels[kiosk]["reserved"] == 1;
        assert levels[kiosk]["available"] == 0 and levels[kiosk]["status"] == "out";
        assert not levels[kiosk]["few_left"];
        assert {v["venue_id"] for v in got["venues"]} == {nova.venue, kiosk};
        one = _report(app, kiosk)["report"];
        assert one["takings"]["net_cents"] == one["takings"]["snacks_cents"] == 55000;
        assert one["takings"]["tickets_cents"] == 0;
        assert one["snacks"]["units"] == 3;
        assert one["venues"][0]["name"] == "Kiosk"
            and one["venues"][0]["screens"] == [];
        assert [r["venue_id"] for r in one["snacks"]["low_stock"]] == [kiosk];
        # Financial-report permission covers these read-only inventory summaries.
        finance = _report(app, who="finance")["report"]["snacks"];
        assert finance["top_products"] == snacks["top_products"];
        assert finance["low_stock"] == snacks["low_stock"];
        # Historical sales are empty, but stock still describes now.
        past = owner_call(
            app,
            "sales_report",
            {"date_from": "2020-01-01", "date_to": "2020-01-01", "venue_id": kiosk}
        )["report"];
        assert past["snacks"]["units"] == 0;
        assert past["snacks"]["low_stock"] == one["snacks"]["low_stock"];
        owner_call(app, "archive_snack_product", {"product_id": made["coke"]});
        after = _report(app)["report"]["snacks"];
        assert after["low_stock"] == [];
        assert after["sales_cents"] == 118000;
        # Another cinema cannot read these products or counts.
        assert code_of(_report(app, who="rival")) == "not_found";
        open_cinema_for(app, "rival", "rift", "Rift Cinemas");
        other = app.call(
            "rival",
            "sales_report",
            {"tenant": "rift", "date_from": "", "date_to": "", "venue_id": ""}
        );
        assert other["ok"] , other;
        assert other["report"]["snacks"]["top_products"] == [];
        assert other["report"]["snacks"]["low_stock"] == [];
    } finally {
        app.close();
    }
}

test "a short snack payment owed back has no net takings or sold products" {
    (app, nova, _) = paying_cinema([]);
    try {
        made = snack_menu(app, nova.venue);
        holder = _snack_order(
            app, nova.venue, [{"variant_id": made["small"], "quantity": 1}]
        );
        started = owner_call(
            app,
            "sell_snacks_with_mpesa",
            {
                "venue_id": nova.venue,
                "holder": holder,
                "phone": fresh_phone(),
                "email": "",
                "idempotency_key": f"pay-{uuid.uuid4().hex}"
            }
        );
        forged = app.call(
            "owner",
            "pay_forged",
            {
                "slug": "nova",
                "screening_id": "",
                "reference": started["payment"]["reference"],
                "code": 0,
                "cents": 10000,
                "receipt": "SHORTSNACK01"
            }
        );
        app.client.set_auth_token("");
        response = app.client.post(
            f"/hooks/mpesa/{forged['token']}", json=forged["body"]
        );
        assert response.status_code == 200;
        app.call("owner", "pay_process");
        got = _report(app)["report"];
        assert got["takings"]["gross_cents"] == 10000;
        assert got["takings"]["refunds_cents"] == 10000;
        assert got["takings"]["net_cents"] == 0;
        assert got["takings"]["tickets_cents"] == 0;
        assert got["takings"]["snacks_cents"] == 0;
        assert got["snacks"]["units"] == 0;
        assert got["snacks"]["top_products"] == [];
    } finally {
        app.close();
    }
}
