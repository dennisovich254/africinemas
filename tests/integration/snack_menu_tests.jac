"""P12.6: the storefront's snack menu and a cart's price, from the server only.

In-process app (payment_app.jac). Nova sells Popcorn (Small KES 200, Large KES 400, and
KES 450 at its venue) with extras (Butter KES 30, Caramel KES 50, up to two), Coca-Cola
(stock tracked: 3 on hand), Fanta, and a Movie Night Combo (KES 700: a Large Popcorn and
two drinks, Coca-Cola or Fanta). A draft (Nachos) isn't sold. The menu for a showtime
lists them by category at the venue's prices, says few Coca-Colas are left, and drops
Coca-Cola when it runs out (the combo still sells, with Fanta). A cart is priced on the
server: extras add to a unit, a combo's choices don't; every problem is named.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { paying_cinema }

def _call(app: Served, name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
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
    return _call(
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

def _menu_setup(app: Served, venue: str) -> dict[str, any] {  # jac:ignore[W1037]
    kinds = {
        c["name"]: c["category_id"]
        for c in _call(app, "add_default_snack_categories", {})["categories"]
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
        _call(app, "publish_snack_product", {"product_id": p["product_id"]});
    }
    _call(
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
    _call(app, "publish_snack_product", {"product_id": combo["product_id"]});
    group = _call(
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
    _call(
        app,
        "set_snack_product_addons",
        {"product_id": popcorn["product_id"], "group_ids": [group["group_id"]]}
    );
    _call(
        app,
        "set_snack_venue_price",
        {
            "product_id": popcorn["product_id"],
            "variant_id": large,
            "venue_id": venue,
            "price_cents": 45000
        }
    );
    _call(
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

def _snacks(app: Served, screening: str) -> any {  # jac:ignore[W1037]
    return browse(app, "public_snacks", {"slug": "nova", "screening_id": screening});
}

def _price(app: Served, screening: str, lines: list[dict[str, any]]) -> any {  # jac:ignore[W1037]
    return browse(
        app, "price_snacks", {"slug": "nova", "screening_id": screening, "lines": lines}
    );
}

def _products(menu: any) -> dict[str, dict[str, any]] {  # jac:ignore[W1037]
    return {p["name"]: p for c in menu["categories"] for p in c["products"]};
}

test "the menu lists what's on sale at the showtime's venue, at its prices" {
    (app, nova, screening) = paying_cinema([]);
    try {
        made = _menu_setup(app, nova.venue);
        menu = _snacks(app, screening);
        assert menu["ok"] , menu;
        assert [c["name"] for c in menu["categories"]]
            == ["Popcorn", "Beverages", "Combos & Deals"] , menu;
        shown = _products(menu);
        assert "Nachos" not in shown , "a draft isn't sold";
        popcorn = shown["Popcorn"];
        assert [(v["label"], v["price_cents"]) for v in popcorn["variants"]]
            == [("Small", 20000), ("Large", 45000)] , popcorn["variants"];
        assert popcorn["from_cents"] == 20000;
        extras = popcorn["addon_groups"][0];
        assert extras["label"] == "Choose your extras" and extras["max_picks"] == 2;
        assert [o["name"] for o in extras["options"]] == ["Butter", "Caramel"];
        assert shown["Coca-Cola"]["variants"][0]["left"] == 3;
        assert shown["Fanta"]["variants"][0]["left"] is None;
        drinks = shown["Movie Night Combo"]["components"][1];
        assert [c["name"] for c in drinks["choices"]] == ["Coca-Cola", "Fanta"];
        # Coca-Cola runs out: it leaves the menu, and the combo sells with Fanta.
        _call(
            app,
            "adjust_snack_stock",
            {
                "product_id": made["coke"],
                "variant_id": made["coke_v"],
                "venue_id": nova.venue,
                "reason": "damaged",
                "quantity": 3,
                "note": ""
            }
        );
        after = _products(_snacks(app, screening));
        assert "Coca-Cola" not in after;
        assert [
            c["name"] for c in after["Movie Night Combo"]["components"][1]["choices"]
        ]
            == ["Fanta"];
        assert code_of(_snacks(app, "nope")) == "not_found";
    } finally {
        app.close();
    }
}

test "a cart is priced on the server, and every problem is named" {
    (app, nova, screening) = paying_cinema([]);
    try {
        made = _menu_setup(app, nova.venue);
        priced = _price(
            app,
            screening,
            [
                {
                    "variant_id": made["large"],
                    "quantity": 2,
                    "addons": [made["butter"], made["caramel"]]
                },
                {
                    "variant_id": made["combo_v"],
                    "quantity": 1,
                    "choices": [[], [made["coke_v"], made["fanta_v"]]]
                }
            ]
        );
        assert priced["ok"] , priced;
        large = priced["lines"][0];
        assert large["name"] == "Popcorn · Large";
        assert (large["unit_cents"], large["line_cents"]) == (53000, 106000) , large;
        combo = priced["lines"][1];
        assert combo["unit_cents"] == 70000 , "a combo's choices don't change its price";
        assert [c["name"] for c in combo["choices"]]
            == ["Popcorn · Large", "Coca-Cola", "Fanta"];
        assert priced["total_cents"] == 176000;
        # Every problem at once: three extras, a quantity of none, more Coca-Cola than
        # is left (the combo's counts too), and a snack that isn't sold.
        bad = _price(
            app,
            screening,
            [
                {
                    "variant_id": made["small"],
                    "quantity": 1,
                    "addons": [made["butter"], made["caramel"], made["butter"]]
                },
                {"variant_id": made["large"], "quantity": 0},
                {"variant_id": made["coke_v"], "quantity": 2},
                {
                    "variant_id": made["combo_v"],
                    "quantity": 1,
                    "choices": [[], [made["coke_v"], made["coke_v"]]]
                },
                {"variant_id": "nope", "quantity": 1}
            ]
        );
        assert code_of(bad) == "snacks_unavailable" , bad;
        codes = sorted(p["code"] for p in bad["error"]["problems"]);
        assert codes
            == ["ADDONS_COUNT", "NOT_ENOUGH", "QUANTITY", "SNACK_UNAVAILABLE"] , bad[
            "error"
        ]["problems"];
        short = [
            p
            for p in bad["error"]["problems"]
            if p["code"] == "NOT_ENOUGH"
        ][0];
        assert short["message"] == "Only 3 Coca-Cola left." , short;
    } finally {
        app.close();
    }
}
