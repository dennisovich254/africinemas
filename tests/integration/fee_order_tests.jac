"""P15.2: AfriCinemas' fee on every paid order.

In-process app (payment_app.jac). Anna's storefront order is paid by M-Pesa: 7% of its
tickets, frozen on the order with the standard rule, once even when Safaricom's callback
comes twice. A cash sale at the box office with snacks pays 3% on everything. When the
super admin agrees other rates with Nova, its next order uses them and the earlier ones
don't change; going back to the standard works the same way. Refunds credit the fee for
M-Pesa or a Platform failure, never for cash. The report adds up (net takings = fees +
the cinema's share), and each cinema sees only its own rates.
"""

import os;
import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of, open_cinema_for }
import from tests.support.payment_setup { paying_cinema, paid, settle, hire, ANNA }
import from tests.support.snack_setup { snack_menu }
import from tests.support.platform_setup { ADMINS_ENV, super_admin }

glob BOSS: str = "boss@example.com";

def _fees(app: Served, screening: str) -> dict[str, dict[str, any]] {  # jac:ignore[W1037]
    # reference -> the order's fee, for the confirmed orders.
    return {
        o["reference"]: o
        for o in browse(
            app, "t_order_fees", {"slug": "nova", "screening_id": screening}
        )
        if o["status"] == "confirmed"
    };
}

def _counter_cash(
    app: Served,
    screening: str,
    seats: list[str],
    snacks: list[dict[str, any]] | None = None  # jac:ignore[W1037]
) -> any {  # jac:ignore[W1037]
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": "nova", "screening_id": screening, "holder": holder};
    assert browse(app, "hold_seats", {** where, "labels": seats})["ok"];
    ordered = browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": s, "ticket_type": "ADULT"} for s in seats],
            "snacks": snacks or []
        }
    );
    assert ordered["ok"] , ordered;
    return app.call(
        "agent",
        "sell_for_cash",
        {"tenant": "nova", "screening_id": screening, "holder": holder, "email": ""}
    );
}

test "the fee is frozen on each paid order, at the rule in force for its cinema" {
    (app, nova, screening) = paying_cinema(["agent", "rival"]);
    try {
        super_admin(app, "boss", BOSS);
        hire(app, "agent", "box_office_agent", nova.venue);
        made = snack_menu(app, nova.venue);
        # Online, by M-Pesa: 7% of the tickets, under the standard rule.
        reference = paid(app, screening);
        online = list(_fees(app, screening).values())[0];
        assert online["fee_detail"]["channel"] == "online";
        assert online["fee_detail"]["rule_scope"] == "platform";
        assert online["fee_cents"] == (online["total_cents"] * 700 + 5000) // 10000;
        assert online["entries"] == [["fee", online["fee_cents"]]];
        # Safaricom's callback again: still one fee.
        settle(app, screening, reference);
        assert list(_fees(app, screening).values())[0]["entries"]
            == [["fee", online["fee_cents"]]];
        # Cash at the box office, with a snack: 3% of everything.
        sold = _counter_cash(
            app, screening, ["A3"], [{"variant_id": made["coke_v"], "quantity": 1}]
        );
        assert sold["ok"] , sold;
        counter = [
            o
            for o in _fees(app, screening).values()
            if o["fee_detail"]["channel"] == "counter"
        ][0];
        assert counter["fee_cents"] == (counter["total_cents"] * 300 + 5000) // 10000;
        assert sorted([p["category"] for p in counter["fee_detail"]["parts"]])
            == ["snacks", "tickets"];
        # Nova negotiates: its own rates from today.
        today = app.call("boss", "fee_rules", {})["today"];
        agreed = app.call(
            "boss",
            "set_cinema_fee_terms",
            {
                "slug": "nova",
                "standard": False,
                "online_ticket_percent": 5,
                "online_snack_percent": 15,
                "counter_percent": 2,
                "applies_from": today,
                "note": "Pilot terms, 2026"
            }
        );
        assert agreed["ok"] , agreed;
        terms = app.call("boss", "cinema_fee_terms", {"slug": "nova"});
        assert terms["current"]["scope"] == "cinema"
            and terms["current"]["counter_bp"] == 200;
        assert app.call("owner", "my_fee_rates", {"tenant": "nova"})["agreed"];
        sold = _counter_cash(app, screening, ["A4"]);
        assert sold["ok"] , sold;
        fees = _fees(app, screening);
        newest = [
            o
            for o in fees.values()
            if o["fee_detail"]["rule_scope"] == "cinema"
        ][0];
        assert newest["fee_cents"] == (newest["total_cents"] * 200 + 5000) // 10000;
        # The earlier orders keep their fees.
        assert fees[online["reference"]]["fee_cents"] == online["fee_cents"];
        assert fees[counter["reference"]]["fee_cents"] == counter["fee_cents"];
        # Only super admins set terms; another cinema stays on the standard.
        assert not app.call(
            "owner",
            "set_cinema_fee_terms",
            {
                "slug": "nova",
                "standard": True,
                "online_ticket_percent": 0,
                "online_snack_percent": 0,
                "counter_percent": 0,
                "applies_from": "2099-01-01",
                "note": ""
            }
        )["ok"];
        open_cinema_for(app, "rival", "rift", "Rift");
        assert not app.call("rival", "my_fee_rates", {"tenant": "rift"})["agreed"];
        assert not app.call("rival", "my_fee_rates", {"tenant": "nova"})["ok"];
    } finally {
        os.environ.pop(ADMINS_ENV, None);
        app.close();
    }
}

test "refunds credit the fee for M-Pesa or a Platform failure, never for cash" {
    (app, nova, screening) = paying_cinema(["agent"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        paid(app, screening);
        online = list(_fees(app, screening).values())[0];
        half = online["total_cents"] // 2;
        where = {
            "slug": "nova",
            "screening_id": screening,
            "reference": online["reference"]
        };
        credited = browse(
            app,
            "t_refund",
            {
                ** where,
                "amount_cents": half,
                "method": "mpesa",
                "platform_failure": False
            }
        );
        assert credited["fee_credited_cents"]
            == (online["fee_cents"] * half * 2 + online["total_cents"])
                // (2 * online["total_cents"]) , (credited, online);
        cash = browse(
            app,
            "t_refund",
            {** where, "amount_cents": 100, "method": "cash", "platform_failure": False}
        );
        assert cash["fee_credited_cents"] == 0 , cash;
        failure = browse(
            app,
            "t_refund",
            {** where, "amount_cents": 100, "method": "cash", "platform_failure": True}
        );
        assert failure["fee_credited_cents"] > 0;
        entries = _fees(app, screening)[online["reference"]]["entries"];
        assert [k for (k, _) in entries]
            == ["fee", "fee_credit", "fee_credit"] , entries;
        # The report: net takings are AfriCinemas' fees plus the cinema's share.
        today = app.call(
            "owner", "sales_report", {"tenant": "nova", "date_from": "", "date_to": ""}
        )["today"];
        shown = app.call(
            "owner",
            "sales_report",
            {"tenant": "nova", "date_from": today, "date_to": today}
        )["report"];
        fees = shown["fees"];
        assert fees["fees_cents"] == sum([a for (_, a) in entries]) , fees;
        assert fees["fees_cents"] + fees["cinema_share_cents"]
            == shown["takings"]["net_cents"];
    } finally {
        app.close();
    }
}

test "partial refunds credit exactly the fee in all, and never more than was paid" {
    (app, _, screening) = paying_cinema([]);
    try {
        paid(app, screening);
        online = list(_fees(app, screening).values())[0];
        total = online["total_cents"];
        where = {
            "slug": "nova",
            "screening_id": screening,
            "reference": online["reference"],
            "method": "mpesa",
            "platform_failure": False
        };
        # Three refunds that add up to the whole order: the credits add up to the
        # whole fee, to the cent, however each one rounds.
        third = total // 3;
        credits = 0;
        for amount in [third, third, total - 2 * third] {
            done = browse(app, "t_refund", {** where, "amount_cents": amount});
            assert "refused" not in done , done;
            credits += done["fee_credited_cents"];
        }
        assert credits == online["fee_cents"] , (credits, online);
        # Nothing is left to refund: one cent more is refused.
        more = browse(app, "t_refund", {** where, "amount_cents": 1});
        assert "refused" in more , more;
    } finally {
        app.close();
    }
}
