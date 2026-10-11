"""P12.4: stock per variant per venue (core/snacks/inventory_api.jac). Design guide §8.

In-process app (tests/apps/payment_app.jac): Nova with Westgate, its owner on shift,
and a Coca-Cola 500 ml whose stock is tracked.
- Stock levels list the tracked variants at a venue with on hand, reserved, available,
  their low-stock alert and status.
- An adjustment has a reason (received, damaged, count correction, other) and leaves a
  movement with the change, the stock after it, the note, who and when. Stock never
  goes below zero; an untracked variant has no stock to adjust.
- Stock rules per venue: the low-stock alert and what happens at zero.
- Reserving for an order (used from P12.7) takes only what's available: two orders
  can't both have the last bottle; committing a sale takes it off the shelf and records
  it; releasing gives it back.
- The box office adjusts stock at their venue only. Another cinema's anything is
  not_found.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, open_cinema_for }
import from tests.support.payment_setup { paying_cinema, hire }

def _call(
    app: Served,
    name: str,
    args: dict[str, any],
    who: str = "owner",
    tenant: str = "nova"
) -> any {  # jac:ignore[W1037]
    return app.call(who, name, {"tenant": tenant, ** args});
}

def _coke(app: Served, tracked: bool = True) -> dict[str, any] {  # jac:ignore[W1037]
    kind = _call(app, "create_snack_category", {"name": "Beverages"})["category"][
        "category_id"
    ];
    made = _call(
        app,
        "save_snack_product",
        {
            "product_id": "",
            "name": "Coca-Cola 500 ml",
            "brand": "Coca-Cola",
            "description": "",
            "tags": [],
            "category_id": kind,
            "kind": "single",
            "option_names": [],
            "variants": [
                {
                    "variant_id": "",
                    "option_values": [],
                    "sku": "COKE-500",
                    "barcode": "",
                    "price_cents": 15000,
                    "available": True,
                    "track_stock": tracked
                }
            ]
        }
    );
    assert made["ok"] , made;
    product = made["product"];
    return {
        "product_id": product["product_id"],
        "variant_id": product["variants"][0]["variant_id"]
    };
}

def _adjust(
    app: Served,
    coke: dict[str, any],  # jac:ignore[W1037]
    venue: str,
    reason: str,
    quantity: int,
    note: str = "",
    who: str = "owner"
) -> any {  # jac:ignore[W1037]
    return _call(
        app,
        "adjust_snack_stock",
        {
            ** coke,
            "venue_id": venue,
            "reason": reason,
            "quantity": quantity,
            "note": note
        },
        who
    );
}

def _level(app: Served, venue: str, who: str = "owner") -> dict[str, any] {  # jac:ignore[W1037]
    got = _call(app, "snack_stock_levels", {"venue_id": venue}, who);
    assert got["ok"] , got;
    return got["levels"][0] if got["levels"] else {};
}

test "adjustments have reasons, leave movements, and never go below zero" {
    (app, nova, _) = paying_cinema([]);
    try {
        coke = _coke(app);
        assert _level(app, nova.venue)["on_hand"] == 0;
        assert _adjust(app, coke, nova.venue, "received", 50, "Delivery")["ok"];
        damaged = _adjust(app, coke, nova.venue, "damaged", 3, "Three damaged bottles");
        assert damaged["ok"] and damaged["level"]["on_hand"] == 47 , damaged;
        counted = _adjust(app, coke, nova.venue, "count", 40, "Shelf count");
        assert counted["level"]["on_hand"] == 40;
        assert code_of(_adjust(app, coke, nova.venue, "damaged", 41))
            == "invalid_adjustment";
        assert code_of(_adjust(app, coke, nova.venue, "received", 0))
            == "invalid_adjustment";
        history = _call(
            app,
            "snack_stock_history",
            {"venue_id": nova.venue, "variant_id": coke["variant_id"], "limit": 10}
        );
        assert history["ok"] , history;
        moves = history["movements"];
        assert [m["reason"] for m in moves] == ["count", "damaged", "received"];
        assert [m["change"] for m in moves] == [-7, -3, 50];
        assert [m["on_hand_after"] for m in moves] == [40, 47, 50];
        assert moves[1]["note"] == "Three damaged bottles";
        assert moves[0]["by"] and moves[0]["at"];
        level = _level(app, nova.venue);
        assert (level["on_hand"], level["reserved"], level["available"]) == (40, 0, 40);
        assert level["status"] == "ok" and level["label"] == "Coca-Cola 500 ml";
    } finally {
        app.close();
    }
}

test "stock rules set the low-stock alert and what happens at zero" {
    (app, nova, _) = paying_cinema([]);
    try {
        coke = _coke(app);
        _adjust(app, coke, nova.venue, "received", 8);
        rules = _call(
            app,
            "set_snack_stock_rules",
            {
                ** coke,
                "venue_id": nova.venue,
                "low_threshold": 10,
                "at_zero": "unavailable"
            }
        );
        assert rules["ok"] , rules;
        level = _level(app, nova.venue);
        assert level["status"] == "low" and level["low_threshold"] == 10 , level;
        assert code_of(
            _call(
                app,
                "set_snack_stock_rules",
                {
                    ** coke,
                    "venue_id": nova.venue,
                    "low_threshold": -1,
                    "at_zero": "unavailable"
                }
            )
        )
            == "invalid_rules";
    } finally {
        app.close();
    }
}

test "an untracked variant has no stock to adjust" {
    (app, nova, _) = paying_cinema([]);
    try {
        coke = _coke(app, False);
        assert code_of(_adjust(app, coke, nova.venue, "received", 5)) == "not_tracked";
        assert _call(app, "snack_stock_levels", {"venue_id": nova.venue})["levels"]
            == [];
    } finally {
        app.close();
    }
}

test "reservations take only what's available; a sale leaves the shelf" {
    (app, nova, _) = paying_cinema([]);
    try {
        coke = _coke(app);
        _adjust(app, coke, nova.venue, "received", 1);
        args = {
            "variant_id": coke["variant_id"],
            "venue_id": nova.venue,
            "quantity": 1
        };
        assert _call(app, "t_reserve_snack_stock", args)["ok"];
        assert code_of(_call(app, "t_reserve_snack_stock", args)) == "out_of_stock";
        level = _level(app, nova.venue);
        assert (level["on_hand"], level["reserved"], level["available"]) == (1, 1, 0);
        assert level["status"] == "out";
        assert _call(app, "t_commit_snack_stock", {** args, "order_ref": "ORD1"})["ok"];
        level = _level(app, nova.venue);
        assert (level["on_hand"], level["reserved"]) == (0, 0);
        sale = _call(
            app,
            "snack_stock_history",
            {"venue_id": nova.venue, "variant_id": "", "limit": 1}
        )["movements"][0];
        assert sale["reason"] == "sale"
            and sale["change"] == -1
            and sale["note"] == "Order ORD1";
        # A released reservation goes back on sale.
        _adjust(app, coke, nova.venue, "received", 2);
        _call(app, "t_reserve_snack_stock", {** args, "quantity": 2});
        assert _call(app, "t_release_snack_stock", {** args, "quantity": 2})["ok"];
        assert _level(app, nova.venue)["available"] == 2;
    } finally {
        app.close();
    }
}

test "the box office adjusts stock at their venue only; other cinemas can't" {
    (app, nova, _) = paying_cinema(["agent"]);
    try {
        coke = _coke(app);
        junction = app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Junction", "city": "Nairobi", "address": ""}
        )["venue"]["venue_id"];
        hire(app, "agent", "box_office_agent", nova.venue);
        assert _adjust(app, coke, nova.venue, "received", 5, "", "agent")["ok"];
        assert code_of(_adjust(app, coke, junction, "received", 5, "", "agent"))
            == "forbidden";
        assert _level(app, nova.venue, "agent")["on_hand"] == 5;
        assert code_of(
            _call(app, "snack_stock_levels", {"venue_id": junction}, "agent")
        )
            == "forbidden";
        rift = open_cinema_for(app, "owner", "rift", "Rift Cinemas");
        assert code_of(_adjust(app, coke, rift.venue, "received", 5)) == "not_found";
        assert code_of(
            _call(
                app,
                "adjust_snack_stock",
                {
                    ** coke,
                    "venue_id": rift.venue,
                    "reason": "received",
                    "quantity": 5,
                    "note": ""
                },
                "owner",
                "rift"
            )
        )
            == "not_found";
    } finally {
        app.close();
    }
}
