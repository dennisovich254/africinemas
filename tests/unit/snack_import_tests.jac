"""P12.5: the snack catalog's CSV import (core/snacks/importer.jac), as pure logic.
Design guide §4C.

- Columns are found by name (product_name or name or product; category; brand;
  variant or size; option; sku; price; currency), and staff can map them instead.
- Rows become products: rows with the same product name are one product with one
  variant per row (named by its variant value, the option defaulting to Size); a row
  without a variant is a single item. Prices are shillings ("200", "1,250", "150.00").
- Every problem is reported with its row number (the header is row 1), before anything
  is saved: a missing name, category or SKU, an unknown category (unless missing
  categories are to be made), a SKU twice in the file or used by another product, a
  price that isn't whole shillings, a currency other than KES, a product whose rows
  disagree on its category, or a single item on more than one row.
- An existing product (same name) is updated, its variants matched by SKU; others are
  added. Re-running the same file changes nothing new.
"""

import from core.snacks.importer {
    read_csv,
    guess_mapping,
    plan_import,
    export_csv,
    ExistingProduct
}

glob GUIDE_CSV: str = """product_name,category,brand,variant,sku,price,currency
Popcorn,Popcorn,,Small,POP-SM,200,KES
Popcorn,Popcorn,,Medium,POP-MD,300,KES
Popcorn,Popcorn,,Large,POP-LG,400,KES
Coca-Cola,Beverages,Coca-Cola,300 ml,COKE-300,100,KES
Coca-Cola,Beverages,Coca-Cola,500 ml,COKE-500,150,KES
Doritos Nacho Cheese,Crisps & Chips,Doritos,45 g,DOR-NC-45,100,KES
Bottled Water,Beverages,,,WATER-500,"1,000.00",
""";

def _plan(
    text: str,
    existing: list[ExistingProduct] | None = None,
    categories: list[str] | None = None,
    create: bool = False
) -> tuple[list[dict[str, any]], list[dict[str, any]]] {  # jac:ignore[W1037]
    (headers, rows) = read_csv(text);
    return plan_import(
        rows,
        guess_mapping(headers),
        existing or [],
        categories
            if categories is not None
            else ["Popcorn", "Beverages", "Crisps & Chips"],
        create
    );
}

test "the guide's example becomes four products with their variants" {
    (headers, rows) = read_csv(GUIDE_CSV);
    assert headers[0] == "product_name" and len(rows) == 7;
    mapping = guess_mapping(headers);
    assert mapping["product_name"] == "product_name" and mapping["sku"] == "sku";
    (plan, errors) = _plan(GUIDE_CSV);
    assert errors == [] , errors;
    by_name = {p["name"]: p for p in plan};
    assert sorted(by_name.keys())
        == ["Bottled Water", "Coca-Cola", "Doritos Nacho Cheese", "Popcorn"];
    popcorn = by_name["Popcorn"];
    assert popcorn["kind"] == "variants" and popcorn["option_names"] == ["Size"];
    assert [v["option_values"] for v in popcorn["variants"]]
        == [["Small"], ["Medium"], ["Large"]];
    assert [v["price_cents"] for v in popcorn["variants"]] == [20000, 30000, 40000];
    assert popcorn["action"] == "create";
    water = by_name["Bottled Water"];
    assert water["kind"] == "single" and water["variants"][0]["price_cents"] == 100000;
    assert by_name["Coca-Cola"]["brand"] == "Coca-Cola";
}

test "columns are found by other names, or mapped by staff" {
    (headers, rows) = read_csv(
        "Name,Category,Size,SKU,Price\nPopcorn,Popcorn,Small,POP-SM,200\n"
    );
    mapping = guess_mapping(headers);
    assert mapping["product_name"] == "Name" and mapping["variant"] == "Size";
    (plan, errors) = plan_import(
        rows,
        {
            "product_name": "Name",
            "category": "Category",
            "variant": "Size",
            "sku": "SKU",
            "price": "Price"
        },
        [],
        ["Popcorn"],
        False
    );
    assert errors == [] and plan[0]["variants"][0]["sku"] == "POP-SM" , errors;
}

test "every bad row is reported with its row number, and nothing is planned" {
    bad = """product_name,category,variant,sku,price,currency
,Popcorn,Small,POP-SM,200,KES
Popcorn,Snacks,Medium,POP-MD,300,KES
Popcorn,Popcorn,Large,POP-MD,abc,USD
Nachos,Popcorn,,,250,KES
Water,Beverages,,W1,100,
Water,Beverages,,W2,100,
""";
    (plan, errors) = _plan(bad);
    assert plan == [];
    found = sorted([(e["row"], e["field"]) for e in errors]);
    assert found
        == [
            (2, "product_name"),
            (3, "category"),
            # Row 4 also disagrees with row 3 on Popcorn's category.
            (4, "category"),
            (4, "currency"),
            (4, "price"),
            (4, "sku"),
            (5, "sku"),
            (7, "variant")
        ] , found;
    assert all(e["message"] for e in errors);
}

test "missing categories can be made instead of refused" {
    text = "product_name,category,sku,price\nNachos,Hot Food,NACHOS,300\n";
    (_, errors) = _plan(text, None, ["Popcorn"], False);
    assert [e["field"] for e in errors] == ["category"];
    (plan, errors) = _plan(text, None, ["Popcorn"], True);
    assert errors == [] and plan[0]["new_category"] , (plan, errors);
}

test "an existing product is updated, its variants matched by SKU" {
    existing = [
        ExistingProduct(
            product_id="p-popcorn",
            name="Popcorn",
            category="Popcorn",
            kind="variants",
            option_names=["Size"],
            variants=[
                {"variant_id": "v-small", "sku": "POP-SM", "option_values": ["Small"]}
            ]
        ),
        ExistingProduct(
            product_id="p-other",
            name="Caramel corn",
            category="Popcorn",
            kind="variants",
            option_names=["Size"],
            variants=[{"variant_id": "v-cc", "sku": "CC-1", "option_values": ["Small"]}]
        )
    ];
    (plan, errors) = _plan(
        "product_name,category,variant,sku,price\nPopcorn,Popcorn,Small,POP-SM,250\nPopcorn,Popcorn,Large,POP-LG,400\n",
        existing
    );
    assert errors == [] , errors;
    popcorn = plan[0];
    assert popcorn["action"] == "update" and popcorn["product_id"] == "p-popcorn";
    assert [(v["variant_id"], v["action"]) for v in popcorn["variants"]]
        == [("v-small", "update"), ("", "create")];
    # A SKU another product uses is refused.
    (_, errors) = _plan(
        "product_name,category,variant,sku,price\nPopcorn,Popcorn,Jumbo,CC-1,500\n",
        existing
    );
    assert [e["field"] for e in errors] == ["sku"]
        and "Caramel corn" in errors[0]["message"];
}

test "the export is the same columns, and reads back as the same plan" {
    text = export_csv(
        [
            {
                "name": "Popcorn",
                "category": "Popcorn",
                "brand": "",
                "option_names": ["Size"],
                "variants": [
                    {"option_values": ["Small"], "sku": "POP-SM", "price_cents": 20000}
                ]
            }
        ]
    );
    assert text.splitlines()[0]
        == "product_name,category,brand,option,variant,sku,price,currency";
    assert text.splitlines()[1] == "Popcorn,Popcorn,,Size,Small,POP-SM,200,KES";
    (plan, errors) = _plan(text);
    assert errors == [] and plan[0]["variants"][0]["price_cents"] == 20000;
}

test "an existing product's shape isn't changed by an import" {
    water = [
        ExistingProduct(
            product_id="p-water",
            name="Bottled Water",
            category="Beverages",
            kind="single",
            option_names=[],
            variants=[
                {"variant_id": "v-water", "sku": "WATER-500", "option_values": []}
            ]
        )
    ];
    (_, errors) = _plan(
        "product_name,category,variant,sku,price\nBottled Water,Beverages,500 ml,WATER-500,100\nBottled Water,Beverages,1 litre,WATER-1000,150\n",
        water
    );
    assert [e["field"] for e in errors] == ["variant"]
        and "single item" in errors[0]["message"] , errors;
}
