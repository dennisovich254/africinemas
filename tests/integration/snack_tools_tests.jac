"""P12.5: faster catalog work (core/snacks/tools_api.jac). Design guide §4.

In-process app (payment_app.jac): Nova with Westgate, its owner on shift.
- Duplicate makes a new draft "Copy of …" with the same variants and prices but no
  SKUs and no stock; it never reuses a SKU.
- The CSV import's preview reports every bad row (with its row number) and saves
  nothing; a good import makes the products and variants once, and running it again
  updates them instead of adding copies; missing categories are made only when asked.
- The export reads back as the same catalog.
- Bulk publish, archive and restore answer per product: one that can't be published
  says why, the others go through.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of }
import from tests.support.payment_setup { paying_cinema, hire }

glob GUIDE_CSV: str = """product_name,category,brand,variant,sku,price,currency
Popcorn,Popcorn,,Small,POP-SM,200,KES
Popcorn,Popcorn,,Medium,POP-MD,300,KES
Popcorn,Popcorn,,Large,POP-LG,400,KES
Coca-Cola,Beverages,Coca-Cola,300 ml,COKE-300,100,KES
Coca-Cola,Beverages,Coca-Cola,500 ml,COKE-500,150,KES
Doritos Nacho Cheese,Crisps & Chips,Doritos,45 g,DOR-NC-45,100,KES
""";

def _call(app: Served, name: str, args: dict[str, any], who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, name, {"tenant": "nova", ** args});
}

def _products(app: Served) -> dict[str, dict[str, any]] {  # jac:ignore[W1037]
    got = _call(
        app, "list_snack_products", {"search": "", "category_id": "", "status": ""}
    );
    return {p["name"]: p for p in got["products"]};
}

def _import(
    app: Served, text: str, create: bool = False, preview: bool = False
) -> any {  # jac:ignore[W1037]
    return _call(
        app,
        "preview_snack_import" if preview else "import_snack_catalog",
        {"csv_text": text, "mapping": {}, "create_categories": create}
    );
}

test "a CSV previews without saving, imports once, and re-imports as updates" {
    (app, _, _) = paying_cinema([]);
    try {
        _call(app, "add_default_snack_categories", {});
        preview = _import(app, GUIDE_CSV, False, True);
        assert preview["ok"] and preview["errors"] == [] , preview;
        assert preview["summary"]["products_created"] == 3;
        assert preview["summary"]["variants_created"] == 6;
        assert preview["mapping"]["sku"] == "sku";
        assert _products(app) == {} , "a preview saves nothing";
        done = _import(app, GUIDE_CSV);
        assert done["ok"] , done;
        listed = _products(app);
        assert sorted(listed.keys())
            == ["Coca-Cola", "Doritos Nacho Cheese", "Popcorn"];
        assert listed["Popcorn"]["variant_count"] == 3
            and listed["Popcorn"]["status"] == "draft";
        assert listed["Coca-Cola"]["price_from_cents"] == 10000;
        # Again, with a new price and a new size: updates, not copies.
        again = _import(
            app,
            GUIDE_CSV.replace("POP-SM,200", "POP-SM,250")
                + "Popcorn,Popcorn,,Jumbo,POP-JB,500,KES\n"
        );
        assert again["ok"] , again;
        assert again["summary"]["products_updated"] == 3
            and again["summary"]["variants_created"] == 1;
        listed = _products(app);
        assert len(listed) == 3 and listed["Popcorn"]["variant_count"] == 4;
        assert listed["Popcorn"]["price_from_cents"] == 25000;
    } finally {
        app.close();
    }
}

test "a bad file is refused row by row, and nothing is imported" {
    (app, _, _) = paying_cinema([]);
    try {
        _call(app, "add_default_snack_categories", {});
        bad = "product_name,category,variant,sku,price\nPopcorn,Popcorn,Small,POP-SM,200\nNachos,Hot Snacks,,NACHOS,abc\n";
        preview = _import(app, bad, False, True);
        assert sorted([(e["row"], e["field"]) for e in preview["errors"]])
            == [(3, "category"), (3, "price")] , preview;
        refused = _import(app, bad);
        assert code_of(refused) == "import_has_errors"
            and len(refused["error"]["errors"]) == 2 , refused;
        assert _products(app) == {};
        # With missing categories made, and the price fixed, it imports.
        fixed = bad.replace(",abc", ",300");
        made = _import(app, fixed, True);
        assert made["ok"] and made["summary"]["categories_created"] == 1 , made;
        names = [
            c["name"] for c in _call(app, "list_snack_categories", {})["categories"]
        ];
        assert "Hot Snacks" in names;
    } finally {
        app.close();
    }
}

test "the export reads back as the same catalog" {
    (app, _, _) = paying_cinema([]);
    try {
        _call(app, "add_default_snack_categories", {});
        _import(app, GUIDE_CSV);
        exported = _call(app, "export_snack_catalog", {});
        assert exported["ok"] , exported;
        lines = exported["csv"].splitlines();
        assert lines[0]
            == "product_name,category,brand,option,variant,sku,price,currency";
        assert "Popcorn,Popcorn,,Size,Small,POP-SM,200,KES" in lines;
        again = _import(app, exported["csv"], False, True);
        assert again["errors"] == [] and again["summary"]["products_updated"] == 3;
        assert again["summary"]["variants_created"] == 0;
    } finally {
        app.close();
    }
}

test "duplicate copies a product as a new draft, without SKUs or stock" {
    (app, nova, _) = paying_cinema([]);
    try {
        _call(app, "add_default_snack_categories", {});
        _import(app, GUIDE_CSV);
        coke = _products(app)["Coca-Cola"];
        copy = _call(
            app, "duplicate_snack_product", {"product_id": coke["product_id"]}
        );
        assert copy["ok"] , copy;
        made = copy["product"];
        assert made["name"] == "Copy of Coca-Cola" and made["status"] == "draft";
        assert [v["option_values"] for v in made["variants"]]
            == [["300 ml"], ["500 ml"]];
        assert [v["price_cents"] for v in made["variants"]] == [10000, 15000];
        assert [v["sku"] for v in made["variants"]] == ["", ""];
        assert made["product_id"] != coke["product_id"];
    } finally {
        app.close();
    }
}

test "bulk actions answer per product" {
    (app, _, _) = paying_cinema(["agent"]);
    try {
        _call(app, "add_default_snack_categories", {});
        _import(app, GUIDE_CSV);
        listed = _products(app);
        coke = listed["Coca-Cola"];
        copy = _call(app, "duplicate_snack_product", {"product_id": coke["product_id"]})[
            "product"
        ];
        ids = [listed["Popcorn"]["product_id"], copy["product_id"]];
        got = _call(
            app, "bulk_snack_products", {"product_ids": ids, "action": "publish"}
        );
        assert got["ok"] and got["done"] == 1 , got;
        failed = [
            r
            for r in got["results"]
            if not r["ok"]
        ][0];
        assert failed["product_id"] == copy["product_id"]
            and failed["problems"] , failed;
        assert _products(app)["Popcorn"]["status"] == "active";
        archived = _call(
            app, "bulk_snack_products", {"product_ids": ids, "action": "archive"}
        );
        assert archived["done"] == 2;
        hire(app, "agent", "box_office_agent", "");
        assert code_of(
            _call(
                app,
                "bulk_snack_products",
                {"product_ids": ids, "action": "restore"},
                "agent"
            )
        )
            == "forbidden";
    } finally {
        app.close();
    }
}
