"""A venue's optional tracked 3D-glasses snack product (P12.13)."""

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
import from core.catalog.answers { Refused, answer }
import from core.tenancy.models { Tenant }
import from core.catalog.models { Venue }
import from core.catalog.venues { find_venue }
import from core.audit.log { audited }
import from core.snacks.models { SnackProduct, SnackVariant, GlassesConfig }
import from core.snacks.catalog { check_venue_price, offer }
import from core.snacks.inventory_api { level_of }
import from core.snacks.store {
    MANAGE,
    as_principal,
    reader,
    products_of,
    variants_of,
    find_product,
    find_variant
}

glob PURPOSE: str = "3d_glasses";

def _configs(tenant: Tenant) -> list[GlassesConfig] {
    me = as_principal(tenant);
    try {
        found = [tenant-->[?:GlassesConfig]];
    } finally {
        restore(me);
    }
    return found;
}

def _find_config(tenant: Tenant, venue_id: str) -> GlassesConfig | None {
    found = [
        c
        for c in _configs(tenant)
        if c.venue_id == venue_id
    ];
    return found[0] if found else None;
}

def _special(tenant: Tenant) -> tuple[SnackProduct | None, SnackVariant | None] {
    found = [
        p
        for p in products_of(tenant)
        if p.purpose == PURPOSE
    ];
    product = found[0] if found else None;
    rows = variants_of(tenant, product) if product is not None else [];
    return (product, rows[0] if rows else None);
}

def _make_special(
    tenant: Tenant, tenant_id: str, price: int
) -> tuple[SnackProduct, SnackVariant] {
    stamp = now().isoformat();
    product = SnackProduct(
        tenant_id=tenant_id,
        name="3D glasses",
        description="Reusable 3D glasses",
        purpose=PURPOSE,
        kind="single",
        status="active",
        created_at=stamp,
        updated_at=stamp,
        published_at=stamp
    );
    variant = SnackVariant(
        tenant_id=tenant_id,
        product_id="",
        sku="3D-GLASSES",
        price_cents=price,
        available=True,
        track_stock=True,
        created_at=stamp,
        updated_at=stamp
    );
    assign_id(product, fresh_node_id());
    variant.product_id = node_id(product);
    assign_id(variant, fresh_node_id());
    tenant ++> product;
    product ++> variant;
    attach_to_tenant(product, tenant);
    attach_to_tenant(variant, tenant);
    return (product, variant);
}

def _view(tenant: Tenant, config: GlassesConfig) -> dict[str, any] {  # jac:ignore[W1037]
    product = find_product(tenant, config.product_id);
    variant = find_variant(tenant, product, config.variant_id)
        if product is not None
        else None;
    price = variant.venue_prices.get(config.venue_id, variant.price_cents)
        if variant is not None
        else None;
    on_sale = False;
    if product is not None and variant is not None {
        (on_sale, _) = offer(
            product.status,
            product.off_at,
            variant.available,
            variant.off_at,
            variant.price_cents,
            variant.venue_prices,
            config.venue_id
        );
    }
    level = level_of(tenant, variant, config.venue_id) if variant is not None else {};
    return {
        "venue_id": config.venue_id,
        "sold": config.sold,
        "price_cents": price,
        "product_id": config.product_id,
        "variant_id": config.variant_id,
        "track_stock": variant.track_stock if variant is not None else False,
        "on_sale": on_sale,
        "available": level.get("available", 0)
    };
}

def glasses_offer(tenant: Tenant, venue_id: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    config = _find_config(tenant, venue_id);
    if config is None or not config.sold {
        return None;
    }
    shown = _view(tenant, config);
    if not shown["on_sale"]
        or shown["price_cents"] is None
        or shown["available"] <= 0 {
        return None;
    }
    return shown;
}

def _configure(
    tenant: str, venue_id: str, sold: bool, price_cents: int
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    if find_venue(scope.tenant, venue_id) is None {
        raise Refused("not_found", "That venue wasn't found.");
    }
    (price, problem) = check_venue_price(price_cents);
    if problem or price is None {
        raise Refused("invalid_price", problem or "Enter a price.");
    }
    me = as_principal(scope.tenant);
    try {
        (product, variant) = _special(scope.tenant);
        if product is None or variant is None {
            (product, variant) = _make_special(
                scope.tenant, scope.ctx.tenant_id, price
            );
        }
        prices = dict(variant.venue_prices);
        prices[venue_id] = price;
        variant.venue_prices = prices;
        variant.updated_at = now().isoformat();
        config = _find_config(scope.tenant, venue_id);
        if config is None {
            config = GlassesConfig(
                tenant_id=scope.ctx.tenant_id,
                venue_id=venue_id,
                product_id=node_id(product),
                variant_id=node_id(variant)
            );
            assign_id(config, fresh_node_id());
            scope.tenant ++> config;
            attach_to_tenant(config, scope.tenant);
        }
        config.sold = bool(sold);
        config.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "glasses": _view(scope.tenant, config as GlassesConfig)};
}

def _list(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = reader(tenant);
    return {
        "ok": True,
        "venues": [_view(scope.tenant, c) for c in _configs(scope.tenant)]
    };
}

def:protect configure_3d_glasses(
    tenant: str, venue_id: str, sold: bool, price_cents: int
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_glasses.configured",
        "venue",
        venue_id,
        lambda -> any { return answer(
            lambda -> any { return _configure(tenant, venue_id, sold, price_cents); }
        ); }
    );
}

def:protect list_3d_glasses(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _list(tenant); });  # jac:ignore[W1037]
}
