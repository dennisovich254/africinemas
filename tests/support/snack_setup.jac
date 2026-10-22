"""A cinema's snacks for the menu and order tests (P12.6, P12.7).

snack_menu(app, venue): the usual categories; Popcorn (Small KES 200, Large KES 400, and
KES 450 at `venue`) with extras (Butter KES 30, Caramel KES 50, up to two); Coca-Cola
(stock tracked, 3 received at `venue`); Fanta; a Movie Night Combo (KES 700: a Large
Popcorn and two drinks, Coca-Cola or Fanta); and a draft, Nachos. Returns the ids the
tests use.
"""

import from tests.support.served { Served }

def owner_call(app: Served, name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
    got = app.call("owner", name, {"tenant": "nova", ** args});
    assert got["ok"] , (name, got);
    return got;
}

def _row(values: list[str], price: int, tracked: bool = False) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "variant_id": "",
        "option_values": values,
        "sku": "",
        "barcode": "",
        "price_cents": price,
        "available": True,
        "track_stock": tracked
    };
}

def _product(
    app: Served,
    name: str,
    category_id: str,
    kind: str,
    rows: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return owner_call(
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
        }
    )["product"];
}

def snack_menu(app: Served, venue: str) -> dict[str, any] {  # jac:ignore[W1037]
    kinds = {
        c["name"]: c["category_id"]
        for c in owner_call(app, "add_default_snack_categories", {})["categories"]
    };
    popcorn = _product(
        app,
        "Popcorn",
        kinds["Popcorn"],
        "variants",
        [_row(["Small"], 20000), _row(["Large"], 40000)]
    );
    coke = _product(
        app, "Coca-Cola", kinds["Beverages"], "single", [_row([], 15000, True)]
    );
    fanta = _product(app, "Fanta", kinds["Beverages"], "single", [_row([], 15000)]);
    combo = _product(
        app, "Movie Night Combo", kinds["Combos & Deals"], "combo", [_row([], 70000)]
    );
    _product(app, "Nachos", kinds["Hot Food"], "single", [_row([], 25000)]);
    small = popcorn["variants"][0]["variant_id"];
    large = popcorn["variants"][1]["variant_id"];
    coke_v = coke["variants"][0]["variant_id"];
    fanta_v = fanta["variants"][0]["variant_id"];
    for p in [popcorn, coke, fanta] {
        owner_call(app, "publish_snack_product", {"product_id": p["product_id"]});
    }
    owner_call(
        app,
        "set_snack_combo_components",
        {
            "product_id": combo["product_id"],
            "components": [
                {"label": "Popcorn", "quantity": 1, "variant_ids": [large]},
                {"label": "Drinks", "quantity": 2, "variant_ids": [coke_v, fanta_v]}
            ]
        }
    );
    owner_call(app, "publish_snack_product", {"product_id": combo["product_id"]});
    group = owner_call(
        app,
        "save_snack_addon_group",
        {
            "group_id": "",
            "name": "Popcorn extras",
            "label": "Choose your extras",
            "min_picks": 0,
            "max_picks": 2,
            "repeatable": False,
            "options": [
                {"name": "Butter", "price_cents": 3000},
                {"name": "Caramel", "price_cents": 5000}
            ]
        }
    )["group"];
    owner_call(
        app,
        "set_snack_product_addons",
        {"product_id": popcorn["product_id"], "group_ids": [group["group_id"]]}
    );
    owner_call(
        app,
        "set_snack_venue_price",
        {
            "product_id": popcorn["product_id"],
            "variant_id": large,
            "venue_id": venue,
            "price_cents": 45000
        }
    );
    owner_call(
        app,
        "adjust_snack_stock",
        {
            "product_id": coke["product_id"],
            "variant_id": coke_v,
            "venue_id": venue,
            "reason": "received",
            "quantity": 3,
            "note": ""
        }
    );
    return {
        "popcorn": popcorn["product_id"],
        "coke": coke["product_id"],
        "small": small,
        "large": large,
        "coke_v": coke_v,
        "fanta_v": fanta_v,
        "combo_v": combo["variants"][0]["variant_id"],
        "butter": group["options"][0]["option_id"],
        "caramel": group["options"][1]["option_id"]
    };
}
