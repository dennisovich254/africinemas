"""P12.1: the snack catalog in the back office (core/snacks), design guide docs/snacks-guide.md.

In-process app (tests/apps/payment_app.jac): Nova with one venue, its owner on shift.
- Categories: the usual six in one call (skipping names already there), added (names
  unique ignoring case), renamed, reordered, archived and restored.
- Products: saved as drafts even with gaps (no SKU, no price); publishing checks them
  on the server and answers every problem by field; a published product shows in the
  list as "3 variants, from KES 200" and is found by name, brand, SKU or barcode, and
  filtered by category and status. Variants keep their ids across saves; a removed row
  is gone. SKUs are unique in the cinema (also between products); a freed SKU can be
  used again. Unpublish, archive and restore move the lifecycle; only a draft can be
  deleted. Images are checked like posters.
- Roles: the owner, tenant admin and general manager manage the catalog; box office
  staff read it; ushers can't. Another cinema's anything is not_found. Every change is
  audited.
"""

import io;
import base64;
import from PIL { Image }
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, open_cinema_for }
import from tests.support.payment_setup { paying_cinema, hire }

def _png(width: int = 400, height: int = 400) -> str {
    out = io.BytesIO();
    Image.new("RGB", (width, height), (200, 120, 40)).save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _call(
    app: Served,
    name: str,
    args: dict[str, any],
    who: str = "owner",
    tenant: str = "nova"
) -> any {  # jac:ignore[W1037]
    return app.call(who, name, {"tenant": tenant, ** args});
}

def _category(app: Served, name: str, who: str = "owner", tenant: str = "nova") -> any {  # jac:ignore[W1037]
    return _call(app, "create_snack_category", {"name": name}, who, tenant);
}

def _row(
    values: list[str], sku: str, price: any, variant_id: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "variant_id": variant_id,
        "option_values": values,
        "sku": sku,
        "barcode": "",
        "price_cents": price,
        "available": True,
        "track_stock": False
    };
}

def _save(  # jac:ignore[W3030] a product as the editor sends it, with test defaults
    app: Served,
    name: str,
    category_id: str,
    variants: list[dict[str, any]],  # jac:ignore[W1037]
    product_id: str = "",
    kind: str = "variants",
    options: list[str] | None = None,
    brand: str = "",
    who: str = "owner",
    tenant: str = "nova"
) -> any {  # jac:ignore[W1037]
    return _call(
        app,
        "save_snack_product",
        {
            "product_id": product_id,
            "name": name,
            "brand": brand,
            "description": "",
            "tags": [],
            "category_id": category_id,
            "kind": kind,
            "option_names": (["Size"] if kind == "variants" else [])
                if options is None
                else options,
            "variants": variants
        },
        who,
        tenant
    );
}

def _popcorn(app: Served, category_id: str) -> any {  # jac:ignore[W1037]
    return _save(
        app,
        "Popcorn",
        category_id,
        [
            _row(["Small"], "POP-SM", 20000),
            _row(["Medium"], "POP-MD", 30000),
            _row(["Large"], "POP-LG", 40000)
        ]
    );
}

def _listed(
    app: Served,
    args: dict[str, any] | None = None,  # jac:ignore[W1037]
    who: str = "owner"
) -> list[str] {
    got = _call(
        app,
        "list_snack_products",
        {"search": "", "category_id": "", "status": "", ** (args or {})},
        who
    );
    assert got["ok"] , got;
    return [p["name"] for p in got["products"]];
}

def _fields(answer: dict[str, any]) -> list[str] {  # jac:ignore[W1037]
    return sorted([p["field"] for p in answer["error"]["problems"]]);
}

test "categories: the usual six, unique names, renamed, reordered, archived" {
    (app, _, _) = paying_cinema([]);
    try {
        assert _category(app, "Popcorn")["ok"];
        usual = _call(app, "add_default_snack_categories", {});
        assert usual["ok"] , usual;
        names = [
            c["name"] for c in _call(app, "list_snack_categories", {})["categories"]
        ];
        assert names
            == [
                "Popcorn",
                "Beverages",
                "Crisps & Chips",
                "Candy & Chocolates",
                "Hot Food",
                "Combos & Deals"
            ] , names;
        assert code_of(_category(app, " beverages ")) == "category_taken";
        assert code_of(_category(app, "")) == "invalid_category";
        listed = {
            c["name"]: c for c in _call(app, "list_snack_categories", {})["categories"]
        };
        hot = listed["Hot Food"]["category_id"];
        renamed = _call(
            app, "rename_snack_category", {"category_id": hot, "name": "Hot snacks"}
        );
        assert renamed["ok"] and renamed["category"]["name"] == "Hot snacks" , renamed;
        order = [
            listed[n]["category_id"]
            for n in [
                "Beverages",
                "Popcorn",
                "Crisps & Chips",
                "Candy & Chocolates",
                "Combos & Deals"
            ]
        ]
            + [hot];
        assert _call(app, "reorder_snack_categories", {"category_ids": order})["ok"];
        assert [
            c["name"] for c in _call(app, "list_snack_categories", {})["categories"]
        ][:2]
            == ["Beverages", "Popcorn"];
        assert code_of(
            _call(app, "reorder_snack_categories", {"category_ids": order[:2]})
        )
            == "stale_order";
        archived = _call(
            app, "set_snack_category_status", {"category_id": hot, "status": "archived"}
        );
        assert archived["ok"]
            and archived["category"]["status"] == "archived" , archived;
    } finally {
        app.close();
    }
}

test "a draft may have gaps; publishing checks it and answers by field" {
    (app, _, _) = paying_cinema([]);
    try {
        popcorn = _category(app, "Popcorn")["category"]["category_id"];
        draft = _save(
            app,
            "Popcorn",
            popcorn,
            [_row(["Small"], "POP-SM", 20000), _row(["Medium"], "", None)]
        );
        assert draft["ok"] , draft;
        product = draft["product"];
        assert product["status"] == "draft" and len(product["variants"]) == 2;
        refused = _call(
            app, "publish_snack_product", {"product_id": product["product_id"]}
        );
        assert code_of(refused) == "cannot_publish" , refused;
        assert _fields(refused) == ["variants[1].price_cents", "variants[1].sku"];
        assert "Medium" in refused["error"]["problems"][0]["message"];
        # Fixed (the rows keep their ids), it publishes.
        ids = [v["variant_id"] for v in product["variants"]];
        fixed = _save(
            app,
            "Popcorn",
            popcorn,
            [
                _row(["Small"], "POP-SM", 20000, ids[0]),
                _row(["Medium"], "POP-MD", 30000, ids[1]),
                _row(["Large"], "POP-LG", 40000)
            ],
            product["product_id"]
        );
        assert fixed["ok"] , fixed;
        assert [v["variant_id"] for v in fixed["product"]["variants"]][:2] == ids;
        published = _call(
            app, "publish_snack_product", {"product_id": product["product_id"]}
        );
        assert published["ok"]
            and published["product"]["status"] == "active" , published;
        # A bad save is refused by field, and nothing changes.
        bad = _save(
            app,
            "",
            popcorn,
            [_row(["Small"], "bad sku!", 20000)],
            product["product_id"]
        );
        assert code_of(bad) == "invalid_product" , bad;
        assert _fields(bad) == ["name", "variants[0].sku"];
        # An active product must stay sellable: an edit that removes every price is refused.
        unsellable = _save(
            app,
            "Popcorn",
            popcorn,
            [_row(["Small"], "POP-SM", None, ids[0])],
            product["product_id"]
        );
        assert code_of(unsellable) == "cannot_publish" , unsellable;
    } finally {
        app.close();
    }
}

test "the list shows variants and prices, and finds products by name, brand, SKU or barcode" {
    (app, _, _) = paying_cinema([]);
    try {
        popcorn = _category(app, "Popcorn")["category"]["category_id"];
        drinks = _category(app, "Beverages")["category"]["category_id"];
        made = _popcorn(app, popcorn);
        _call(
            app, "publish_snack_product", {"product_id": made["product"]["product_id"]}
        );
        coke = _save(
            app,
            "Coca-Cola",
            drinks,
            [_row(["300 ml"], "COKE-300", 10000), _row(["500 ml"], "COKE-500", 15000)],
            brand="Coca-Cola"
        );
        water = _save(
            app,
            "Bottled Water",
            drinks,
            [{** _row([], "WATER-500", 10000), "barcode": "5012345678900"}],
            kind="single"
        );
        assert coke["ok"] and water["ok"] , (coke, water);
        summary = {
            p["name"]: p
            for p in _call(
                app,
                "list_snack_products",
                {"search": "", "category_id": "", "status": ""}
            )["products"]
        };
        assert summary["Popcorn"]["variant_count"] == 3;
        assert summary["Popcorn"]["price_from_cents"] == 20000;
        assert summary["Popcorn"]["status"] == "active";
        assert summary["Popcorn"]["category_name"] == "Popcorn";
        assert summary["Coca-Cola"]["status"] == "draft";
        assert _listed(app, {"search": "coke-500"}) == ["Coca-Cola"];
        assert _listed(app, {"search": "coca"}) == ["Coca-Cola"];
        assert _listed(app, {"search": "5012345678900"}) == ["Bottled Water"];
        assert sorted(_listed(app, {"category_id": drinks}))
            == ["Bottled Water", "Coca-Cola"];
        assert _listed(app, {"status": "active"}) == ["Popcorn"];
    } finally {
        app.close();
    }
}

test "SKUs are unique in the cinema, and a freed SKU can be used again" {
    (app, _, _) = paying_cinema([]);
    try {
        popcorn = _category(app, "Popcorn")["category"]["category_id"];
        made = _popcorn(app, popcorn)["product"];
        clash = _save(
            app, "Caramel popcorn", popcorn, [_row(["Small"], "pop-md", 25000)]
        );
        assert code_of(clash) == "invalid_product" , clash;
        assert _fields(clash) == ["variants[0].sku"];
        assert "Popcorn" in clash["error"]["problems"][0]["message"];
        # Popcorn drops its Medium; POP-MD is free again.
        ids = [v["variant_id"] for v in made["variants"]];
        smaller = _save(
            app,
            "Popcorn",
            popcorn,
            [
                _row(["Small"], "POP-SM", 20000, ids[0]),
                _row(["Large"], "POP-LG", 40000, ids[2])
            ],
            made["product_id"]
        );
        assert smaller["ok"] and len(smaller["product"]["variants"]) == 2 , smaller;
        assert _save(
            app, "Caramel popcorn", popcorn, [_row(["Small"], "POP-MD", 25000)]
        )["ok"];
    } finally {
        app.close();
    }
}

test "unpublish, archive and restore; only a draft is deleted" {
    (app, _, _) = paying_cinema([]);
    try {
        popcorn = _category(app, "Popcorn")["category"]["category_id"];
        product_id = _popcorn(app, popcorn)["product"]["product_id"];
        assert _call(app, "publish_snack_product", {"product_id": product_id})["ok"];
        assert code_of(_call(app, "delete_snack_product", {"product_id": product_id}))
            == "archive_instead";
        archived = _call(app, "archive_snack_product", {"product_id": product_id});
        assert archived["ok"] and archived["product"]["status"] == "archived";
        restored = _call(app, "restore_snack_product", {"product_id": product_id});
        assert restored["ok"] and restored["product"]["status"] == "draft";
        assert _call(app, "publish_snack_product", {"product_id": product_id})["ok"];
        back = _call(app, "unpublish_snack_product", {"product_id": product_id});
        assert back["ok"] and back["product"]["status"] == "draft";
        assert _call(app, "delete_snack_product", {"product_id": product_id})["ok"];
        assert _listed(app) == [];
        # Its SKUs are free again.
        assert _popcorn(app, popcorn)["ok"];
        actions = [
            e["action"] for e in _call(app, "audit_log", {"limit": 50})["events"]
        ];
        for action in [
            "snack_category.created",
            "snack_product.saved",
            "snack_product.published",
            "snack_product.archived",
            "snack_product.restored",
            "snack_product.unpublished",
            "snack_product.deleted"
        ] {
            assert action in actions , (action, actions);
        }
    } finally {
        app.close();
    }
}

test "a product has images, checked like posters" {
    (app, _, _) = paying_cinema([]);
    try {
        popcorn = _category(app, "Popcorn")["category"]["category_id"];
        product_id = _popcorn(app, popcorn)["product"]["product_id"];
        up = _call(
            app,
            "upload_snack_image",
            {
                "product_id": product_id,
                "content_type": "image/png",
                "data_base64": _png()
            }
        );
        assert up["ok"] and len(up["product"]["images"]) == 1 , up;
        image_id = up["product"]["images"][0]["image_id"];
        got = _call(
            app, "get_snack_image", {"product_id": product_id, "image_id": image_id}
        );
        assert got["ok"] and got["content_type"] == "image/webp" , got;
        wrong = _call(
            app,
            "upload_snack_image",
            {
                "product_id": product_id,
                "content_type": "image/gif",
                "data_base64": _png()
            }
        );
        assert code_of(wrong) == "wrong_type";
        gone = _call(
            app, "remove_snack_image", {"product_id": product_id, "image_id": image_id}
        );
        assert gone["ok"] and gone["product"]["images"] == [] , gone;
    } finally {
        app.close();
    }
}

test "managers manage the catalog, the box office reads it, ushers can't" {
    (app, nova, _) = paying_cinema(["gm", "agent", "usher"]);
    try {
        hire(app, "gm", "general_manager", "");
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "usher", "usher", "");
        made = _category(app, "Popcorn", "gm");
        assert made["ok"] , made;
        popcorn = made["category"]["category_id"];
        assert _save(
            app, "Popcorn", popcorn, [_row(["Small"], "POP-SM", 20000)], who="gm"
        )["ok"];
        assert _listed(app, {}, "agent") == ["Popcorn"];
        assert code_of(
            _save(app, "Nachos", popcorn, [_row(["Small"], "NAC", 20000)], who="agent")
        )
            == "forbidden";
        assert code_of(
            _call(
                app,
                "list_snack_products",
                {"search": "", "category_id": "", "status": ""},
                "usher"
            )
        )
            == "forbidden";
    } finally {
        app.close();
    }
}

test "another cinema's products and categories are not found" {
    (app, _, _) = paying_cinema([]);
    try {
        open_cinema_for(app, "owner", "rift", "Rift Cinemas");
        popcorn = _category(app, "Popcorn")["category"]["category_id"];
        product_id = _popcorn(app, popcorn)["product"]["product_id"];
        assert _call(
            app,
            "list_snack_products",
            {"search": "", "category_id": "", "status": ""},
            "owner",
            "rift"
        )["products"]
            == [];
        assert code_of(
            _call(app, "get_snack_product", {"product_id": product_id}, "owner", "rift")
        )
            == "not_found";
        assert code_of(
            _call(
                app,
                "publish_snack_product",
                {"product_id": product_id},
                "owner",
                "rift"
            )
        )
            == "not_found";
        # Rift can't file a product under Nova's category, and SKUs are per cinema.
        refused = _save(
            app, "Popcorn", popcorn, [_row(["Small"], "POP-SM", 20000)], tenant="rift"
        );
        assert code_of(refused) == "invalid_product"
            and _fields(refused) == ["category_id"];
        rift_cat = _category(app, "Popcorn", "owner", "rift")["category"][
            "category_id"
        ];
        assert _save(
            app, "Popcorn", rift_cat, [_row(["Small"], "POP-SM", 20000)], tenant="rift"
        )["ok"];
    } finally {
        app.close();
    }
}
