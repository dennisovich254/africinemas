"""Snacks for the browser tests (P12.8, P12.10): a cinema selling tickets whose venue sells
Popcorn (Small KES 200, Large KES 400, with Butter KES 30) and Coca-Cola (KES 150, stock
tracked).
"""

import from e2e.support.api { call }
import from e2e.support.catalog { cinema_selling_tickets }

def made_by(owner: dict[str, str], name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
    got = call(owner["token"], name, {"tenant": owner["slug"], ** args});
    assert got["ok"] , (name, got);
    return got;
}

def snack_row(values: list[str], price: int, tracked: bool = False) -> dict[str, any] {  # jac:ignore[W1037]
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

def snack_product(
    owner: dict[str, str],
    name: str,
    category: str,
    kind: str,
    rows: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    made = made_by(
        owner,
        "save_snack_product",
        {
            "product_id": "",
            "name": name,
            "brand": "",
            "description": "",
            "tags": [],
            "category_id": category,
            "kind": kind,
            "option_names": ["Size"] if kind == "variants" else [],
            "variants": rows
        }
    )["product"];
    made_by(owner, "publish_snack_product", {"product_id": made["product_id"]});
    return made;
}

def with_snacks(starts_in_minutes: int = 0) -> dict[str, str] {
    owner = cinema_selling_tickets(starts_in_minutes=starts_in_minutes);
    kinds = {
        c["name"]: c["category_id"]
        for c in made_by(owner, "add_default_snack_categories", {})["categories"]
    };
    popcorn = snack_product(
        owner,
        "Popcorn",
        kinds["Popcorn"],
        "variants",
        [snack_row(["Small"], 20000), snack_row(["Large"], 40000)]
    );
    snack_product(
        owner, "Coca-Cola", kinds["Beverages"], "single", [snack_row([], 15000, True)]
    );
    group = made_by(
        owner,
        "save_snack_addon_group",
        {
            "group_id": "",
            "name": "Popcorn extras",
            "label": "Extras",
            "min_picks": 0,
            "max_picks": 1,
            "repeatable": False,
            "options": [{"name": "Butter", "price_cents": 3000}]
        }
    )["group"];
    made_by(
        owner,
        "set_snack_product_addons",
        {"product_id": popcorn["product_id"], "group_ids": [group["group_id"]]}
    );
    return owner;
}
