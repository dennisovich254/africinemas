"""Faster catalog work (P12.5; design guide §4). Tenant-scoped endpoints, listed in
tests/isolation/registry.jac; changes are audited.

- duplicate_snack_product: a new draft "Copy of …" with the same details, variants
  (values, prices, availability, Track stock), add-ons, combo items and venue settings,
  but no SKUs (each must be new), no images and no stock (stock belongs to variants).
- preview_snack_import and import_snack_catalog: a CSV in AfriCinemas' columns
  (core/snacks/importer.jac), with a column mapping staff can change. The preview
  reports every bad row and saves nothing; the import runs the same checks and, only if
  there are none, makes missing categories (when asked) and creates or updates the
  products (by name) and their variants (by SKU). New products are drafts; running the
  same file again updates, never duplicates.
- export_snack_catalog: the catalog in the same columns.
- bulk_snack_products: publish, archive or restore many at once; each product answers
  for itself (a product that can't be published says why). bulk_snack_venues sets
  which venues sell many products.

Reading (export) needs concessions.read anywhere in the cinema; everything else needs
concessions.manage.
"""

import from core.clock { now }
import from core.authz.context { scoped }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    restore,
    flush_now,
    fresh_node_id,
    assign_id
}
import from core.tenancy.models { Tenant }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { audited }
import from core.snacks.models { SnackProduct, SnackVariant }
import from core.snacks.importer {
    ExistingProduct,
    read_csv,
    guess_mapping,
    plan_import,
    export_csv
}
import from core.snacks.store {
    MANAGE,
    as_principal,
    reader,
    categories_of,
    products_of,
    variants_of,
    next_position,
    find_product,
    must,
    product_view
}
import from core.snacks.category_api { make_category }
import from core.snacks.product_api { save_product, move_product }
import from core.snacks.venue_api { set_product_venues }

glob CSV_MAX_BYTES: int = 1000000,
     BULK_MAX: int = 200,
     ACTIONS: dict[str, tuple[list[str], str]] = {
         "publish": (["draft"], "active"),
         "archive": (["draft", "active"], "archived"),
         "restore": (["archived"], "draft")
     };

def _row_of(v: SnackVariant) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "variant_id": node_id(v),
        "option_values": list(v.option_values),
        "sku": v.sku,
        "barcode": v.barcode,
        "price_cents": v.price_cents,
        "available": v.available,
        "track_stock": v.track_stock
    };
}

def _duplicate(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    source: SnackProduct = must(find_product(scope.tenant, product_id));
    variants = variants_of(scope.tenant, source);
    made = save_product(
        tenant,
        "",
        f"Copy of {source.name}"[:80],
        source.brand,
        source.description,
        list(source.tags),
        source.category_id,
        source.kind,
        list(source.option_names),
        [{** _row_of(v), "variant_id": "", "sku": "", "barcode": ""} for v in variants]
    );
    copy: SnackProduct = must(
        find_product(scope.tenant, made["product"]["product_id"])
    );
    new_variants = variants_of(scope.tenant, copy);
    me = as_principal(scope.tenant);
    try {
        copy.addon_group_ids = list(source.addon_group_ids);
        copy.components = [dict(c) for c in source.components];
        copy.off_at = list(source.off_at);
        for (old, new) in zip(variants, new_variants) {
            new.off_at = list(old.off_at);
            new.venue_prices = dict(old.venue_prices);
            new.stock_rules = dict(old.stock_rules);
        }
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "product": product_view(scope.tenant, copy, new_variants)};
}

def _existing(tenant: Tenant) -> list[ExistingProduct] {
    names = {node_id(c): c.name for c in categories_of(tenant)};
    return [
        ExistingProduct(
            product_id=node_id(p),
            name=p.name,
            category=names.get(p.category_id, ""),
            kind=p.kind,
            option_names=list(p.option_names),
            variants=[
                {
                    "variant_id": node_id(v),
                    "sku": v.sku,
                    "option_values": list(v.option_values)
                }
                for v in variants_of(tenant, p)
                if v.sku
            ]
        ) for p in products_of(tenant)
    ];
}

def _plan(
    tenant: Tenant, csv_text: str, mapping: dict[str, str], create_categories: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    if not isinstance(csv_text, str) or len(csv_text.encode("utf-8")) > CSV_MAX_BYTES {
        raise Refused("file_too_large", "Choose a CSV file of up to 1 MB.");
    }
    (headers, rows) = read_csv(csv_text);
    if not rows {
        raise Refused("empty_file", "This file has no rows under its header.");
    }
    used = mapping
        if isinstance(mapping, dict) and any(mapping.values())
        else guess_mapping(headers);
    (plan, errors) = plan_import(
        rows,
        {str(k): str(v) for (k, v) in used.items()},
        _existing(tenant),
        [c.name for c in categories_of(tenant)],
        bool(create_categories)
    );
    return {
        "headers": headers,
        "mapping": used,
        "rows": len(rows),
        "plan": plan,
        "errors": errors
    };
}

def _summary(plan: list[dict[str, any]]) -> dict[str, int] {  # jac:ignore[W1037]
    variants = [v for p in plan for v in p["variants"]];
    return {
        "products_created": len(
            [
                p
                for p in plan
                if p["action"] == "create"
            ]
        ),
        "products_updated": len(
            [
                p
                for p in plan
                if p["action"] == "update"
            ]
        ),
        "variants_created": len(
            [
                v
                for v in variants
                if v["action"] == "create"
            ]
        ),
        "variants_updated": len(
            [
                v
                for v in variants
                if v["action"] == "update"
            ]
        ),
        "categories_created": len(
            list(
                dict.fromkeys(
                    [
                        p["category"].casefold()
                        for p in plan
                        if p["new_category"]
                    ]
                )
            )
        )
    };
}

def _preview(
    tenant: str, csv_text: str, mapping: dict[str, str], create_categories: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    found = _plan(scope.tenant, csv_text, mapping, create_categories);
    return {
        "ok": True,
        "headers": found["headers"],
        "mapping": found["mapping"],
        "rows": found["rows"],
        "products": [
            {
                "name": p["name"],
                "category": p["category"],
                "action": p["action"],
                "variants": [
                    {
                        "label": " · ".join(v["option_values"]) or "This item",
                        "sku": v["sku"],
                        "price_cents": v["price_cents"],
                        "action": v["action"]
                    } for v in p["variants"]
                ]
            } for p in found["plan"]
        ],
        "errors": found["errors"],
        "summary": _summary(found["plan"])
    };
}

def _import(
    tenant: str, csv_text: str, mapping: dict[str, str], create_categories: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    found = _plan(scope.tenant, csv_text, mapping, create_categories);
    if found["errors"] {
        raise Refused(
            "import_has_errors",
            f"{len(found['errors'])} rows need fixing; nothing was imported.",
            {"errors": found["errors"]}
        );
    }
    plan: list[dict[str, any]] = found["plan"];  # jac:ignore[W1037]
    by_name = {c.name.casefold(): node_id(c) for c in categories_of(scope.tenant)};
    for p in plan {
        key = p["category"].casefold();
        if key not in by_name {
            made = make_category(
                scope.tenant,
                scope.ctx.tenant_id,
                p["category"],
                next_position(categories_of(scope.tenant))
            );
            by_name[key] = node_id(made);
        }
    }
    for p in plan {
        planned = [
            {
                "variant_id": v["variant_id"],
                "option_values": v["option_values"],
                "sku": v["sku"],
                "barcode": "",
                "price_cents": v["price_cents"],
                "available": True,
                "track_stock": False
            } for v in p["variants"]
        ];
        if p["action"] == "create" {
            save_product(
                tenant,
                "",
                p["name"],
                p["brand"],
                "",
                [],
                by_name[p["category"].casefold()],
                p["kind"],
                p["option_names"],
                planned
            );
            continue;
        }
        product: SnackProduct = must(find_product(scope.tenant, p["product_id"]));
        current = [_row_of(v) for v in variants_of(scope.tenant, product)];
        updates = {
            v["variant_id"]: v
            for v in planned
            if v["variant_id"]
        };
        merged = [
            {
                ** row,
                "price_cents": updates[row["variant_id"]]["price_cents"],
                "option_values": updates[row["variant_id"]]["option_values"]
            }
                if row["variant_id"] in updates
                else row for row in current
        ]
            + [
                v
                for v in planned
                if not v["variant_id"]
            ];
        save_product(
            tenant,
            p["product_id"],
            p["name"],
            p["brand"] or product.brand,
            product.description,
            list(product.tags),
            by_name[p["category"].casefold()],
            product.kind,
            list(product.option_names),
            merged
        );
    }
    return {"ok": True, "summary": _summary(plan)};
}

def _export(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = reader(tenant);
    names = {node_id(c): c.name for c in categories_of(scope.tenant)};
    products = [
        {
            "name": p.name,
            "category": names.get(p.category_id, ""),
            "brand": p.brand,
            "option_names": list(p.option_names),
            "variants": [
                {
                    "option_values": list(v.option_values),
                    "sku": v.sku,
                    "price_cents": v.price_cents
                } for v in variants_of(scope.tenant, p)
            ]
        }
        for p in products_of(scope.tenant)
        if p.status != "archived" and p.kind != "combo"
    ];
    return {"ok": True, "csv": export_csv(products)};
}

def _bulk(tenant: str, product_ids: list[str], action: str) -> dict[str, any] {  # jac:ignore[W1037]
    scoped(tenant, MANAGE);
    if action not in ACTIONS {
        raise Refused("invalid_action", "Choose publish, archive or restore.");
    }
    ids = [str(x) for x in product_ids][:BULK_MAX]
        if isinstance(product_ids, list)
        else [];
    (allowed, to) = ACTIONS[action];
    results: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for product_id in ids {
        got = answer(
            lambda -> any { return move_product(tenant, product_id, allowed, to); }
        );  # jac:ignore[W1037]
        results.append(
            {
                "product_id": product_id,
                "ok": bool(got.get("ok", False)),
                "message": ""
                    if got.get("ok", False)
                    else str(got.get("error", {}).get("message", "")),
                "problems": []
                    if got.get("ok", False)
                    else got.get("error", {}).get("problems", [])
            }
        );
    }
    return {
        "ok": True,
        "results": results,
        "done": len(
            [
                r
                for r in results
                if r["ok"]
            ]
        )
    };
}

def _bulk_venues(
    tenant: str, product_ids: list[str], venue_ids: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    scoped(tenant, MANAGE);
    ids = [str(x) for x in product_ids][:BULK_MAX]
        if isinstance(product_ids, list)
        else [];
    for product_id in ids {
        set_product_venues(tenant, product_id, venue_ids);
    }
    return {"ok": True, "done": len(ids)};
}

def:protect duplicate_snack_product(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.duplicated",
        "snack_product",
        product_id,
        lambda -> any { return _duplicate(tenant, product_id); }  # jac:ignore[W1037]
    );
}

def:protect preview_snack_import(
    tenant: str, csv_text: str, mapping: dict[str, str], create_categories: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _preview(tenant, csv_text, mapping, create_categories); }
    );  # jac:ignore[W1037]
}

def:protect import_snack_catalog(
    tenant: str, csv_text: str, mapping: dict[str, str], create_categories: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_catalog.imported",
        "snack_catalog",
        "",
        lambda -> any { return _import(tenant, csv_text, mapping, create_categories); }  # jac:ignore[W1037]
    );
}

def:protect export_snack_catalog(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _export(tenant); });  # jac:ignore[W1037]
}

def:protect bulk_snack_products(
    tenant: str, product_ids: list[str], action: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.bulk_changed",
        "snack_product",
        "",
        lambda -> any { return _bulk(tenant, product_ids, action); },  # jac:ignore[W1037]
        detail=action
    );
}

def:protect bulk_snack_venues(
    tenant: str, product_ids: list[str], venue_ids: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.bulk_venues_set",
        "snack_product",
        "",
        lambda -> any { return _bulk_venues(tenant, product_ids, venue_ids); }  # jac:ignore[W1037]
    );
}
