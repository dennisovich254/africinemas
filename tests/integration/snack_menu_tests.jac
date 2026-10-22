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
import from tests.support.snack_setup { owner_call as _call, snack_menu as _menu_setup }

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
