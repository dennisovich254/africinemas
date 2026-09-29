"""Price lists and quotes (P3.6, architecture §27, §28). Tenant-scoped endpoints, listed
in tests/isolation/registry.jac.

- get_price_list (showtimes.read, at any venue) and save_price_list (tenant.settings.update): one list
  per cinema, checked by core/catalog/pricing.jac, its version bumped on every save.
- quote_tickets (showtimes.read at the screening's venue): prices seats of a published
  screening. Each seat's zone comes from the screening's own seat slots and each price
  from the list; nothing else in the request is read, so a client can't set a price.
  Quotes record the price list version they used (§27: orders will snapshot them).
- The public quote for customers comes with checkout (plan 4.6), on the same engine.
"""

import from datetime { datetime }
import from core.clock { now }
import from core.authz.policy { Forbidden, ROLE_PERMISSIONS, Resource, require }
import from core.authz.context { NotFound, TenantScope, on_shift, scoped }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.catalog.models { PriceList, Screening, SeatSlot }
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues { find_screening }
import from core.catalog.storefront { PUBLIC_STATES }
import from core.catalog.pricing {
    PriceTable,
    PricingError,
    parse_price_list,
    price_list_data,
    price_ticket
}

glob READ: str = "showtimes.read",
     CONFIGURE: str = "tenant.settings.update",
     QUOTE_MAX_SEATS: int = 20;

def _price_list(scope: TenantScope) -> PriceList | None {
    if not scope.tenant.price_list_id {
        return None;
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found: any = jobj(scope.tenant.price_list_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as PriceList if isinstance(found, PriceList) else None;
}

def _view(price_list: PriceList) -> dict[str, any] {  # jac:ignore[W1037]
    view = dict(price_list.data);
    view["version"] = price_list.version;
    view["updated_at"] = price_list.updated_at;
    return view;
}

def _get_price_list(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The list is cinema-wide, but staff limited to a venue sell from it too: holding
    # showtimes.read anywhere in the cinema is enough to read it.
    scope = on_shift(tenant);
    if not any(READ in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments) {
        raise Forbidden(READ);
    }
    found = _price_list(scope);
    return {"ok": True, "price_list": _view(found) if found is not None else None};
}

def _save_price_list(
    tenant: str,
    timezone: str,
    ticket_types: list[any],  # jac:ignore[W1037]
    prices: list[any],  # jac:ignore[W1037]
    surcharges: list[any],  # jac:ignore[W1037]
    service_fee_cents: int
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    (table, problems) = parse_price_list(
        {
            "timezone": timezone,
            "ticket_types": ticket_types,
            "prices": prices,
            "surcharges": surcharges,
            "service_fee_cents": service_fee_cents
        }
    );
    if table is None {
        raise Refused(
            "invalid_price_list",
            "This price list has problems to fix before it can be saved.",
            {"problems": [{"code": p.code, "message": p.message} for p in problems]}
        );
    }
    existing = _price_list(scope);
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        if existing is None {
            saved = PriceList(tenant_id=scope.ctx.tenant_id);
            scope.tenant ++> saved;
            attach_to_tenant(saved, scope.tenant);
            scope.tenant.price_list_id = node_id(saved);
        } else {
            saved = existing as PriceList;
        }
        saved.data = price_list_data(table as PriceTable);
        saved.version += 1;
        saved.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "price_list": _view(saved)};
}

def _slots_by_label(scope: TenantScope, screening: Screening) -> dict[str, SeatSlot] {
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        slots = [screening-->[?:SeatSlot]];
    } finally {
        restore(me);
    }
    return {s.label: s for s in slots};
}

def _quote_tickets(tenant: str, screening_id: str, items: list[any]) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screening = find_screening(scope.tenant, screening_id);
    if screening is None {
        raise NotFound();
    }
    require(
        scope.ctx,
        READ,
        Resource(tenant_id=scope.ctx.tenant_id, venue_id=screening.venue_id)
    );
    if screening.state not in PUBLIC_STATES {
        raise Refused("not_published", "Only published screenings can be priced.");
    }
    if not items
        or len(items) > QUOTE_MAX_SEATS
        or any(not isinstance(i, dict) for i in items) {
        raise Refused(
            "no_seats",
            f"Choose between 1 and {QUOTE_MAX_SEATS} seats, each with a ticket type."
        );
    }
    price_list = _price_list(scope);
    if price_list is None {
        raise Refused("no_prices", "Set up this cinema's prices first.");
    }
    (parsed, _) = parse_price_list(price_list.data);
    table = parsed as PriceTable;
    slots = _slots_by_label(scope, screening);
    starts = datetime.fromisoformat(screening.starts_at);
    lines: list[dict[str, any]] = [];  # jac:ignore[W1037]
    seen: set[str] = set();
    for item in items {
        # Only the seat and the ticket type are read; any price sent along is ignored.
        label = str(item.get("seat_label", "")).strip().upper();
        ticket = str(item.get("ticket_type", "")).strip().upper();
        if label in seen {
            raise Refused("duplicate_seat", f"Seat {label} is in the quote twice.");
        }
        seen.add(label);
        slot = slots.get(label);
        if slot is None {
            raise Refused("unknown_seat", f"This screening has no seat {label}.");
        }
        if slot.state != "available" {
            raise Refused("seat_not_for_sale", f"Seat {label} isn't for sale.");
        }
        try {
            priced = price_ticket(table, ticket, slot.zone, starts);
        } except PricingError as e {
            raise Refused(e.code, f"Seat {label}: {e.message}");
        }
        priced["seat_label"] = label;
        priced["zone"] = slot.zone;
        priced["ticket_type"] = ticket;
        priced["ticket_name"] = table.ticket_types[ticket];
        lines.append(priced);
    }
    return {
        "ok": True,
        "quote": {
            "screening_id": screening_id,
            "currency": table.currency,
            "price_list_version": price_list.version,
            "lines": lines,
            "total_cents": sum([l["total_cents"] for l in lines])
        }
    };
}

def:priv get_price_list(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_price_list(tenant); });  # jac:ignore[W1037]
}

def:priv save_price_list(
    tenant: str,
    timezone: str,
    ticket_types: list[any],  # jac:ignore[W1037]
    prices: list[any],  # jac:ignore[W1037]
    surcharges: list[any],  # jac:ignore[W1037]
    service_fee_cents: int
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _save_price_list(  # jac:ignore[W1037]
            tenant, timezone, ticket_types, prices, surcharges, service_fee_cents
        ); }
    );
}

def:priv quote_tickets(
    tenant: str,
    screening_id: str,
    items: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _quote_tickets(tenant, screening_id, items); }  # jac:ignore[W1037]
    );
}
