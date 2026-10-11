"""Snack products and their variants in the back office (P12.1). Tenant-scoped endpoints,
listed in tests/isolation/registry.jac; every change is audited. Design guide:
docs/snacks-guide.md §1–§3, §7, §9.

- Reading (list_snack_products, get_snack_product, get_snack_image) needs
  concessions.read anywhere in the cinema; everything else needs concessions.manage.
- save_snack_product saves the product and all its variants in one call, as the editor
  sends them. Fields are checked by core/snacks/catalog.jac and every problem comes back
  by field (invalid_product). A draft may leave SKUs and prices empty; an active product
  must stay sellable (cannot_publish). Variants keep their ids: a row sent with its id
  updates that variant, a row without one is new, and a variant not sent is removed.
- SKUs are unique in the cinema: each is an atomic claim (ADR-0007) held by its
  variant's id, provisional until the save commits; a freed SKU is released on commit.
- Lifecycle: draft -> active (publish, validated on the server: publish_problems) ->
  draft (unpublish) or archived (archive) -> draft (restore). Only a draft can be
  deleted; anything else is archived instead (archive_instead), so orders keep reading.
- Images go through the poster pipeline; up to IMAGES_MAX per product, the first is the
  main one.
- A product, category or image id from another cinema answers not_found (or, for the
  category of a save, a problem on category_id).
"""

import from jaclang { JacRuntime as Jac }
import from core.clock { now }
import from core.claims { claim, holder, make_permanent, release }
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
import from core.snacks.catalog {
    ProductFields,
    VariantFields,
    KINDS,
    check_product,
    check_variants,
    publish_problems,
    variant_label
}
import from core.snacks.store {
    MANAGE,
    as_principal,
    reader,
    categories_of,
    products_of,
    variants_of,
    find_category,
    find_product,
    must,
    product_view,
    product_summary,
    new_image,
    drop_media_on_commit,
    drop_media_now,
    image_answer
}

glob SKUS: str = "snack-sku",
     SKU_HOLD_S: int = 300,
     IMAGES_MAX: int = 5,
     STATUSES: list[str] = ["draft", "active", "archived"];

def _sku_key(tenant_id: str, sku: str) -> str {
    return f"{tenant_id}:{sku}";
}

def _keep_on_commit(key: str, owner: str) {
    # One hook per claim: a lambda made in a loop would see only the last one.
    on_commit(lambda { make_permanent(SKUS, key, owner); });
}

def _free_on_commit(key: str, owner: str) {
    on_commit(lambda { release(SKUS, key, owner); });
}

def _as_fields(v: SnackVariant) -> VariantFields {
    return VariantFields(
        variant_id=node_id(v),
        option_values=list(v.option_values),
        sku=v.sku,
        barcode=v.barcode,
        price_cents=v.price_cents,
        available=v.available,
        track_stock=v.track_stock
    );
}

def _category_ok(tenant: Tenant, category_id: str) -> bool {
    found = find_category(tenant, category_id);
    return found is not None and found.status == "active";
}

def _view(tenant: Tenant, p: SnackProduct) -> dict[str, any] {  # jac:ignore[W1037]
    return product_view(tenant, p, variants_of(tenant, p));
}

def _owner_of(tenant: Tenant, variant_id: str) -> str {
    # The product name a SKU's holder belongs to, for the message.
    for p in products_of(tenant) {
        if any(node_id(v) == variant_id for v in variants_of(tenant, p)) {
            return p.name;
        }
    }
    return "another product";
}

def _claim_skus(
    tenant: Tenant, tenant_id: str, rows: list[VariantFields], ids: list[str]
) -> list[str] {
    # Claims each row's SKU for its variant id; returns the keys newly won (to make
    # permanent, or release on failure). Refuses with every SKU another variant holds.
    won: list[str] = [];
    problems: list[dict[str, str]] = [];
    for (i, row) in enumerate(rows) {
        if not row.sku {
            continue;
        }
        key = _sku_key(tenant_id, row.sku);
        before = holder(SKUS, key);
        got = claim(SKUS, key, ids[i], SKU_HOLD_S);
        if got != ids[i] {
            problems.append(
                {
                    "field": f"variants[{i}].sku",
                    "code": "SKU_TAKEN",
                    "message": f"{variant_label(row.option_values)}: {row.sku} is already used by {_owner_of(
                        tenant, got
                    )}."
                }
            );
        } elif before != ids[i] {
            won.append(key);
        }
    }
    if problems {
        for (i, row) in enumerate(rows) {
            key = _sku_key(tenant_id, row.sku);
            if key in won {
                release(SKUS, key, ids[i]);
            }
        }
        raise Refused(
            "invalid_product", problems[0]["message"], {"problems": problems}
        );
    }
    return won;
}

def _save(  # jac:ignore[W3030] the editor's whole form: product fields and its variants
    tenant: str,
    product_id: str,
    name: str,
    brand: str,
    description: str,
    tags: list[str],
    category_id: str,
    kind: str,
    option_names: list[str],
    variants: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    tenant_id = scope.ctx.tenant_id;
    product: SnackProduct | None = must(find_product(scope.tenant, product_id))
        if product_id
        else None;
    (fields, problems) = check_product(
        name, brand, description, tags, kind, option_names
    );
    if find_category(scope.tenant, category_id) is None {
        problems = problems
            + [
                {
                    "field": "category_id",
                    "code": "CATEGORY_REQUIRED",
                    "message": "Choose one of your categories."
                }
            ];
    }
    shape_kind = kind if kind in KINDS else "variants";
    shape_options = [str(o) for o in option_names]
        if isinstance(option_names, list)
        else [];
    if fields is not None {
        shape_kind = fields.kind;
        shape_options = fields.option_names;
    }
    (rows, row_problems) = check_variants(shape_kind, shape_options, variants);
    problems = problems + row_problems;
    if fields is None or rows is None or problems {
        raise Refused(
            "invalid_product", problems[0]["message"], {"problems": problems}
        );
    }
    checked = fields as ProductFields;
    kept_rows = rows as list[VariantFields];
    if product is not None and product.status == "active" {
        unsellable = publish_problems(
            _category_ok(scope.tenant, category_id), kept_rows
        );
        if unsellable {
            raise Refused(
                "cannot_publish",
                "This product is on sale, so it must stay sellable. "
                    + unsellable[0]["message"],
                {"problems": unsellable}
            );
        }
    }
    existing = variants_of(scope.tenant, product) if product is not None else [];
    by_id = {node_id(v): v for v in existing};
    ids = [
        r.variant_id if r.variant_id in by_id else fresh_node_id() for r in kept_rows
    ];
    won = _claim_skus(scope.tenant, tenant_id, kept_rows, ids);
    stamp = now().isoformat();
    keep_keys = [
        _sku_key(tenant_id, r.sku)
        for r in kept_rows
        if r.sku
    ];
    freed = [
        (_sku_key(tenant_id, v.sku), node_id(v))
        for v in existing
        if v.sku
            and (_sku_key(tenant_id, v.sku) not in keep_keys or node_id(v) not in ids)
    ];
    me = as_principal(scope.tenant);
    try {
        if product is None {
            product = SnackProduct(
                tenant_id=tenant_id, name=checked.name, created_at=stamp
            );
            assign_id(product, fresh_node_id());
            scope.tenant ++> product;
            attach_to_tenant(product, scope.tenant);
        }
        made = product as SnackProduct;
        made.name = checked.name;
        made.brand = checked.brand;
        made.description = checked.description;
        made.tags = checked.tags;
        made.category_id = category_id;
        made.kind = checked.kind;
        made.option_names = checked.option_names;
        made.updated_at = stamp;
        for (i, row) in enumerate(kept_rows) {
            found = by_id.get(ids[i]);
            if found is None {
                found = SnackVariant(
                    tenant_id=tenant_id, product_id=node_id(made), created_at=stamp
                );
                assign_id(found, ids[i]);
                made ++> found;
                attach_to_tenant(found, scope.tenant);
            }
            v = found as SnackVariant;
            v.option_values = row.option_values;
            v.sku = row.sku;
            v.barcode = row.barcode;
            v.price_cents = row.price_cents;
            v.available = row.available;
            v.track_stock = row.track_stock;
            v.position = i;
            v.updated_at = stamp;
        }
        gone = [
            v
            for v in existing
            if node_id(v) not in ids
        ];
        if gone {
            Jac.destroy(gone);
        }
        flush_now();
    } except Exception as e {
        for (i, row) in enumerate(kept_rows) {
            key = _sku_key(tenant_id, row.sku);
            if row.sku and key in won {
                release(SKUS, key, ids[i]);
            }
        }
        raise e;
    } finally {
        restore(me);
    }
    for (i, row) in enumerate(kept_rows) {
        key = _sku_key(tenant_id, row.sku);
        if row.sku and key in won {
            _keep_on_commit(key, ids[i]);
        }
    }
    for (key, owner) in freed {
        _free_on_commit(key, owner);
    }
    return {"ok": True, "product": _view(scope.tenant, product as SnackProduct)};
}

def _move(product: SnackProduct, tenant: Tenant, status: str) {
    me = as_principal(tenant);
    try {
        stamp = now().isoformat();
        product.status = status;
        product.updated_at = stamp;
        if status == "active" {
            product.published_at = stamp;
        }
        flush_now();
    } finally {
        restore(me);
    }
}

def _transition(
    tenant: str, product_id: str, allowed: list[str], to: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    if product.status not in allowed {
        raise Refused(
            "wrong_status",
            f"A product that is {product.status} can't be moved to {to} this way."
        );
    }
    if to == "active" {
        problems = publish_problems(
            _category_ok(scope.tenant, product.category_id),
            [_as_fields(v) for v in variants_of(scope.tenant, product)]
        );
        if product.kind == "combo" and not product.components {
            problems = problems
                + [
                    {
                        "field": "components",
                        "code": "COMPONENTS_REQUIRED",
                        "message": "Choose what this combo includes before publishing."
                    }
                ];
        }
        if problems {
            raise Refused(
                "cannot_publish",
                "The product cannot be published.",
                {"problems": problems}
            );
        }
    }
    _move(product, scope.tenant, to);
    return {"ok": True, "product": _view(scope.tenant, product)};
}

def _delete(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    if product.status != "draft" {
        raise Refused(
            "archive_instead",
            "Only a draft can be deleted. Archive this product instead: it leaves the storefront and stays in your reports."
        );
    }
    variants = variants_of(scope.tenant, product);
    keys = [
        (_sku_key(scope.ctx.tenant_id, v.sku), node_id(v))
        for v in variants
        if v.sku
    ];
    media = [i["key"] for i in product.images];
    me = as_principal(scope.tenant);
    try {
        Jac.destroy(variants + [product]);
        flush_now();
    } finally {
        restore(me);
    }
    for (key, owner) in keys {
        _free_on_commit(key, owner);
    }
    for m in media {
        drop_media_on_commit(m);
    }
    return {"ok": True};
}

def _matches(p: SnackProduct, variants: list[SnackVariant], search: str) -> bool {
    wanted = search.strip().casefold();
    if not wanted {
        return True;
    }
    texts = [p.name, p.brand]
        + [v.sku for v in variants]
        + [v.barcode for v in variants];
    return any(
        wanted in t.casefold()
        for t in texts
        if t
    );
}

def _list(tenant: str, search: str, category_id: str, status: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = reader(tenant);
    names = {node_id(c): c.name for c in categories_of(scope.tenant)};
    found: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for p in products_of(scope.tenant) {
        if category_id and p.category_id != category_id {
            continue;
        }
        if status and p.status != status {
            continue;
        }
        variants = variants_of(scope.tenant, p);
        if _matches(p, variants, search if isinstance(search, str) else "") {
            found.append(product_summary(p, variants, names.get(p.category_id, "")));
        }
    }
    return {"ok": True, "products": found};
}

def _get(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = reader(tenant);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    return {"ok": True, "product": _view(scope.tenant, product)};
}

def _upload_image(
    tenant: str, product_id: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    if len(product.images) >= IMAGES_MAX {
        raise Refused("too_many_images", f"A product has up to {IMAGES_MAX} images.");
    }
    image = new_image(scope, content_type, data_base64);
    me = as_principal(scope.tenant);
    try {
        product.images = product.images + [image];
        product.updated_at = now().isoformat();
        flush_now();
    } except Exception as e {
        drop_media_now(image["key"]);
        raise e;
    } finally {
        restore(me);
    }
    return {"ok": True, "product": _view(scope.tenant, product)};
}

def _remove_image(tenant: str, product_id: str, image_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    gone = [
        i
        for i in product.images
        if i["image_id"] == image_id
    ];
    must(gone[0] if gone else None);
    me = as_principal(scope.tenant);
    try {
        product.images = [
            i
            for i in product.images
            if i["image_id"] != image_id
        ];
        product.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    drop_media_on_commit(gone[0]["key"]);
    return {"ok": True, "product": _view(scope.tenant, product)};
}

def _get_image(tenant: str, product_id: str, image_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = reader(tenant);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    found = [
        i
        for i in product.images
        if i["image_id"] == image_id
    ];
    must(found[0] if found else None);
    return image_answer(found[0]["key"]);
}

def:priv list_snack_products(
    tenant: str, search: str, category_id: str, status: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _list(tenant, search, category_id, status); });  # jac:ignore[W1037]
}

def:priv get_snack_product(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get(tenant, product_id); });  # jac:ignore[W1037]
}

def:priv get_snack_image(
    tenant: str, product_id: str, image_id: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_image(tenant, product_id, image_id); });  # jac:ignore[W1037]
}

def:priv save_snack_product(  # jac:ignore[W3030] the editor's whole form: product fields and its variants
    tenant: str,
    product_id: str,
    name: str,
    brand: str,
    description: str,
    tags: list[str],
    category_id: str,
    kind: str,
    option_names: list[str],
    variants: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.saved",
        "snack_product",
        product_id,
        lambda -> any { return _save(  # jac:ignore[W1037]
            tenant,
            product_id,
            name,
            brand,
            description,
            tags,
            category_id,
            kind,
            option_names,
            variants
        ); },
        made="product.product_id"
    );
}

def:priv publish_snack_product(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.published",
        "snack_product",
        product_id,
        lambda -> any { return _transition(tenant, product_id, ["draft"], "active"); }  # jac:ignore[W1037]
    );
}

def:priv unpublish_snack_product(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.unpublished",
        "snack_product",
        product_id,
        lambda -> any { return _transition(tenant, product_id, ["active"], "draft"); }  # jac:ignore[W1037]
    );
}

def:priv archive_snack_product(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.archived",
        "snack_product",
        product_id,
        lambda -> any { return _transition(  # jac:ignore[W1037]
            tenant, product_id, ["draft", "active"], "archived"
        ); }
    );
}

def:priv restore_snack_product(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.restored",
        "snack_product",
        product_id,
        lambda -> any { return _transition(tenant, product_id, ["archived"], "draft"); }  # jac:ignore[W1037]
    );
}

def:priv delete_snack_product(tenant: str, product_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.deleted",
        "snack_product",
        product_id,
        lambda -> any { return _delete(tenant, product_id); }  # jac:ignore[W1037]
    );
}

def:priv upload_snack_image(
    tenant: str, product_id: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.image_added",
        "snack_product",
        product_id,
        lambda -> any { return _upload_image(  # jac:ignore[W1037]
            tenant, product_id, content_type, data_base64
        ); }
    );
}

def:priv remove_snack_image(
    tenant: str, product_id: str, image_id: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.image_removed",
        "snack_product",
        product_id,
        lambda -> any { return _remove_image(tenant, product_id, image_id); }  # jac:ignore[W1037]
    );
}
