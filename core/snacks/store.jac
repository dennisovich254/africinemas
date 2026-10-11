"""Reading and keeping the snack catalog (P12.1), shared by the snacks endpoints.

Everything is read and written as the cinema's principal (ADR-0003). A node id from
another cinema, or no node, is None here and not_found to callers. Images go through the
poster pipeline (process_snack_photo); a removed image is deleted on commit.
"""

import io;
import base64;
import from uuid { uuid4 }
import from core.authz.context { NotFound, TenantScope, on_shift }
import from core.authz.policy { Forbidden, ROLE_PERMISSIONS }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.answers { Refused }
import from core.catalog.pricing { CURRENCY }
import from core.catalog.poster {
    PosterRejected,
    decode_upload,
    process_snack_photo,
    media_key,
    media_store,
    read_media
}
import from core.snacks.models { SnackCategory, SnackProduct, SnackVariant }
import from core.snacks.catalog { variant_label }

glob READ: str = "concessions.read",
     MANAGE: str = "concessions.manage";

def as_principal(tenant: Tenant) -> str {
    # Switches to the cinema's principal; returns the caller's root id to restore.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    return me;
}

def reader(tenant: str) -> TenantScope {
    # The catalog is the whole cinema's, but venue-scoped staff (a box office agent at
    # one venue) read it too: any role with concessions.read, wherever it applies.
    scope = on_shift(tenant);
    if not any(READ in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments) {
        raise Forbidden(READ);
    }
    return scope;
}

def _ordered(found: list[any]) -> list[any] {  # jac:ignore[W1037]
    return sorted(
        found,
        key=lambda (n: any) -> tuple[int, str] { return (n.position, n.created_at); }  # jac:ignore[W1037]
    );
}

def categories_of(tenant: Tenant) -> list[SnackCategory] {
    me = as_principal(tenant);
    try {
        found = [tenant-->[?:SnackCategory]];
    } finally {
        restore(me);
    }
    return _ordered(found);
}

def products_of(tenant: Tenant) -> list[SnackProduct] {
    me = as_principal(tenant);
    try {
        found = [tenant-->[?:SnackProduct]];
    } finally {
        restore(me);
    }
    return sorted(
        found, key=lambda (p: SnackProduct) -> str { return p.name.casefold(); }
    );
}

def variants_of(tenant: Tenant, product: SnackProduct) -> list[SnackVariant] {
    me = as_principal(tenant);
    try {
        found = [product-->[?:SnackVariant]];
    } finally {
        restore(me);
    }
    return _ordered(found);
}

def next_position(found: list[any]) -> int {  # jac:ignore[W1037]
    return max([n.position for n in found] + [-1]) + 1;
}

def _read(tenant: Tenant, ref: str) -> any {  # jac:ignore[W1037]
    if not ref or not isinstance(ref, str) {
        return None;
    }
    me = as_principal(tenant);
    try {
        found: any = jobj(ref);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    if found is None or getattr(found, "tenant_id", "") != node_id(tenant) {
        return None;
    }
    return found;
}

def find_category(tenant: Tenant, ref: str) -> SnackCategory | None {
    found = _read(tenant, ref);
    return found if isinstance(found, SnackCategory) else None;
}

def find_product(tenant: Tenant, ref: str) -> SnackProduct | None {
    found = _read(tenant, ref);
    return found if isinstance(found, SnackProduct) else None;
}

def find_variant(
    tenant: Tenant, product: SnackProduct, ref: str
) -> SnackVariant | None {
    # The product's own variant `ref`, or None.
    for v in variants_of(tenant, product) {
        if node_id(v) == ref {
            return v;
        }
    }
    return None;
}

def must(found: any) -> any {  # jac:ignore[W1037]
    # `found`, or not_found.
    if found is None {
        raise NotFound();
    }
    return found;
}

def category_view(c: SnackCategory, product_count: int) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "category_id": node_id(c),
        "name": c.name,
        "position": c.position,
        "status": c.status,
        "product_count": product_count
    };
}

def variant_view(v: SnackVariant) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "variant_id": node_id(v),
        "option_values": list(v.option_values),
        "label": variant_label(v.option_values),
        "sku": v.sku,
        "barcode": v.barcode,
        "price_cents": v.price_cents,
        "available": v.available,
        "track_stock": v.track_stock,
        "off_at": list(v.off_at),
        "venue_prices": dict(v.venue_prices)
    };
}

def product_view(
    tenant: Tenant, p: SnackProduct, variants: list[SnackVariant]
) -> dict[str, any] {  # jac:ignore[W1037]
    found = find_category(tenant, p.category_id);
    return {
        "product_id": node_id(p),
        "name": p.name,
        "brand": p.brand,
        "description": p.description,
        "tags": list(p.tags),
        "category_id": p.category_id,
        "category_name": found.name if found is not None else "",
        "kind": p.kind,
        "option_names": list(p.option_names),
        "status": p.status,
        "images": [{"image_id": i["image_id"]} for i in p.images],
        "off_at": list(p.off_at),
        "currency": CURRENCY,
        "variants": [variant_view(v) for v in variants],
        "updated_at": p.updated_at,
        "published_at": p.published_at
    };
}

def product_summary(
    p: SnackProduct, variants: list[SnackVariant], category_name: str
) -> dict[str, any] {  # jac:ignore[W1037]
    prices = [
        v.price_cents
        for v in variants
        if v.price_cents is not None
    ];
    return {
        "product_id": node_id(p),
        "name": p.name,
        "brand": p.brand,
        "category_id": p.category_id,
        "category_name": category_name,
        "kind": p.kind,
        "status": p.status,
        "variant_count": len(variants),
        "price_from_cents": min(prices) if prices else None,
        "first_sku": (
            [
                v.sku
                for v in variants
                if v.sku
            ]
            + [""]
        )[0],
        # Every SKU and barcode, so the list can search as staff type.
        "skus": [
            v.sku
            for v in variants
            if v.sku
        ]
            + [
                v.barcode
                for v in variants
                if v.barcode
            ],
        "image_id": p.images[0]["image_id"] if p.images else "",
        "currency": CURRENCY,
        "updated_at": p.updated_at
    };
}

def new_image(
    scope: TenantScope, content_type: str, data_base64: str
) -> dict[str, str] {
    # Checks and stores an uploaded image; returns {image_id, key}.
    try {
        webp = process_snack_photo(decode_upload(data_base64), content_type);
    } except PosterRejected as e {
        raise Refused(e.code, e.message);
    }
    key = media_key(scope.ctx.tenant_id, str(uuid4()));
    media_store().upload(io.BytesIO(webp), key);
    return {"image_id": uuid4().hex[:16], "key": key};
}

def drop_media_on_commit(key: str) {
    if key {
        on_commit(lambda { media_store().delete(key); });
    }
}

def drop_media_now(key: str) {
    if key {
        media_store().delete(key);
    }
}

def image_answer(key: str) -> dict[str, any] {  # jac:ignore[W1037]
    data = read_media(key) if key else None;
    if not data {
        raise Refused("no_image", "This image isn't there any more.");
    }
    return {
        "ok": True,
        "content_type": "image/webp",
        "data_base64": base64.b64encode(data).decode()
    };
}
