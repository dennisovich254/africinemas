"""P12.2: snack availability and prices per venue (core/snacks/venue_api.jac).

In-process app (tests/apps/payment_app.jac): Nova with Westgate, plus Junction added
here. A product is sold at every venue unless switched off at one; each variant can be
unavailable at a venue and can have that venue's own price.

- The product's venues and the venue prices are managers' (concessions.manage).
- A variant's availability at a venue is the box office's too (concessions.availability
  at that venue): a venue-scoped agent changes only their venue.
- A venue price is whole cents in range, or none (back to the variant's price).
- A venue that isn't Nova's, or another cinema's product, is not_found. Every change is
  audited.
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

def _popcorn(app: Served) -> dict[str, any] {  # jac:ignore[W1037]
    kind = _call(app, "create_snack_category", {"name": "Popcorn"})["category"][
        "category_id"
    ];
    made = _call(
        app,
        "save_snack_product",
        {
            "product_id": "",
            "name": "Popcorn",
            "brand": "",
            "description": "",
            "tags": [],
            "category_id": kind,
            "kind": "variants",
            "option_names": ["Size"],
            "variants": [
                {
                    "variant_id": "",
                    "option_values": [size],
                    "sku": sku,
                    "barcode": "",
                    "price_cents": price,
                    "available": True,
                    "track_stock": False
                }
                for (size, sku, price) in [
                    ("Small", "POP-SM", 20000),
                    ("Large", "POP-LG", 40000)
                ]
            ]
        }
    );
    assert made["ok"] , made;
    return made["product"];
}

def _junction(app: Served) -> str {
    return app.call(
        "owner",
        "create_venue",
        {"tenant": "nova", "name": "Junction", "city": "Nairobi", "address": ""}
    )["venue"]["venue_id"];
}

test "a product is sold everywhere until switched off at a venue" {
    (app, nova, _) = paying_cinema([]);
    try {
        junction = _junction(app);
        product = _popcorn(app);
        assert product["off_at"] == [];
        pid = product["product_id"];
        only = _call(
            app,
            "set_snack_product_venues",
            {"product_id": pid, "venue_ids": [nova.venue]}
        );
        assert only["ok"] and only["product"]["off_at"] == [junction] , only;
        back = _call(
            app,
            "set_snack_product_venues",
            {"product_id": pid, "venue_ids": [nova.venue, junction]}
        );
        assert back["product"]["off_at"] == [];
        assert code_of(
            _call(
                app,
                "set_snack_product_venues",
                {"product_id": pid, "venue_ids": ["nope"]}
            )
        )
            == "not_found";
    } finally {
        app.close();
    }
}

test "a variant can be unavailable, or priced differently, at one venue" {
    (app, nova, _) = paying_cinema([]);
    try {
        junction = _junction(app);
        product = _popcorn(app);
        pid = product["product_id"];
        large = product["variants"][1]["variant_id"];
        off = _call(
            app,
            "set_snack_variant_availability",
            {
                "product_id": pid,
                "variant_id": large,
                "venue_id": junction,
                "available": False
            }
        );
        assert off["ok"] , off;
        assert off["product"]["variants"][1]["off_at"] == [junction];
        priced = _call(
            app,
            "set_snack_venue_price",
            {
                "product_id": pid,
                "variant_id": large,
                "venue_id": nova.venue,
                "price_cents": 45000
            }
        );
        assert priced["ok"] , priced;
        assert priced["product"]["variants"][1]["venue_prices"] == {nova.venue: 45000};
        bad = _call(
            app,
            "set_snack_venue_price",
            {
                "product_id": pid,
                "variant_id": large,
                "venue_id": nova.venue,
                "price_cents": 5
            }
        );
        assert code_of(bad) == "invalid_price" , bad;
        cleared = _call(
            app,
            "set_snack_venue_price",
            {
                "product_id": pid,
                "variant_id": large,
                "venue_id": nova.venue,
                "price_cents": None
            }
        );
        assert cleared["product"]["variants"][1]["venue_prices"] == {};
        # A variant of another product isn't this product's.
        assert code_of(
            _call(
                app,
                "set_snack_variant_availability",
                {
                    "product_id": pid,
                    "variant_id": "nope",
                    "venue_id": junction,
                    "available": False
                }
            )
        )
            == "not_found";
        actions = [
            e["action"] for e in _call(app, "audit_log", {"limit": 50})["events"]
        ];
        for action in [
            "snack_variant.availability_changed",
            "snack_variant.venue_price_set"
        ] {
            assert action in actions , (action, actions);
        }
    } finally {
        app.close();
    }
}

test "the box office flips availability at their venue only; prices are managers'" {
    (app, nova, _) = paying_cinema(["agent"]);
    try {
        junction = _junction(app);
        product = _popcorn(app);
        pid = product["product_id"];
        small = product["variants"][0]["variant_id"];
        hire(app, "agent", "box_office_agent", nova.venue);
        mine = _call(
            app,
            "set_snack_variant_availability",
            {
                "product_id": pid,
                "variant_id": small,
                "venue_id": nova.venue,
                "available": False
            },
            "agent"
        );
        assert mine["ok"] , mine;
        assert code_of(
            _call(
                app,
                "set_snack_variant_availability",
                {
                    "product_id": pid,
                    "variant_id": small,
                    "venue_id": junction,
                    "available": False
                },
                "agent"
            )
        )
            == "forbidden";
        assert code_of(
            _call(
                app,
                "set_snack_venue_price",
                {
                    "product_id": pid,
                    "variant_id": small,
                    "venue_id": nova.venue,
                    "price_cents": 25000
                },
                "agent"
            )
        )
            == "forbidden";
        assert code_of(
            _call(
                app,
                "set_snack_product_venues",
                {"product_id": pid, "venue_ids": [nova.venue]},
                "agent"
            )
        )
            == "forbidden";
    } finally {
        app.close();
    }
}

test "another cinema's products and venues are not found" {
    (app, nova, _) = paying_cinema([]);
    try {
        product = _popcorn(app);
        pid = product["product_id"];
        rift = open_cinema_for(app, "owner", "rift", "Rift Cinemas");
        assert code_of(
            _call(
                app,
                "set_snack_product_venues",
                {"product_id": pid, "venue_ids": [rift.venue]},
                "owner",
                "rift"
            )
        )
            == "not_found";
        assert code_of(
            _call(
                app,
                "set_snack_product_venues",
                {"product_id": pid, "venue_ids": [rift.venue]}
            )
        )
            == "not_found";
    } finally {
        app.close();
    }
}
