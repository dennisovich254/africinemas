"""Snack availability and prices per venue (P12.2; design guide §3F, §7). Tenant-scoped
endpoints, listed in tests/isolation/registry.jac; every change is audited.

A cinema's venues are the guide's locations. A product is sold at every venue unless
switched off at one (set_snack_product_venues); a variant can be unavailable at a venue
(set_snack_variant_availability) and can have that venue's own price
(set_snack_venue_price), which overrides the variant's price there (catalog.offer).

- The product's venues and the venue prices need concessions.manage.
- A variant's availability at a venue needs concessions.availability AT that venue, so
  venue-scoped box office staff flip it only where they work.
- A venue price is whole cents in range, or None to use the variant's price
  (invalid_price). A venue, product or variant that isn't the cinema's is not_found.
"""

import from core.clock { now }
import from core.authz.context { scoped }
import from core.tenancy.principal { node_id, restore, flush_now }
import from core.tenancy.models { Tenant }
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues { find_venue }
import from core.catalog.models { Venue }
import from core.audit.log { audited }
import from core.snacks.models { SnackProduct, SnackVariant }
import from core.snacks.catalog { check_venue_price }
import from core.snacks.store {
    MANAGE,
    as_principal,
    variants_of,
    find_product,
    find_variant,
    must,
    product_view
}

glob AVAILABILITY: str = "concessions.availability";

def _venues_of(tenant: Tenant) -> list[str] {
    me = as_principal(tenant);
    try {
        found = [node_id(v) for v in [tenant-->[?:Venue]]];
    } finally {
        restore(me);
    }
    return found;
}

def _view(tenant: Tenant, product: SnackProduct) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "product": product_view(tenant, product, variants_of(tenant, product))
    };
}

def _set_product_venues(
    tenant: str, product_id: str, venue_ids: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    wanted = [str(v) for v in venue_ids] if isinstance(venue_ids, list) else [];
    for venue_id in wanted {
        must(find_venue(scope.tenant, venue_id));
    }
    me = as_principal(scope.tenant);
    try {
        product.off_at = [
            v
            for v in _venues_of(scope.tenant)
            if v not in wanted
        ];
        product.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return _view(scope.tenant, product);
}

def _set_availability(
    tenant: str, product_id: str, variant_id: str, venue_id: str, available: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, AVAILABILITY, venue_id);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    variant: SnackVariant = must(find_variant(scope.tenant, product, variant_id));
    must(find_venue(scope.tenant, venue_id));
    others = [
        v
        for v in variant.off_at
        if v != venue_id
    ];
    me = as_principal(scope.tenant);
    try {
        variant.off_at = others if available else others + [venue_id];
        variant.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return _view(scope.tenant, product);
}

def _set_venue_price(
    tenant: str,
    product_id: str,
    variant_id: str,
    venue_id: str,
    price_cents: int | None
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    variant: SnackVariant = must(find_variant(scope.tenant, product, variant_id));
    must(find_venue(scope.tenant, venue_id));
    (price, problem) = check_venue_price(price_cents);
    if problem {
        raise Refused("invalid_price", problem);
    }
    prices = {
        k: v
        for (k, v) in variant.venue_prices.items()
        if k != venue_id
    };
    if price is not None {
        prices[venue_id] = price;
    }
    me = as_principal(scope.tenant);
    try {
        variant.venue_prices = prices;
        variant.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return _view(scope.tenant, product);
}

def:priv set_snack_product_venues(
    tenant: str, product_id: str, venue_ids: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.venues_set",
        "snack_product",
        product_id,
        lambda -> any { return _set_product_venues(tenant, product_id, venue_ids); }  # jac:ignore[W1037]
    );
}

def:priv set_snack_variant_availability(
    tenant: str, product_id: str, variant_id: str, venue_id: str, available: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_variant.availability_changed",
        "snack_variant",
        variant_id,
        lambda -> any { return _set_availability(  # jac:ignore[W1037]
            tenant, product_id, variant_id, venue_id, available
        ); },
        detail=f"{'available' if available else 'unavailable'} at venue {venue_id}"
    );
}

def:priv set_snack_venue_price(
    tenant: str,
    product_id: str,
    variant_id: str,
    venue_id: str,
    price_cents: int | None
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_variant.venue_price_set",
        "snack_variant",
        variant_id,
        lambda -> any { return _set_venue_price(  # jac:ignore[W1037]
            tenant, product_id, variant_id, venue_id, price_cents
        ); },
        detail=f"venue {venue_id}: {price_cents
            if price_cents is not None
            else 'variant price'}"
    );
}
