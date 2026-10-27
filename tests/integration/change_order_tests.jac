"""Going back from paying to change the order (change_order).

In-process app (payment_app.jac). Anna has ordered two seats and a Coke and not paid.
She goes back: the order is cancelled, her seats are held for her again (nobody else
can take them), the Coke goes back on the shelf, and she orders again and pays. The job
that ends unpaid orders never gives the Coke back a second time. While an M-Pesa
request is out she can't go back, and nobody else can change her order.
"""

import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup {
    paying_cinema,
    pay,
    fresh_phone,
    settle,
    ANNA
}
import from tests.support.snack_setup { snack_menu, owner_call }

def _where(screening: str, holder: str = ANNA) -> dict[str, str] {
    return {"slug": "nova", "screening_id": screening, "holder": holder};
}

def _available(app: Served, venue: str, variant: str) -> int {
    levels = owner_call(app, "snack_stock_levels", {"venue_id": venue})["levels"];
    return [
        l
        for l in levels
        if l["variant_id"] == variant
    ][0]["available"];
}

def _order(app: Served, screening: str, snacks: list[dict[str, any]]) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "place_order",
        {
            ** _where(screening),
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [
                {"seat_label": "A1", "ticket_type": "ADULT"},
                {"seat_label": "A2", "ticket_type": "ADULT"}
            ],
            "snacks": snacks
        }
    );
}

test "going back cancels the unpaid order, keeps the seats and gives the snacks back" {
    (app, nova, screening) = paying_cinema([]);
    try {
        made = snack_menu(app, nova.venue);
        coke = [{"variant_id": made["coke_v"], "quantity": 1}];
        # paying_cinema left an order without snacks: change it into one with a Coke.
        assert browse(app, "change_order", _where(screening))["ok"];
        before = _available(app, nova.venue, made["coke_v"]);
        assert _order(app, screening, coke)["ok"];
        assert _available(app, nova.venue, made["coke_v"]) == before - 1;
        # Back again: the Coke returns, the seats stay Anna's.
        back = browse(app, "change_order", _where(screening));
        assert back["ok"] and back["hold"]["seats"] == ["A1", "A2"] , back;
        assert back["hold"]["status"] == "held";
        assert _available(app, nova.venue, made["coke_v"]) == before;
        assert code_of(browse(app, "my_order", _where(screening))) != "";
        assert browse(app, "my_hold", _where(screening))["hold"]["seats"]
            == ["A1", "A2"];
        taken = browse(
            app,
            "hold_seats",
            {** _where(screening, "holder-someone-else-0123456789"), "labels": ["A1"]}
        );
        assert not taken["ok"] , taken;
        # The job that ends unpaid orders leaves the cancelled one alone.
        app.call("owner", "pay_resolve");
        assert _available(app, nova.venue, made["coke_v"]) == before;
        # Nobody else can change her order; there's nothing left to change for her.
        assert code_of(
            browse(
                app, "change_order", _where(screening, "holder-someone-else-0123456789")
            )
        )
            == "no_order";
        assert code_of(browse(app, "change_order", _where(screening))) == "no_order";
        # She orders again, with the Coke, and pays: one order confirmed.
        assert _order(app, screening, coke)["ok"];
        started = pay(app, screening, fresh_phone());
        assert started["ok"] , started;
        # While the M-Pesa request is out, going back is refused.
        assert code_of(browse(app, "change_order", _where(screening)))
            == "payment_in_progress";
        settle(app, screening, started["payment"]["reference"]);
        overview = app.call(
            "owner", "pay_overview", {"slug": "nova", "screening_id": screening}
        );
        assert sorted(overview["orders"])
            == ["cancelled", "cancelled", "confirmed"] , overview;
        assert overview["tickets"] == ["A1", "A2"];
        assert _available(app, nova.venue, made["coke_v"]) == before - 1;
    } finally {
        app.close();
    }
}
