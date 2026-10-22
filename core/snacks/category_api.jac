"""Snack categories in the back office (P12.1). Tenant-scoped endpoints, listed in
tests/isolation/registry.jac; every change is audited.

Categories organize products for staff and customers (design guide §6). Reading needs
concessions.read held anywhere in the cinema; changing needs concessions.manage. Names
are 1 to CATEGORY_NAME_MAX characters and unique in the cinema ignoring case
(category_taken). add_default_snack_categories adds the usual six, or those of them
named (improvements #9: the owner picks), skipping names that are already there, and
says which it added. list_snack_categories also lists the usual names not yet taken
("usual"), offered as suggestions. An archived category keeps its products (for reports) and leaves the
storefront. Another cinema's category is not_found.
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
import from core.snacks.models { SnackCategory }
import from core.snacks.catalog { check_category_name }
import from core.snacks.store {
    MANAGE,
    as_principal,
    reader,
    categories_of,
    products_of,
    next_position,
    find_category,
    must,
    category_view
}

glob DEFAULT_CATEGORIES: list[str] = [
         "Popcorn",
         "Beverages",
         "Crisps & Chips",
         "Candy & Chocolates",
         "Hot Food",
         "Combos & Deals"
     ],
     CATEGORIES_MAX: int = 40,
     STATUSES: list[str] = ["active", "archived"];

def _views(tenant: Tenant, found: list[SnackCategory]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    products = products_of(tenant);
    return [
        category_view(
            c,
            len(
                [
                    p
                    for p in products
                    if p.category_id == node_id(c)
                ]
            )
        ) for c in found
    ];
}

def _name(tenant: Tenant, name: str, keep_id: str = "") -> str {
    # The tidied name, unless it's invalid or another category has it.
    (clean, problems) = check_category_name(name);
    if clean is None {
        raise Refused(
            "invalid_category", problems[0]["message"], {"problems": problems}
        );
    }
    for c in categories_of(tenant) {
        if node_id(c) != keep_id and c.name.casefold() == clean.casefold() {
            raise Refused(
                "category_taken",
                f"There's already a category called '{c.name}'.",
                {
                    "problems": [
                        {
                            "field": "name",
                            "code": "NAME_TAKEN",
                            "message": "That name is taken."
                        }
                    ]
                }
            );
        }
    }
    return clean;
}

def make_category(
    tenant: Tenant, tenant_id: str, name: str, position: int
) -> SnackCategory {
    stamp = now().isoformat();
    me = as_principal(tenant);
    try {
        made = SnackCategory(
            tenant_id=tenant_id,
            name=name,
            position=position,
            created_at=stamp,
            updated_at=stamp
        );
        assign_id(made, fresh_node_id());
        tenant ++> made;
        attach_to_tenant(made, tenant);
        flush_now();
    } finally {
        restore(me);
    }
    return made;
}

def _usual_left(found: list[SnackCategory]) -> list[str] {
    # The usual names no category has yet (archived ones included: the name is taken).
    taken = [c.name.casefold() for c in found];
    return [
        name
        for name in DEFAULT_CATEGORIES
        if name.casefold() not in taken
    ];
}

def _list(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = reader(tenant);
    found = categories_of(scope.tenant);
    return {
        "ok": True,
        "categories": _views(scope.tenant, found),
        "usual": _usual_left(found)
    };
}

def _create(tenant: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    clean = _name(scope.tenant, name);
    found = categories_of(scope.tenant);
    if len(found) >= CATEGORIES_MAX {
        raise Refused(
            "too_many_categories", f"A catalog has up to {CATEGORIES_MAX} categories."
        );
    }
    made = make_category(
        scope.tenant, scope.ctx.tenant_id, clean, next_position(found)
    );
    return {"ok": True, "category": category_view(made, 0)};
}

def _add_defaults(tenant: str, names: list[str] | None) -> dict[str, any] {  # jac:ignore[W1037]
    # `names` picks among the usual ones (others are ignored); None adds them all.
    scope = scoped(tenant, MANAGE);
    found = categories_of(scope.tenant);
    wanted = [str(n).casefold() for n in names] if isinstance(names, list) else None;
    position = next_position(found);
    added: list[str] = [];
    for name in _usual_left(found) {
        if wanted is None or name.casefold() in wanted {
            make_category(scope.tenant, scope.ctx.tenant_id, name, position);
            position += 1;
            added.append(name);
        }
    }
    now_found = categories_of(scope.tenant);
    return {
        "ok": True,
        "added": added,
        "categories": _views(scope.tenant, now_found),
        "usual": _usual_left(now_found)
    };
}

def _rename(tenant: str, category_id: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    found: SnackCategory = must(find_category(scope.tenant, category_id));
    clean = _name(scope.tenant, name, category_id);
    me = as_principal(scope.tenant);
    try {
        found.name = clean;
        found.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "category": _views(scope.tenant, [found])[0]};
}

def _reorder(tenant: str, category_ids: list[str]) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    by_id = {node_id(c): c for c in categories_of(scope.tenant)};
    wanted = [str(x) for x in category_ids] if isinstance(category_ids, list) else [];
    if sorted(wanted) != sorted(by_id.keys()) {
        raise Refused(
            "stale_order",
            "The categories changed while you were reordering them. Reload and try again."
        );
    }
    me = as_principal(scope.tenant);
    try {
        for (position, category_id) in enumerate(wanted) {
            by_id[category_id].position = position;
        }
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True};
}

def _set_status(tenant: str, category_id: str, status: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, MANAGE);
    found: SnackCategory = must(find_category(scope.tenant, category_id));
    if status not in STATUSES {
        raise Refused("invalid_status", "Choose active or archived.");
    }
    me = as_principal(scope.tenant);
    try {
        found.status = status;
        found.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "category": _views(scope.tenant, [found])[0]};
}

def:protect list_snack_categories(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _list(tenant); });  # jac:ignore[W1037]
}

def:protect create_snack_category(tenant: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_category.created",
        "snack_category",
        "",
        lambda -> any { return _create(tenant, name); },  # jac:ignore[W1037]
        made="category.category_id"
    );
}

def:protect add_default_snack_categories(
    tenant: str, names: list[str] | None = None
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_category.defaults_added",
        "snack_category",
        "",
        lambda -> any { return _add_defaults(tenant, names); }  # jac:ignore[W1037]
    );
}

def:protect rename_snack_category(
    tenant: str, category_id: str, name: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_category.renamed",
        "snack_category",
        category_id,
        lambda -> any { return _rename(tenant, category_id, name); }  # jac:ignore[W1037]
    );
}

def:protect reorder_snack_categories(
    tenant: str, category_ids: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_category.reordered",
        "snack_category",
        "",
        lambda -> any { return _reorder(tenant, category_ids); }  # jac:ignore[W1037]
    );
}

def:protect set_snack_category_status(
    tenant: str, category_id: str, status: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snack_category.status_changed",
        "snack_category",
        category_id,
        lambda -> any { return _set_status(tenant, category_id, status); },  # jac:ignore[W1037]
        detail=status
    );
}
