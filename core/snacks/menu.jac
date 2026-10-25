"""The snack menu at a venue, and the price of a cart there (P12.6; ADR-0051).

Used by the storefront (core/snacks/menu_api.jac) and, later, the box office: one place
decides what's on sale and what it costs, so a browser never sets a price.

- menu_of(tenant, venue_id): the active categories in their order, each with its
  products on sale at the venue. A variant is on sale when `offer` says so (product and
  variant active and on there, with a price: the venue's own, else the variant's) and
  its stock allows one more (`stock_allows`). A combo is on sale when its own variant is
  and every component can be filled (`combo_on_sale`); an add-on option when it's on at
  the venue. A product whose required add-ons can't be met is left out, as is a
  category with nothing on sale. Few left (FEW_LEFT or fewer, tracked and stopping at
  zero) is shown as `left`.
- price_cart(tenant, venue_id, lines): each line is {variant_id, quantity, addons (option
  ids, repeated for a repeatable group), choices (per combo component, `quantity` variant
  ids; a fixed one may be left out)}. Answers (priced lines, total, problems): a line's
  unit price is the variant's price there plus its add-ons, a combo's choices don't
  change it. Every problem is reported at once, by line, naming the snack: not on sale,
  a bad quantity, too few or too many add-ons, a choice that isn't one, or more than is
  left (counting a variant's units across the cart, combo components included).
"""

import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id }
import from core.snacks.models { SnackProduct, SnackVariant, SnackAddonGroup }
import from core.snacks.catalog { offer, variant_label }
import from core.snacks.extras { ComponentFields, combo_on_sale }
import from core.snacks.inventory_api { level_of }
import from core.snacks.stock { FEW_LEFT }
import from core.snacks.store {
    categories_of,
    products_of,
    variants_of,
    addon_groups_of
}

glob QUANTITY_MAX: int = 20,
     LINES_MAX: int = 30;

obj Offer {
    # A variant on sale at the venue: its product, price there, and how many can still be
    # sold (None: no limit, untracked or selling on at zero).
    has product: SnackProduct,
        variant: SnackVariant,
        price_cents: int,
        left: int | None;
}

obj Shelf {
    # What a venue sells, read once per request: offers by variant id, every variant of
    # the cinema (for names), and its add-on groups by id.
    has offers: dict[str, Offer],
        variants: dict[str, tuple[SnackProduct, SnackVariant]],
        groups: dict[str, SnackAddonGroup];
}

def snack_name(product: SnackProduct, variant: SnackVariant) -> str {
    # "Popcorn · Large", or "Water" for a single item or a combo.
    return f"{product.name} · {variant_label(variant.option_values)}"
        if product.kind == "variants" and variant.option_values
        else product.name;
}

def shelf_of(tenant: Tenant, venue_id: str) -> Shelf {
    offers: dict[str, Offer] = {};
    every: dict[str, tuple[SnackProduct, SnackVariant]] = {};
    for p in products_of(tenant) {
        for v in variants_of(tenant, p) {
            vid = node_id(v);
            every[vid] = (p, v);
            (on, price) = offer(
                p.status,
                p.off_at,
                v.available,
                v.off_at,
                v.price_cents,
                v.venue_prices,
                venue_id
            );
            if not on or price is None {
                continue;
            }
            left: int | None = None;
            if v.track_stock {
                level = level_of(tenant, v, venue_id);
                if level["at_zero"] != "allow" {
                    left = level["available"];
                }
            }
            if left is None or left > 0 {
                offers[vid] = Offer(product=p, variant=v, price_cents=price, left=left);
            }
        }
    }
    return Shelf(
        offers=offers,
        variants=every,
        groups={node_id(g): g for g in addon_groups_of(tenant)}
    );
}

def _components(product: SnackProduct) -> list[ComponentFields] {
    return [
        ComponentFields(
            label=c["label"],
            quantity=c["quantity"],
            kind=c["kind"],
            variant_ids=c["variant_ids"]
        ) for c in product.components
    ];
}

def _options_at(group: SnackAddonGroup, venue_id: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return [
        o
        for o in group.options
        if venue_id not in o.get("off_at", [])
    ];
}

def _groups_at(
    shelf: Shelf, product: SnackProduct, venue_id: str
) -> list[dict[str, any]] | None {  # jac:ignore[W1037]
    # The product's add-on groups as customers choose from them at the venue, or None
    # when a required pick can't be made there.
    shown: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for gid in product.addon_group_ids {
        g = shelf.groups.get(gid);
        if g is None {
            continue;
        }
        options = _options_at(g, venue_id);
        if g.min_picks > 0
            and (not options or (not g.repeatable and len(options) < g.min_picks)) {
            return None;
        }
        if options {
            shown.append(
                {
                    "group_id": gid,
                    "label": g.label,
                    "min_picks": g.min_picks,
                    "max_picks": g.max_picks,
                    "repeatable": g.repeatable,
                    "options": [
                        {
                            "option_id": o["option_id"],
                            "name": o["name"],
                            "price_cents": o["price_cents"]
                        } for o in options
                    ]
                }
            );
        }
    }
    return shown;
}

def _left_shown(o: Offer) -> int | None {
    return o.left if o.left is not None and o.left <= FEW_LEFT else None;
}

def _product_at(shelf: Shelf, p: SnackProduct, venue_id: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    # How the menu shows a product at the venue, or None when nothing of it is on sale.
    if p.purpose {
        return None;
    }
    mine = [
        o
        for o in shelf.offers.values()
        if node_id(o.product) == node_id(p)
    ];
    mine = sorted(mine, key=lambda (o: Offer) -> int { return o.variant.position; });
    if not mine {
        return None;
    }
    groups = _groups_at(shelf, p, venue_id);
    if groups is None {
        return None;
    }
    components: list[dict[str, any]] = [];  # jac:ignore[W1037]
    if p.kind == "combo" {
        parts = _components(p);
        if not combo_on_sale(parts, {k: True for k in shelf.offers}) {
            return None;
        }
        for c in parts {
            components.append(
                {
                    "label": c.label,
                    "quantity": c.quantity,
                    "kind": c.kind,
                    "choices": [
                        {
                            "variant_id": vid,
                            "name": snack_name(
                                shelf.offers[vid].product, shelf.offers[vid].variant
                            )
                        }
                        for vid in c.variant_ids
                        if vid in shelf.offers
                    ]
                }
            );
        }
    }
    return {
        "product_id": node_id(p),
        "name": p.name,
        "brand": p.brand,
        "description": p.description,
        "kind": p.kind,
        "image_id": p.images[0]["image_id"] if p.images else "",
        "option_names": p.option_names,
        "from_cents": min(o.price_cents for o in mine),
        "variants": [
            {
                "variant_id": node_id(o.variant),
                "label": variant_label(o.variant.option_values),
                "option_values": o.variant.option_values,
                "price_cents": o.price_cents,
                "left": _left_shown(o)
            } for o in mine
        ],
        "addon_groups": groups,
        "components": components
    };
}

def menu_of(tenant: Tenant, venue_id: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    shelf = shelf_of(tenant, venue_id);
    products = products_of(tenant);
    menu: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for c in categories_of(tenant) {
        if c.status != "active" {
            continue;
        }
        cid = node_id(c);
        shown = [
            _product_at(shelf, p, venue_id)
            for p in products
            if p.category_id == cid
        ];
        listed = [
            s
            for s in shown
            if s is not None
        ];
        if listed {
            menu.append({"category_id": cid, "name": c.name, "products": listed});
        }
    }
    return menu;
}

def _problem(line: int, code: str, message: str) -> dict[str, any] {  # jac:ignore[W1037]
    return {"line": line, "code": code, "message": message};
}

def _whole(value: any) -> int | None {  # jac:ignore[W1037]
    return value if isinstance(value, int) and not isinstance(value, bool) else None;
}

def _addons(
    shelf: Shelf,
    o: Offer,
    picked: any,  # jac:ignore[W1037] the request's own data
    venue_id: str,
    at: int
) -> tuple[list[dict[str, any]], list[dict[str, any]]] {  # jac:ignore[W1037]
    # The add-ons picked for a line, checked against the product's groups at the venue:
    # (the add-ons, problems).
    name = snack_name(o.product, o.variant);
    ids = [str(x) for x in picked] if isinstance(picked, list) else [];
    chosen: list[dict[str, any]] = [];  # jac:ignore[W1037]
    problems: list[dict[str, any]] = [];  # jac:ignore[W1037]
    used: list[str] = [];
    for gid in o.product.addon_group_ids {
        g = shelf.groups.get(gid);
        if g is None {
            continue;
        }
        options = {x["option_id"]: x for x in _options_at(g, venue_id)};
        mine = [
            i
            for i in ids
            if i in options
        ];
        used.extend(mine);
        if len(mine) < g.min_picks or len(mine) > g.max_picks {
            problems.append(
                _problem(
                    at,
                    "ADDONS_COUNT",
                    f"{name}: choose {g.min_picks} to {g.max_picks} from {g.label}."
                        if g.min_picks != g.max_picks
                        else f"{name}: choose {g.min_picks} from {g.label}."
                )
            );
        } elif not g.repeatable and len(set(mine)) < len(mine) {
            problems.append(
                _problem(at, "ADDON_REPEATED", f"{name}: choose each extra once.")
            );
        }
        for i in mine {
            chosen.append(
                {
                    "option_id": i,
                    "name": options[i]["name"],
                    "price_cents": options[i]["price_cents"]
                }
            );
        }
    }
    if any(i not in used for i in ids) {
        problems.append(
            _problem(
                at, "ADDON_UNAVAILABLE", f"{name}: an extra isn't available any more."
            )
        );
    }
    return (chosen, problems);
}

def _choices(
    shelf: Shelf,
    o: Offer,
    picked: any,  # jac:ignore[W1037] the request's own data
    at: int
) -> tuple[list[dict[str, str]], list[dict[str, any]]] {  # jac:ignore[W1037]
    # A combo's filled components: (one entry per unit, problems).
    name = snack_name(o.product, o.variant);
    given = picked if isinstance(picked, list) else [];
    filled: list[dict[str, str]] = [];
    problems: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for (n, c) in enumerate(_components(o.product)) {
        wanted = given[n] if n < len(given) and isinstance(given[n], list) else [];
        ids = [str(x) for x in wanted];
        if c.kind == "fixed" and not ids {
            ids = [c.variant_ids[0]] * c.quantity;
        }
        if len(ids) != c.quantity
            or any(i not in c.variant_ids or i not in shelf.offers for i in ids) {
            problems.append(
                _problem(
                    at,
                    "COMBO_CHOICE",
                    f"{name}: choose {c.quantity} for {c.label} from what's available."
                )
            );
            continue;
        }
        for i in ids {
            filled.append(
                {
                    "component": c.label,
                    "variant_id": i,
                    "name": snack_name(shelf.offers[i].product, shelf.offers[i].variant)
                }
            );
        }
    }
    return (filled, problems);
}

def price_cart(
    tenant: Tenant,
    venue_id: str,
    lines: any  # jac:ignore[W1037]
) -> tuple[list[dict[str, any]], int, list[dict[str, any]]] {  # jac:ignore[W1037]
    shelf = shelf_of(tenant, venue_id);
    rows = lines if isinstance(lines, list) else [];
    priced: list[dict[str, any]] = [];  # jac:ignore[W1037]
    problems: list[dict[str, any]] = [];  # jac:ignore[W1037]
    if len(rows) > LINES_MAX {
        return ([], 0, [_problem(-1, "TOO_MANY", f"Add at most {LINES_MAX} snacks.")]);
    }
    # Units of each variant the cart needs, combo components included.
    needed: dict[str, int] = {};
    for (at, row) in enumerate(rows) {
        item: dict[str, any] = row if isinstance(row, dict) else {};  # jac:ignore[W1037]
        vid = str(item.get("variant_id", ""));
        o = shelf.offers.get(vid);
        if o is None {
            known = shelf.variants.get(vid);
            what = snack_name(known[0], known[1]) if known is not None else "A snack";
            problems.append(
                _problem(
                    at, "SNACK_UNAVAILABLE", f"{what} isn't available here any more."
                )
            );
            continue;
        }
        name = snack_name(o.product, o.variant);
        quantity = _whole(item.get("quantity"));
        if quantity is None or quantity < 1 or quantity > QUANTITY_MAX {
            problems.append(
                _problem(at, "QUANTITY", f"{name}: choose 1 to {QUANTITY_MAX}.")
            );
            continue;
        }
        (addons, addon_problems) = _addons(shelf, o, item.get("addons"), venue_id, at);
        problems.extend(addon_problems);
        filled: list[dict[str, str]] = [];
        if o.product.kind == "combo" {
            (filled, combo_problems) = _choices(shelf, o, item.get("choices"), at);
            problems.extend(combo_problems);
        }
        needed[vid] = needed.get(vid, 0) + quantity;
        for f in filled {
            needed[f["variant_id"]] = needed.get(f["variant_id"], 0) + quantity;
        }
        unit = o.price_cents + sum(a["price_cents"] for a in addons);
        priced.append(
            {
                "variant_id": vid,
                "product_id": node_id(o.product),
                "purpose": o.product.purpose,
                "name": name,
                "quantity": quantity,
                "unit_cents": unit,
                "line_cents": unit * quantity,
                "addons": addons,
                "choices": filled
            }
        );
    }
    for (vid, count) in needed.items() {
        o = shelf.offers.get(vid);
        if o is not None and o.left is not None and count > o.left {
            problems.append(
                _problem(
                    -1,
                    "NOT_ENOUGH",
                    f"Only {o.left} {snack_name(o.product, o.variant)} left."
                )
            );
        }
    }
    if problems {
        return ([], 0, problems);
    }
    return (priced, sum(p["line_cents"] for p in priced), []);
}
