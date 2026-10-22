"""P12.1: checking the snack catalog (core/snacks/catalog.jac), as pure logic.

From the design guide (docs/snacks-guide.md):
- A category has a name of 1–40 characters.
- A product has a name (1–80), an optional brand (up to 40), description (up to 500)
  and tags (up to 10, each 1–24, kept once ignoring case), and a type: "single" (one
  sellable version) or "variants" (up to two option names such as Size and Flavour).
- Variants are the versions customers buy. A single product has exactly one, with no
  option values; a product with variants has 1–50, each with one value per option name,
  no two the same. A SKU (letters, digits, ".", "-", "_", up to 32, kept in capitals) is
  unique within the product; a barcode is 8–14 digits; a price is whole cents from KES 1
  to KES 100,000. A draft may leave the SKU and the price empty; publishing needs them,
  a category, and at least one available variant.
- Every problem is reported at once, by field ("variants[1].price_cents"), with a code
  and a message that names the variant.
"""

import from core.snacks.catalog {
    check_category_name,
    check_product,
    check_variants,
    publish_problems,
    sku_for,
    variant_label,
    sku_key,
    ProductFields,
    VariantFields,
    PRICE_MAX_CENTS
}

def _fields(problems: list[dict[str, str]]) -> list[str] {
    return sorted([p["field"] for p in problems]);
}

def _row(
    values: list[str],
    sku: str = "",
    price: any = 10000,  # jac:ignore[W1037]
    barcode: str = "",
    available: bool = True
) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "option_values": values,
        "sku": sku,
        "barcode": barcode,
        "price_cents": price,
        "available": available,
        "track_stock": False
    };
}

test "a category has a name of 1 to 40 characters" {
    assert check_category_name("  Crisps  &   Chips ") == ("Crisps & Chips", []);
    for bad in ["", "   ", "x" * 41, None] {
        (name, problems) = check_category_name(bad);
        assert name is None and problems[0]["field"] == "name" , bad;
    }
}

test "a product is tidied and kept" {
    (fields, problems) = check_product(
        "  Coca-Cola ",
        " Coca-Cola ",
        " Refreshing ",
        ["drinks", " Soda ", "DRINKS"],
        "variants",
        [" Size "]
    );
    assert problems == [] and fields is not None , problems;
    kept = fields as ProductFields;
    assert kept.name == "Coca-Cola" and kept.brand == "Coca-Cola";
    assert kept.description == "Refreshing";
    assert kept.tags == ["drinks", "Soda"];
    assert kept.kind == "variants" and kept.option_names == ["Size"];
}

test "every problem with a product is reported at once" {
    (fields, problems) = check_product(
        "", "b" * 41, "d" * 501, ["t" * 25], "bundle", []
    );
    assert fields is None;
    assert _fields(problems)
        == ["brand", "description", "kind", "name", "tags"] , problems;
    # Options: none for a single product, one or two for one with variants.
    assert _fields(check_product("Water", "", "", [], "single", ["Size"])[1])
        == ["option_names"];
    assert _fields(check_product("Popcorn", "", "", [], "variants", [])[1])
        == ["option_names"];
    assert _fields(
        check_product("Soda", "", "", [], "variants", ["Size", "Flavour", "Ice"])[1]
    )
        == ["option_names"];
    assert _fields(check_product("Soda", "", "", [], "variants", ["Size", "size"])[1])
        == ["option_names"];
}

test "variants are tidied, SKUs kept in capitals, and a draft may leave gaps" {
    (rows, problems) = check_variants(
        "variants",
        ["Size"],
        [
            _row([" Small "], " pop-sm ", 20000),
            _row(["Medium"], "", None),
            {** _row(["Large"], "POP-LG", 40000), "variant_id": "abcdef0123456789"}
        ]
    );
    assert problems == [] and rows is not None , problems;
    kept = rows as list[VariantFields];
    assert [v.option_values for v in kept] == [["Small"], ["Medium"], ["Large"]];
    assert [v.sku for v in kept] == ["POP-SM", "", "POP-LG"];
    assert [v.price_cents for v in kept] == [20000, None, 40000];
    # A row keeps the id it came with; new rows get theirs from the endpoint.
    assert [v.variant_id for v in kept] == ["", "", "abcdef0123456789"];
    assert sku_key(" pop-sm ") == "POP-SM";
}

test "every problem with the variants is reported by row" {
    (rows, problems) = check_variants(
        "variants",
        ["Size"],
        [
            _row(["Small"], "POP-SM", 20000),
            _row([" small "], "pop-sm", 99),
            _row([], "bad sku!", PRICE_MAX_CENTS + 1, "12ab")
        ]
    );
    assert rows is None;
    assert _fields(problems)
        == [
            "variants[1].option_values",
            "variants[1].price_cents",
            "variants[1].sku",
            "variants[2].barcode",
            "variants[2].option_values",
            "variants[2].price_cents",
            "variants[2].sku"
        ] , problems;
    assert all(p["code"] and p["message"] for p in problems);
    # A single product has exactly one variant, without option values.
    assert _fields(check_variants("single", [], [_row([]), _row([])])[1])
        == ["variants"];
    assert _fields(check_variants("single", [], [_row(["Big"])])[1])
        == ["variants[0].option_values"];
    assert _fields(check_variants("variants", ["Size"], [])[1]) == ["variants"];
    assert check_variants("single", [], [_row([], "", None, "5012345678900")])[1] == [];
}

test "publishing needs a category, prices and an available variant" {
    (rows, _) = check_variants(
        "variants",
        ["Size"],
        [_row(["Small"], "POP-SM", 20000), _row(["Medium"], "", None)]
    );
    problems = publish_problems(True, rows or []);
    assert _fields(problems) == ["variants[1].price_cents"] , problems;
    medium = [
        p
        for p in problems
        if p["field"] == "variants[1].price_cents"
    ][0];
    assert medium["code"] == "PRICE_REQUIRED" and "Medium" in medium["message"];
    assert [p["code"] for p in publish_problems(False, [])]
        == ["CATEGORY_REQUIRED", "VARIANT_REQUIRED"];
    (off, _) = check_variants("single", [], [_row([], "WATER-500", 10000, "", False)]);
    assert [p["code"] for p in publish_problems(True, off or [])] == ["NONE_AVAILABLE"];
}

test "a SKU is made from the name and the options, free of the ones taken" {
    assert sku_for("Coca-Cola", ["300 ml"], []) == "COCA-COLA-300ML";
    assert sku_for("Small Popcorn", [], []) == "SMALL-POPCORN";
    assert sku_for("Popcorn", ["Large", "Caramel"], []) == "POPCORN-LARGE-CARAMEL";
    assert sku_for("Popcorn", ["Large"], ["POPCORN-LARGE"]) == "POPCORN-LARGE-2";
    assert sku_for("Chai ☕", [], []) == "CHAI";
    assert sku_for("☕", [], []) == "ITEM";
    long = sku_for("A very long product name indeed", ["Extra large bucket"], []);
    assert len(long) <= 32 and not long.endswith("-") , long;
}

test "a variant is named by its option values" {
    assert variant_label(["Medium"]) == "Medium";
    assert variant_label(["Zero Sugar", "500 ml"]) == "Zero Sugar · 500 ml";
    assert variant_label([]) == "Default";
}
