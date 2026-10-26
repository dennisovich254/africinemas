"""Extra snacks before showtime (P12.14). A private ticket link or an authorized
counter agent proves access. The booking reference alone is never a public credential.
Actions share one context check: menu, price, place, pay, status; cash is staff only.
"""

import hashlib;
import from datetime { datetime }
import from core.clock { now }
import from core.claims { claim, release, make_permanent }
import from core.authz.context { TenantScope, NotFound, on_shift }
import from core.authz.policy { require, Resource }
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { require_live }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id
}
import from core.catalog.answers { answer, Refused }
import from core.catalog.venues { find_screening, find_venue, screenings_of_cinema }
import from core.booking.models { Order }
import from core.booking.hold_api { check_holder }
import from core.booking.order_api { snack_request }
import from core.booking.ticket_delivery { order_by_link, booking_view }
import from core.booking.ticket_codes { PICKUPS, reserve_reference, pickup_payload }
import from core.booking.snack_additions { addition_allowed, additions }
import from core.booking.snack_sale { place_sale, cash_sale, _view }
import from core.snacks.menu { menu_of, price_cart }
import from core.payments.payment_api { pay_order, latest_intent, payment_view }
import from core.payments.settlement { settle }
import from core.payments.choice { payment_provider, ProviderNotConfigured }
import from core.audit.log { audited }

glob ADDING: str = "booking-snack-addition";

def _counter(tenant: str, reference: str) -> tuple[TenantScope, Order] {
    scope = on_shift(tenant);
    cinema = scope.tenant;
    screenings = screenings_of_cinema(cinema);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            o for s in screenings
            for o in [s-->[?:Order]]
            if o.reference == reference.strip().upper()
                and not o.booking_id
                and o.status == "confirmed"
                and bool(o.lines)
        ];
    } finally {
        restore(me);
    }
    if len(found) != 1 {
        raise NotFound();
    }
    booking = found[0];
    screening = find_screening(cinema, booking.screening_id);
    if screening is None {
        raise NotFound();
    }
    require(
        scope.ctx,
        "bookings.create",
        Resource(tenant_id=node_id(cinema), venue_id=screening.venue_id)
    );
    return (scope, booking);
}

def _pickup(cinema: Tenant, booking: Order, venue_id: str) {
    # Called under ADDING. Allocate once, even if this booking originally had no snacks.
    if booking.pickup_reference {
        return;
    }
    owner = f"{node_id(cinema)}|{node_id(booking)}";
    candidate = reserve_reference(owner, 0, namespace=PICKUPS);
    reference = claim("booking-pickup", node_id(booking), candidate);
    if reference != candidate {
        release(PICKUPS, candidate, owner);
    }
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        booking.pickup_reference = reference;
        booking.pickup_qr = pickup_payload(reference);
        booking.snack_venue_id = venue_id;
        commit_now();
    } finally {
        restore(me);
    }
    make_permanent(PICKUPS, reference, owner);
}

def _run(  # jac:ignore[W3030] shared checkout RPC fields
    cinema: Tenant,
    booking: Order,
    action: str,
    holder: str,
    key: str,
    lines: list[any],  # jac:ignore[W1037]
    phone: str,
    email: str,
    scope: TenantScope | None = None
) -> dict[str, any] {  # jac:ignore[W1037]
    require_live(cinema);
    screening = find_screening(cinema, booking.screening_id);
    if screening is None or booking.booking_id or not booking.lines {
        raise NotFound();
    }
    allowed = addition_allowed(
        booking.status, screening.starts_at, now(), screening.state
    );
    if action == "menu" {
        return {
            "ok": True,
            "booking": booking_view(cinema, booking),
            "can_add": allowed,
            "categories": menu_of(cinema, screening.venue_id) if allowed else []
        };
    }
    if action != "status" and not allowed {
        raise Refused(
            "showtime_started",
            "Extra snacks can only be bought before the showtime starts."
        );
    }
    if action == "price" {
        (priced, total, problems) = price_cart(
            cinema, screening.venue_id, snack_request(lines)
        );
        if problems {
            raise Refused(
                "snacks_unavailable", problems[0]["message"], {"problems": problems}
            );
        }
        return {"ok": True, "lines": priced, "total_cents": total};
    }
    check_holder(holder);
    # Separate payment idempotency namespaces for each booking and selling identity.
    seller = scope.ctx.member_root_id if scope is not None else "guest";
    sale_holder = hashlib.sha256(
        f"{node_id(booking)}|{seller}|{holder}".encode()
    ).hexdigest();
    if action == "place" {
        mine = fresh_node_id();
        if claim(ADDING, node_id(booking), mine, 60) != mine {
            raise Refused(
                "in_progress",
                "Another snack addition is being saved. Try again in a moment."
            );
        }
        try {
            venue = find_venue(cinema, screening.venue_id);
            if venue is None {
                raise NotFound();
            }
            _pickup(cinema, booking, screening.venue_id);
            return place_sale(cinema, venue, sale_holder, key, lines, booking);
        } finally {
            release(ADDING, node_id(booking), mine);
        }
    }
    found = [
        o
        for o in additions(cinema, booking)
        if o.holder == sale_holder
    ];
    order = found[-1] if found else None;
    if order is None {
        raise Refused("no_order", "Choose the extra snacks first.");
    }
    if action == "status" {
        intent = latest_intent(cinema, order);
        if intent is not None {
            try {
                settle(cinema, intent, payment_provider());
            } except ProviderNotConfigured {
                # Payment status remains readable when the provider is unavailable.
                intent = latest_intent(cinema, order);
            }
        }
        return {
            "ok": True,
            "order": _view(order),
            "payment": payment_view(intent) if intent is not None else None
        };
    }
    if action == "pay" and order.status == "confirmed" {
        paid_intent = latest_intent(cinema, order);
        if paid_intent is not None {
            return {"ok": True, "payment": payment_view(paid_intent)};
        }
    }
    if action == "cash" and scope is not None and order.status == "confirmed" {
        return {"ok": True, "order": _view(order)};
    }
    if order.status != "pending_payment"
        or now() >= datetime.fromisoformat(order.pay_by) {
        raise Refused(
            "order_expired", "The time to pay has ended. Choose the snacks again."
        );
    }
    if action == "cash" and scope is not None {
        return cash_sale(scope, order);
    }
    if action == "pay" {
        return pay_order(
            cinema,
            lambda -> Order | None { return order; },
            "Choose the extra snacks first.",
            sale_holder,
            phone,
            email,
            key,
            scope.ctx.member_root_id if scope is not None else ""
        );
    }
    raise Refused("invalid_action", "Choose a snack action.");
}

def _public(  # jac:ignore[W3030] shared checkout RPC fields
    slug: str,
    token: str,
    action: str,
    holder: str,
    key: str,
    lines: list[any],  # jac:ignore[W1037]
    phone: str,
    email: str
) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, booking) = order_by_link(slug, token);
    return _run(cinema, booking, action, holder, key, lines, phone, email);
}

def _staff(  # jac:ignore[W3030] shared checkout RPC fields
    tenant: str,
    reference: str,
    action: str,
    holder: str,
    key: str,
    lines: list[any],  # jac:ignore[W1037]
    phone: str,
    email: str
) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, booking) = _counter(tenant, reference);
    return _run(scope.tenant, booking, action, holder, key, lines, phone, email, scope);
}

def:pub more_snacks(  # jac:ignore[W3030] shared checkout RPC fields
    slug: str,
    token: str,
    action: str = "menu",
    holder: str = "",
    key: str = "",
    lines: list[any] = [],  # jac:ignore[W1037,W3036] never mutated; RPC cart default
    phone: str = "",
    email: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _public(
            slug, token, action, holder, key, lines, phone, email
        ); }
    );  # jac:ignore[W1037]
}

def:protect counter_more_snacks(  # jac:ignore[W3030] shared checkout RPC fields
    tenant: str,
    reference: str,
    action: str = "menu",
    holder: str = "",
    key: str = "",
    lines: list[any] = [],  # jac:ignore[W1037,W3036] never mutated; RPC cart default
    phone: str = "",
    email: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    work = lambda -> any { return answer(
        lambda -> any { return _staff(
            tenant, reference, action, holder, key, lines, phone, email
        ); }
    ); };  # jac:ignore[W1037]
    if action in ["place", "pay", "cash"] {
        return audited(tenant, "sale.extra_snacks", "order", reference, work);
    }
    return work();
}
