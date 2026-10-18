"""Add-on groups and combos in the back office (P12.3; design guide §5). Tenant-scoped
endpoints, listed in tests/isolation/registry.jac; every change is audited.

- Add-on groups (extras such as butter or caramel) are shared by the products they're
  attached to. Saving one (save_snack_addon_group) checks it with
  core/snacks/extras.jac and answers problems by field (invalid_addon_group); options
  keep their ids and venue switches. A group attached to a product can't be deleted
  (addon_in_use). A cinema has at most GROUPS_MAX groups; a product up to
  GROUPS_PER_PRODUCT.
- An add-on's availability at a venue needs concessions.availability AT that venue.
- A combo is a product of kind "combo" sold as one item (its one variant has the SKU
  and price); set_snack_combo_components sets what it includes: each component a fixed
  variant or a choice of eligible ones, from this cinema's non-combo products
  (components[i].variant_ids otherwise). Publishing a combo needs components.
- Reading needs concessions.read anywhere in the cinema; managing needs
  concessions.manage. Another cinema's anything is not_found.
"""

import secrets;
import from jaclang { JacRuntime as Jac }
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
import from core.catalog.venues { find_venue }
import from core.audit.log { audited }
import from core.snacks.models { SnackProduct, SnackAddonGroup }
import from core.snacks.catalog { variant_label }
import from core.snacks.extras {
    AddonGroupFields,
    ComponentFields,
    check_addon_group,
    check_components
}
import from core.snacks.store {
    MANAGE,
    as_principal,
    reader,
    products_of,
    variants_of,
    find_product,
    find_any_variant,
    addon_groups_of,
    find_addon_group,
    addon_group_view,
    must,
    product_view
}

glob AVAILABILITY: str = "concessions.availability",
     GROUPS_MAX: int = 50,
     GROUPS_PER_PRODUCT: int = 5;

def _used_by(tenant: Tenant, group_id: str) -> list[SnackProduct] {
    return [
        p
        for p in products_of(tenant)
        if group_id in p.addon_group_ids
    ];
}

def _group_answer(tenant: Tenant, g: SnackAddonGroup) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "group": addon_group_view(g, len(_used_by(tenant, node_id(g))))
    };
}

def _product_answer(tenant: Tenant, p: SnackProduct) -> dict[str, any] {  # jac:ignore[W1037]
    return {"ok": True, "product": product_view(tenant, p, variants_of(tenant, p))};
}

def _list(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = reader(tenant);
    products = products_of(scope.tenant);
    return {
        "ok": True,
        "groups": [
            addon_group_view(
                g,
                len(
                    [
                        p
                        for p in products
                        if node_id(g) in p.addon_group_ids
                    ]
                )
            ) for g in addon_groups_of(scope.tenant)
        ]
    };
}

def _save_group(  # jac:ignore[W3030] the add-on group form: its fields and options
    tenant: str,
    group_id: str,
    name: str,
    label: str,
    min_picks: int,
    max_picks: int,
    repeatable: bool,
    options: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    group: SnackAddonGroup | None = must(find_addon_group(scope.tenant, group_id))
        if group_id
        else None;
    (fields, problems) = check_addon_group(
        name, label, min_picks, max_picks, repeatable, options
    );
    if fields is None {
        raise Refused(
            "invalid_addon_group", problems[0]["message"], {"problems": problems}
        );
    }
    checked = fields as AddonGroupFields;
    if group is None and len(addon_groups_of(scope.tenant)) >= GROUPS_MAX {
        raise Refused(
            "too_many_groups", f"A catalog has up to {GROUPS_MAX} add-on groups."
        );
    }
    before = {o["option_id"]: o for o in group.options} if group is not None else {};
    stored = [
        {
            "option_id": o.option_id if o.option_id in before else secrets.token_hex(6),
            "name": o.name,
            "price_cents": o.price_cents,
            "off_at": list(before[o.option_id].get("off_at", []))
                if o.option_id in before
                else []
        } for o in checked.options
    ];
    stamp = now().isoformat();
    me = as_principal(scope.tenant);
    try {
        if group is None {
            group = SnackAddonGroup(
                tenant_id=scope.ctx.tenant_id,
                name=checked.name,
                label=checked.label,
                created_at=stamp
            );
            assign_id(group, fresh_node_id());
            scope.tenant ++> group;
            attach_to_tenant(group, scope.tenant);
        }
        made = group as SnackAddonGroup;
        made.name = checked.name;
        made.label = checked.label;
        made.min_picks = checked.min_picks;
        made.max_picks = checked.max_picks;
        made.repeatable = checked.repeatable;
        made.options = stored;
        made.updated_at = stamp;
        flush_now();
    } finally {
        restore(me);
    }
    return _group_answer(scope.tenant, group as SnackAddonGroup);
}

def _delete_group(tenant: str, group_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    group: SnackAddonGroup = must(find_addon_group(scope.tenant, group_id));
    users = _used_by(scope.tenant, group_id);
    if users {
        raise Refused(
            "addon_in_use",
            f"{group.name} is offered with {', '.join([p.name for p in users[:3]])}{' and others'
                if len(users) > 3
                else ''}. Remove it from them first."
        );
    }
    me = as_principal(scope.tenant);
    try {
        Jac.destroy([group]);
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True};
}

def _set_addon_availability(
    tenant: str, group_id: str, option_id: str, venue_id: str, available: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, AVAILABILITY, venue_id);
    group: SnackAddonGroup = must(find_addon_group(scope.tenant, group_id));
    must(find_venue(scope.tenant, venue_id));
    if not any(o["option_id"] == option_id for o in group.options) {
        must(None);
    }
    changed: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for o in group.options {
        copy = dict(o);
        if o["option_id"] == option_id {
            others = [
                v
                for v in o.get("off_at", [])
                if v != venue_id
            ];
            copy["off_at"] = others if available else others + [venue_id];
        }
        changed.append(copy);
    }
    me = as_principal(scope.tenant);
    try {
        group.options = changed;
        group.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return _group_answer(scope.tenant, group);
}

def _set_product_addons(
    tenant: str, product_id: str, group_ids: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    wanted = list(dict.fromkeys([str(x) for x in group_ids]))
        if isinstance(group_ids, list)
        else [];
    if len(wanted) > GROUPS_PER_PRODUCT {
        raise Refused(
            "too_many_groups",
            f"A product can offer up to {GROUPS_PER_PRODUCT} add-on groups."
        );
    }
    for group_id in wanted {
        must(find_addon_group(scope.tenant, group_id));
    }
    me = as_principal(scope.tenant);
    try {
        product.addon_group_ids = wanted;
        product.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return _product_answer(scope.tenant, product);
}

def _set_components(
    tenant: str,
    product_id: str,
    components: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    product: SnackProduct = must(find_product(scope.tenant, product_id));
    if product.kind != "combo" {
        raise Refused(
            "not_a_combo",
            "Only a combo includes other products. Make it a combo first."
        );
    }
    (kept, problems) = check_components(components);
    if kept is not None {
        for (i, c) in enumerate(kept as list[ComponentFields]) {
            for variant_id in c.variant_ids {
                v = find_any_variant(scope.tenant, variant_id);
                owner = find_product(scope.tenant, v.product_id)
                    if v is not None
                    else None;
                if v is None or owner is None or owner.kind == "combo" {
                    problems = problems
                        + [
                            {
                                "field": f"components[{i}].variant_ids",
                                "code": "VARIANT_UNKNOWN",
                                "message": "Choose products from your own catalog (not other combos)."
                            }
                        ];
                    break;
                }
            }
        }
    }
    if kept is None or problems {
        raise Refused(
            "invalid_components", problems[0]["message"], {"problems": problems}
        );
    }
    me = as_principal(scope.tenant);
    try {
        product.components = [
            {
                "label": c.label,
                "quantity": c.quantity,
                "kind": c.kind,
                "variant_ids": c.variant_ids
            } for c in kept as list[ComponentFields]
        ];
        product.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return _product_answer(scope.tenant, product);
}

def _list_variants(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Every variant a combo can include (not other combos), named for staff.
    scope = reader(tenant);
    found: list[dict[str, str]] = [];
    for p in products_of(scope.tenant) {
        if p.kind == "combo" {
            continue;
        }
        for v in variants_of(scope.tenant, p) {
            label = variant_label(v.option_values);
            found.append(
                {
                    "variant_id": node_id(v),
                    "product_id": node_id(p),
                    "name": p.name if p.kind == "single" else f"{p.name} · {label}"
                }
            );
        }
    }
    return {"ok": True, "variants": found};
}

def:protect list_snack_variants(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _list_variants(tenant); });  # jac:ignore[W1037]
}

def:protect list_snack_addon_groups(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _list(tenant); });  # jac:ignore[W1037]
}

def:protect save_snack_addon_group(  # jac:ignore[W3030] the add-on group form: its fields and options
    tenant: str,
    group_id: str,
    name: str,
    label: str,
    min_picks: int,
    max_picks: int,
    repeatable: bool,
    options: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_addons.saved",
        "snack_addons",
        group_id,
        lambda -> any { return _save_group(  # jac:ignore[W1037]
            tenant, group_id, name, label, min_picks, max_picks, repeatable, options
        ); },
        made="group.group_id"
    );
}

def:protect delete_snack_addon_group(tenant: str, group_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_addons.deleted",
        "snack_addons",
        group_id,
        lambda -> any { return _delete_group(tenant, group_id); }  # jac:ignore[W1037]
    );
}

def:protect set_snack_addon_availability(
    tenant: str, group_id: str, option_id: str, venue_id: str, available: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_addons.availability_changed",
        "snack_addons",
        group_id,
        lambda -> any { return _set_addon_availability(  # jac:ignore[W1037]
            tenant, group_id, option_id, venue_id, available
        ); },
        detail=f"{option_id} {'available' if available else 'unavailable'} at venue {venue_id}"
    );
}

def:protect set_snack_product_addons(
    tenant: str, product_id: str, group_ids: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.addons_set",
        "snack_product",
        product_id,
        lambda -> any { return _set_product_addons(tenant, product_id, group_ids); }  # jac:ignore[W1037]
    );
}

def:protect set_snack_combo_components(
    tenant: str,
    product_id: str,
    components: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_product.components_set",
        "snack_product",
        product_id,
        lambda -> any { return _set_components(tenant, product_id, components); }  # jac:ignore[W1037]
    );
}
