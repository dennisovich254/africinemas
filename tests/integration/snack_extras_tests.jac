"""P12.3: add-on groups and combos (core/snacks/extras_api.jac). Design guide §5.

In-process app (tests/apps/payment_app.jac): Nova with Westgate, its owner on shift.
- An add-on group ("Popcorn extras": butter +30, caramel +50, pick up to 2) is saved,
  checked by field, attached to Popcorn and shown as used by it; edited, its options
  keep their ids and venue switches; it can't be deleted while attached. The box office
  marks an add-on unavailable at their venue only.
- A combo (Movie Night Combo, KES 700) includes one Large Popcorn and a choice of two
  drinks; components come from this cinema's non-combo products only; it can't be
  published without them, and a product that isn't a combo can't have them.
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

def _row(values: list[str], sku: str, price: int) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "variant_id": "",
        "option_values": values,
        "sku": sku,
        "barcode": "",
        "price_cents": price,
        "available": True,
        "track_stock": False
    };
}

def _product(
    app: Served,
    name: str,
    category_id: str,
    kind: str,
    rows: list[dict[str, any]],  # jac:ignore[W1037]
    tenant: str = "nova"
) -> dict[str, any] {  # jac:ignore[W1037]
    made = _call(
        app,
        "save_snack_product",
        {
            "product_id": "",
            "name": name,
            "brand": "",
            "description": "",
            "tags": [],
            "category_id": category_id,
            "kind": kind,
            "option_names": ["Size"] if kind == "variants" else [],
            "variants": rows
        },
        "owner",
        tenant
    );
    assert made["ok"] , made;
    return made["product"];
}

def _menu(app: Served) -> dict[str, any] {  # jac:ignore[W1037]
    # Popcorn (Small, Large), Coke and Fanta, and an empty Movie Night Combo.
    kinds = {
        c["name"]: c["category_id"]
        for c in _call(app, "add_default_snack_categories", {})["categories"]
    };
    popcorn = _product(
        app,
        "Popcorn",
        kinds["Popcorn"],
        "variants",
        [_row(["Small"], "POP-SM", 20000), _row(["Large"], "POP-LG", 40000)]
    );
    coke = _product(
        app,
        "Coca-Cola 500 ml",
        kinds["Beverages"],
        "single",
        [_row([], "COKE-500", 15000)]
    );
    fanta = _product(
        app,
        "Fanta 500 ml",
        kinds["Beverages"],
        "single",
        [_row([], "FANTA-500", 15000)]
    );
    combo = _product(
        app,
        "Movie Night Combo",
        kinds["Combos & Deals"],
        "combo",
        [_row([], "COMBO-MN", 70000)]
    );
    return {"popcorn": popcorn, "coke": coke, "fanta": fanta, "combo": combo};
}

def _extras(
    app: Served, options: list[dict[str, any]], group_id: str = "", who: str = "owner"
) -> any {  # jac:ignore[W1037]
    return _call(
        app,
        "save_snack_addon_group",
        {
            "group_id": group_id,
            "name": "Popcorn extras",
            "label": "Choose your extras",
            "min_picks": 0,
            "max_picks": 2,
            "repeatable": False,
            "options": options
        },
        who
    );
}

test "an add-on group is shared by the products it's attached to" {
    (app, nova, _) = paying_cinema([]);
    try {
        menu = _menu(app);
        made = _extras(
            app,
            [
                {"name": "Extra butter", "price_cents": 3000},
                {"name": "Caramel", "price_cents": 5000}
            ]
        );
        assert made["ok"] , made;
        group = made["group"];
        assert [o["price_cents"] for o in group["options"]] == [3000, 5000];
        pid = menu["popcorn"]["product_id"];
        attached = _call(
            app,
            "set_snack_product_addons",
            {"product_id": pid, "group_ids": [group["group_id"]]}
        );
        assert attached["ok"]
            and attached["product"]["addon_group_ids"]
                == [group["group_id"]] , attached;
        listed = _call(app, "list_snack_addon_groups", {})["groups"];
        assert listed[0]["used_by"] == 1;
        # Caramel off at Westgate, then a third add-on: caramel keeps its id and switch.
        caramel = group["options"][1];
        off = _call(
            app,
            "set_snack_addon_availability",
            {
                "group_id": group["group_id"],
                "option_id": caramel["option_id"],
                "venue_id": nova.venue,
                "available": False
            }
        );
        assert off["ok"] , off;
        edited = _extras(
            app,
            group["options"] + [{"name": "Cheese", "price_cents": 4000}],
            group["group_id"]
        );
        assert edited["ok"] , edited;
        kept = [
            o
            for o in edited["group"]["options"]
            if o["name"] == "Caramel"
        ][0];
        assert kept["option_id"] == caramel["option_id"]
            and kept["off_at"] == [nova.venue];
        # In use, it stays; detached, it goes.
        assert code_of(
            _call(app, "delete_snack_addon_group", {"group_id": group["group_id"]})
        )
            == "addon_in_use";
        _call(app, "set_snack_product_addons", {"product_id": pid, "group_ids": []});
        assert _call(app, "delete_snack_addon_group", {"group_id": group["group_id"]})[
            "ok"
        ];
        assert code_of(
            _call(
                app,
                "set_snack_product_addons",
                {"product_id": pid, "group_ids": ["nope"]}
            )
        )
            == "not_found";
    } finally {
        app.close();
    }
}

test "add-on groups are checked by field" {
    (app, _, _) = paying_cinema([]);
    try {
        bad = _extras(
            app,
            [
                {"name": "Butter", "price_cents": -5},
                {"name": "butter", "price_cents": 0}
            ]
        );
        assert code_of(bad) == "invalid_addon_group" , bad;
        assert sorted([p["field"] for p in bad["error"]["problems"]])
            == ["options[0].price_cents", "options[1].name"];
    } finally {
        app.close();
    }
}

test "the box office marks add-ons unavailable at their venue only" {
    (app, nova, _) = paying_cinema(["agent"]);
    try {
        junction = app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Junction", "city": "Nairobi", "address": ""}
        )["venue"]["venue_id"];
        group = _extras(
            app,
            [
                {"name": "Extra butter", "price_cents": 3000},
                {"name": "Caramel", "price_cents": 5000}
            ]
        )["group"];
        option_id = group["options"][0]["option_id"];
        hire(app, "agent", "box_office_agent", nova.venue);
        assert _call(
            app,
            "set_snack_addon_availability",
            {
                "group_id": group["group_id"],
                "option_id": option_id,
                "venue_id": nova.venue,
                "available": False
            },
            "agent"
        )["ok"];
        assert code_of(
            _call(
                app,
                "set_snack_addon_availability",
                {
                    "group_id": group["group_id"],
                    "option_id": option_id,
                    "venue_id": junction,
                    "available": False
                },
                "agent"
            )
        )
            == "forbidden";
        assert code_of(_extras(app, [{"name": "Salt", "price_cents": 0}], "", "agent"))
            == "forbidden";
    } finally {
        app.close();
    }
}

test "a combo includes fixed and chosen items, and needs them to be published" {
    (app, _, _) = paying_cinema([]);
    try {
        menu = _menu(app);
        combo_id = menu["combo"]["product_id"];
        large = menu["popcorn"]["variants"][1]["variant_id"];
        coke = menu["coke"]["variants"][0]["variant_id"];
        fanta = menu["fanta"]["variants"][0]["variant_id"];
        refused = _call(app, "publish_snack_product", {"product_id": combo_id});
        assert code_of(refused) == "cannot_publish" , refused;
        assert "components" in [p["field"] for p in refused["error"]["problems"]];
        set_up = _call(
            app,
            "set_snack_combo_components",
            {
                "product_id": combo_id,
                "components": [
                    {"label": "Popcorn", "quantity": 1, "variant_ids": [large]},
                    {"label": "Drinks", "quantity": 2, "variant_ids": [coke, fanta]}
                ]
            }
        );
        assert set_up["ok"] , set_up;
        parts = set_up["product"]["components"];
        assert [p["kind"] for p in parts] == ["fixed", "choice"];
        assert parts[0]["choices"][0]["name"] == "Popcorn · Large";
        assert parts[1]["quantity"] == 2;
        assert _call(app, "publish_snack_product", {"product_id": combo_id})["ok"];
        # Staff pick components from every variant that isn't a combo.
        names = [v["name"] for v in _call(app, "list_snack_variants", {})["variants"]];
        assert names
            == [
                "Coca-Cola 500 ml",
                "Fanta 500 ml",
                "Popcorn · Small",
                "Popcorn · Large"
            ] , names;
        # A combo can't include a combo, nor another cinema's product.
        no_nesting = _call(
            app,
            "set_snack_combo_components",
            {
                "product_id": combo_id,
                "components": [
                    {
                        "label": "Combo",
                        "quantity": 1,
                        "variant_ids": [menu["combo"]["variants"][0]["variant_id"]]
                    }
                ]
            }
        );
        assert code_of(no_nesting) == "invalid_components" , no_nesting;
        open_cinema_for(app, "owner", "rift", "Rift Cinemas");
        rift_kind = _call(
            app, "create_snack_category", {"name": "Snacks"}, "owner", "rift"
        )["category"]["category_id"];
        rift_nachos = _product(
            app, "Nachos", rift_kind, "single", [_row([], "NACHOS", 30000)], "rift"
        );
        elsewhere = _call(
            app,
            "set_snack_combo_components",
            {
                "product_id": combo_id,
                "components": [
                    {
                        "label": "Nachos",
                        "quantity": 1,
                        "variant_ids": [rift_nachos["variants"][0]["variant_id"]]
                    }
                ]
            }
        );
        assert code_of(elsewhere) == "invalid_components" , elsewhere;
        # Only a combo has components.
        assert code_of(
            _call(
                app,
                "set_snack_combo_components",
                {
                    "product_id": menu["popcorn"]["product_id"],
                    "components": [{"label": "X", "quantity": 1, "variant_ids": [coke]}]
                }
            )
        )
            == "not_a_combo";
    } finally {
        app.close();
    }
}
