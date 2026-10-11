"""Stock per variant per venue (P12.4; design guide §8). Tenant-scoped endpoints, listed
in tests/isolation/registry.jac; every change is audited and leaves a movement.

Only variants with Track stock have stock. Each has, per venue, on hand and reserved
(atomic counters in core/claims.jac, so concurrent sales can't oversell), available =
on hand − reserved, and rules: a low-stock alert and what happens at zero.

- snack_stock_levels and snack_stock_history need concessions.read at that venue.
- adjust_snack_stock (received, damaged, count correction, other; checked by
  core/snacks/stock.jac) and set_snack_stock_rules need concessions.inventory at that
  venue, so venue-scoped box office staff keep stock only where they work.
- reserve_stock, commit_stock and release_stock are for orders (P12.7): a reservation
  takes only what's available (out_of_stock otherwise); a commit takes the units off the
  shelf and records a "sale" movement; a release gives them back.
- A product, variant or venue that isn't the cinema's is not_found.
"""

import from core.clock { now }
import from core.claims {
    stock_counts,
    stock_change,
    stock_reserve,
    stock_release,
    stock_commit
}
import from core.authz.context { scoped }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.membership { records_of }
import from core.tenancy.principal {
    node_id,
    restore,
    flush_now,
    fresh_node_id,
    assign_id
}
import from core.tenancy.models { Tenant }
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues { find_venue }
import from core.audit.log { audited }
import from core.snacks.models { SnackProduct, SnackVariant, StockMovement }
import from core.snacks.catalog { variant_label }
import from core.snacks.stock {
    check_adjustment,
    check_rules,
    available_of,
    stock_status
}
import from core.snacks.store {
    READ,
    as_principal,
    products_of,
    variants_of,
    find_product,
    find_variant,
    find_any_variant,
    must
}

glob STOCK: str = "snack-stock",
     INVENTORY: str = "concessions.inventory",
     HISTORY_MAX: int = 200,
     DEFAULT_RULES: dict[str, any] = {"low": 0, "at_zero": "unavailable"};  # jac:ignore[W1037]

def stock_key(tenant_id: str, variant_id: str, venue_id: str) -> str {
    return f"{tenant_id}:{variant_id}:{venue_id}";
}

def rules_of(variant: SnackVariant, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return variant.stock_rules.get(venue_id, DEFAULT_RULES);
}

def level_of(tenant: Tenant, variant: SnackVariant, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A variant's stock at a venue, as the pages and orders read it.
    (on_hand, reserved) = stock_counts(
        STOCK, stock_key(node_id(tenant), node_id(variant), venue_id)
    );
    rules = rules_of(variant, venue_id);
    return {
        "on_hand": on_hand,
        "reserved": reserved,
        "available": available_of(on_hand, reserved),
        "low_threshold": rules["low"],
        "at_zero": rules["at_zero"],
        "status": stock_status(on_hand, reserved, rules["low"])
    };
}

def _row(
    tenant: Tenant, p: SnackProduct, v: SnackVariant, venue_id: str
) -> dict[str, any] {  # jac:ignore[W1037]
    label = p.name
        if p.kind != "variants"
        else f"{p.name} · {variant_label(v.option_values)}";
    return {
        "product_id": node_id(p),
        "variant_id": node_id(v),
        "label": label,
        "sku": v.sku,
        ** level_of(tenant, v, venue_id)
    };
}

def _staff_names(tenant: Tenant) -> dict[str, str] {
    me = as_principal(tenant);
    try {
        found = {
            m.staff_root_id: (m.email or m.label or "a staff member")
            for m in records_of(tenant)
        };
    } finally {
        restore(me);
    }
    return found;
}

def _record(  # jac:ignore[W3030] one movement: where, why, how much, the stock after, a note and who
    tenant: Tenant,
    product_id: str,
    variant_id: str,
    venue_id: str,
    reason: str,
    change: int,
    on_hand_after: int,
    note: str,
    made_by: str
) {
    me = as_principal(tenant);
    try {
        moved = StockMovement(
            tenant_id=node_id(tenant),
            product_id=product_id,
            variant_id=variant_id,
            venue_id=venue_id,
            reason=reason,
            change=change,
            on_hand_after=on_hand_after,
            note=note[:200],
            made_by=made_by,
            at=now().isoformat()
        );
        assign_id(moved, fresh_node_id());
        tenant ++> moved;
        attach_to_tenant(moved, tenant);
        flush_now();
    } finally {
        restore(me);
    }
}

def _tracked(
    tenant: Tenant, product_id: str, variant_id: str, venue_id: str
) -> tuple[SnackProduct, SnackVariant] {
    product: SnackProduct = must(find_product(tenant, product_id));
    variant: SnackVariant = must(find_variant(tenant, product, variant_id));
    must(find_venue(tenant, venue_id));
    if not variant.track_stock {
        raise Refused(
            "not_tracked",
            "This variant's stock isn't tracked. Tick Track stock in the product editor first."
        );
    }
    return (product, variant);
}

def _levels(tenant: str, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ, venue_id);
    must(find_venue(scope.tenant, venue_id));
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for p in products_of(scope.tenant) {
        if p.status == "archived" {
            continue;
        }
        for v in variants_of(scope.tenant, p) {
            if v.track_stock {
                rows.append(_row(scope.tenant, p, v, venue_id));
            }
        }
    }
    return {"ok": True, "levels": rows};
}

def _adjust(
    tenant: str,
    product_id: str,
    variant_id: str,
    venue_id: str,
    reason: str,
    quantity: int,
    note: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, INVENTORY, venue_id);
    (product, variant) = _tracked(scope.tenant, product_id, variant_id, venue_id);
    key = stock_key(scope.ctx.tenant_id, variant_id, venue_id);
    (on_hand, _) = stock_counts(STOCK, key);
    (delta, problem) = check_adjustment(reason, quantity, on_hand);
    if problem {
        raise Refused("invalid_adjustment", problem);
    }
    after = stock_change(STOCK, key, delta);
    if after is None {
        raise Refused(
            "stock_changed",
            "The stock changed while you were adjusting it. Reload and try again."
        );
    }
    _record(
        scope.tenant,
        product_id,
        variant_id,
        venue_id,
        reason,
        delta,
        after[0],
        note if isinstance(note, str) else "",
        scope.ctx.member_root_id
    );
    return {"ok": True, "level": _row(scope.tenant, product, variant, venue_id)};
}

def _set_rules(
    tenant: str,
    product_id: str,
    variant_id: str,
    venue_id: str,
    low_threshold: int,
    at_zero: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, INVENTORY, venue_id);
    (product, variant) = _tracked(scope.tenant, product_id, variant_id, venue_id);
    problem = check_rules(low_threshold, at_zero);
    if problem {
        raise Refused("invalid_rules", problem);
    }
    rules = dict(variant.stock_rules);
    rules[venue_id] = {"low": low_threshold, "at_zero": at_zero};
    me = as_principal(scope.tenant);
    try {
        variant.stock_rules = rules;
        variant.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "level": _row(scope.tenant, product, variant, venue_id)};
}

def _history(
    tenant: str, venue_id: str, variant_id: str, limit: int
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ, venue_id);
    must(find_venue(scope.tenant, venue_id));
    if not isinstance(limit, int) or limit < 1 or limit > HISTORY_MAX {
        raise Refused("bad_limit", f"Ask for 1 to {HISTORY_MAX} movements at a time.");
    }
    me = as_principal(scope.tenant);
    try {
        found = [
            m
            for m in [scope.tenant-->[?:StockMovement]]
            if m.venue_id == venue_id and (not variant_id or m.variant_id == variant_id)
        ];
    } finally {
        restore(me);
    }
    found = sorted(
        found, key=lambda (m: StockMovement) -> str { return m.at; }, reverse=True
    )[:limit];
    names = _staff_names(scope.tenant);
    labels: dict[str, str] = {};
    for p in products_of(scope.tenant) {
        for v in variants_of(scope.tenant, p) {
            labels[node_id(v)] = p.name
                if p.kind != "variants"
                else f"{p.name} · {variant_label(v.option_values)}";
        }
    }
    return {
        "ok": True,
        "movements": [
            {
                "variant_id": m.variant_id,
                "label": labels.get(m.variant_id, "Removed item"),
                "reason": m.reason,
                "change": m.change,
                "on_hand_after": m.on_hand_after,
                "note": m.note,
                "by": names.get(m.made_by, "a staff member")
                    if m.made_by
                    else "An order",
                "at": m.at
            } for m in found
        ]
    };
}

# For orders (P12.7): stock taken for a cart, then sold or given back.

def reserve_stock(
    tenant: Tenant, variant_id: str, venue_id: str, quantity: int
) -> bool {
    # True when `quantity` were reserved (only what's available).
    return stock_reserve(
        STOCK, stock_key(node_id(tenant), variant_id, venue_id), quantity
    )
        is not None;
}

def release_stock(tenant: Tenant, variant_id: str, venue_id: str, quantity: int) {
    stock_release(STOCK, stock_key(node_id(tenant), variant_id, venue_id), quantity);
}

def commit_stock(
    tenant: Tenant, variant_id: str, venue_id: str, quantity: int, order_ref: str
) -> bool {
    # The reserved units leave the shelf, recorded as a sale of the order.
    after = stock_commit(
        STOCK, stock_key(node_id(tenant), variant_id, venue_id), quantity
    );
    if after is None {
        return False;
    }
    variant = find_any_variant(tenant, variant_id);
    _record(
        tenant,
        variant.product_id if variant is not None else "",
        variant_id,
        venue_id,
        "sale",
        0 - quantity,
        after[0],
        f"Order {order_ref}",
        ""
    );
    return True;
}

def:priv snack_stock_levels(tenant: str, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _levels(tenant, venue_id); });  # jac:ignore[W1037]
}

def:priv snack_stock_history(
    tenant: str, venue_id: str, variant_id: str, limit: int
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _history(tenant, venue_id, variant_id, limit); }
    );  # jac:ignore[W1037]
}

def:priv adjust_snack_stock(  # jac:ignore[W3030] an adjustment: which variant where, the reason, how many and a note
    tenant: str,
    product_id: str,
    variant_id: str,
    venue_id: str,
    reason: str,
    quantity: int,
    note: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_stock.adjusted",
        "snack_variant",
        variant_id,
        lambda -> any { return _adjust(  # jac:ignore[W1037]
            tenant, product_id, variant_id, venue_id, reason, quantity, note
        ); },
        detail=f"{reason} {quantity} at venue {venue_id}"
    );
}

def:priv set_snack_stock_rules(
    tenant: str,
    product_id: str,
    variant_id: str,
    venue_id: str,
    low_threshold: int,
    at_zero: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_stock.rules_set",
        "snack_variant",
        variant_id,
        lambda -> any { return _set_rules(  # jac:ignore[W1037]
            tenant, product_id, variant_id, venue_id, low_threshold, at_zero
        ); },
        detail=f"low {low_threshold}, at zero {at_zero}, at venue {venue_id}"
    );
}
