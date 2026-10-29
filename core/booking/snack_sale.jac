"""Snacks only, at the box office (P12.10, ADR-0073; improvements #21, #26).

A walk-in buys snacks without a ticket, paying cash or with M-Pesa at the counter. The
order hangs off the **venue** instead of a showtime (Order.screening_id is ""), and
otherwise goes the way a ticket order does, in the same steps, one request each:

1. place_snack_order: the menu's prices (price_cart), the stock set aside
   (reserve_snacks) until pay_by, and the order listed with the open ones
   (OPEN_ORDERS), so an unpaid one expires and gives its stock back (resolver).
2. sell_snacks_for_cash confirms it at once (confirm_order: the stock sold, the ledger
   entry "cash" recorded by the agent); sell_snacks_with_mpesa sends the M-Pesa prompt
   (payment_api.pay_order) and counter_snack_payment follows it, as my_payment does.
3. Paid, it has a pickup code (P12.9): the agent hands the snacks over with the Snack
   counter's hand_over_snacks, on the same page.

Each needs a login, an open shift and bookings.create at the venue, as selling tickets
there does; the cinema must be live (P14.1).
"""

import secrets;
import json;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, release, renew, holder as claim_holder }
import from core.authz.policy { Resource, Forbidden, authorize, require }
import from core.authz.context { NotFound, TenantScope, on_shift }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    fresh_node_id,
    assign_id,
    act_as,
    restore,
    commit_now
}
import from core.tenancy.open_cinema { require_live }
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Venue }
import from core.catalog.venues { find_venue, find_screening }
import from core.catalog.pricing { CURRENCY }
import from core.snacks.menu { menu_of, price_cart }
import from core.snacks.order_stock { reserve_snacks, release_snacks }
import from core.booking.models { Order }
import from core.booking.snack_additions { additions }
import from core.booking.hold_api { check_holder, seconds_from_env }
import from core.booking.order_api {
    ORDER_KEYS,
    OPEN_ORDERS,
    PROVISIONAL_SECONDS,
    KEY_SECONDS,
    PAY_ENV,
    PAY_SECONDS,
    check_key,
    snack_request
}
import from core.booking.confirm { Takings, confirm_order }
import from core.booking.ticket_codes { ticket_key, TicketKeyMissing }
import from core.payments.payment_api {
    ORDER_PAYMENT,
    stored_intent,
    pay_order,
    latest_intent,
    payment_view
}
import from core.payments.settlement { FINALIZE }
import from core.payments.state { PaymentState, is_final }
import from core.audit.log { audited }
import from core.tenancy.shifts { shift_started_at }
import from core.payments.reconcile { require_counted }

glob SELL: str = "bookings.create";

def _venue(tenant: str, venue_id: str) -> tuple[TenantScope, Venue] {
    # The caller's cinema and the venue, once they may sell there.
    scope = on_shift(tenant);
    require_live(scope.tenant);
    venue = find_venue(scope.tenant, venue_id);
    if venue is None {
        raise NotFound();
    }
    require(
        scope.ctx, SELL, Resource(tenant_id=scope.ctx.tenant_id, venue_id=venue_id)
    );
    return (scope, venue);
}

def _orders(cinema: Tenant, venue: Venue, holder: str) -> list[Order] {
    # The venue's snacks-only orders for this sale (its holder id), oldest first.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            o
            for o in [venue-->[?:Order]]
            if o.holder == holder and not o.booking_id
        ];
    } finally {
        restore(me);
    }
    return sorted(found, key=lambda (o: Order) -> str { return o.created_at; });
}

def _pending(cinema: Tenant, venue: Venue, holder: str) -> Order | None {
    waiting = [
        o
        for o in _orders(cinema, venue, holder)
        if o.status == "pending_payment"
    ];
    return waiting[-1] if waiting else None;
}

def _view(order: Order) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "reference": order.reference,
        "status": order.status,
        "currency": order.currency,
        "snacks": [dict(l) for l in order.snack_lines],
        "total_cents": order.total_cents,
        "pay_by": order.pay_by,
        # Paid: the code the Snack counter hands them over with (P12.9).
        "pickup_reference": order.pickup_reference,
        "pickup_qr": order.pickup_qr,
        "handed_over": bool(order.snacks_collected_at)
    };
}

def _venues(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The venues where the caller may sell, by name: where a snacks-only sale can be.
    scope = on_shift(tenant);
    require_live(scope.tenant);
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        venues = [v for v in [scope.tenant-->[?:Venue]]];
    } finally {
        restore(me);
    }
    mine = [
        {"venue_id": node_id(v), "name": v.name}
        for v in venues
        if authorize(
            scope.ctx,
            SELL,
            Resource(tenant_id=scope.ctx.tenant_id, venue_id=node_id(v))
        )
    ];
    if not mine {
        raise Forbidden(SELL);
    }
    return {
        "ok": True,
        "venues": sorted(
            mine, key=lambda (v: dict[str, str]) -> str { return v["name"]; }
        )
    };
}

def _price(tenant: str, venue_id: str, lines: any) -> dict[str, any] {  # jac:ignore[W1037]
    # The cart's prices at the venue, as price_snacks gives them online.
    (scope, venue) = _venue(tenant, venue_id);
    (priced, total, problems) = price_cart(
        scope.tenant, venue_id, snack_request(lines)
    );
    if problems {
        raise Refused(
            "snacks_unavailable", problems[0]["message"], {"problems": problems}
        );
    }
    return {"ok": True, "lines": priced, "total_cents": total};
}

def _menu(tenant: str, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, venue) = _venue(tenant, venue_id);
    return {"ok": True, "categories": menu_of(scope.tenant, venue_id)};
}

def _place(
    tenant: str,
    venue_id: str,
    holder: str,
    idempotency_key: str,
    snacks: any  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, venue) = _venue(tenant, venue_id);
    return place_sale(scope.tenant, venue, holder, idempotency_key, snacks);
}

def place_sale(
    cinema: Tenant,
    venue: Venue,
    holder: str,
    idempotency_key: str,
    snacks: any,  # jac:ignore[W1037]
    booking: Order | None = None
) -> dict[str, any] {  # jac:ignore[W1037]
    venue_id = node_id(venue);
    check_holder(holder);
    check_key(idempotency_key);
    asked = snack_request(snacks);
    if not asked {
        raise Refused("no_snacks", "Choose at least one snack.");
    }
    key_name = f"{node_id(cinema)}:{holder}:{idempotency_key}";
    if booking is not None {
        key_name = f"addition:{node_id(booking)}:{holder}:{idempotency_key}";
    }
    existing = claim_holder(ORDER_KEYS, key_name);
    if existing is not None {
        # The same request again (a retried tap): the order it made.
        found = _orders(cinema, venue, holder);
        if booking is not None {
            found = additions(cinema, booking);
        }
        for o in found {
            if node_id(o) == existing {
                if booking is not None
                    and o.snack_request != json.dumps(asked, sort_keys=True) {
                    raise Refused(
                        "idempotency_conflict",
                        "These snacks differ from the saved request. Start a new addition."
                    );
                }
                return {"ok": True, "order": _view(o)};
            }
        }
        raise Refused(
            "in_progress", "This sale is still being set up. Try again in a moment."
        );
    }
    (lines, cents, problems) = price_cart(cinema, venue_id, asked);
    if problems {
        raise Refused(
            "snacks_unavailable", problems[0]["message"], {"problems": problems}
        );
    }
    if booking is not None and any(l.get("purpose") for l in lines) {
        raise Refused(
            "invalid_snacks",
            "Glasses cannot be added to an issued ticket through the snack menu."
        );
    }
    order_ref = fresh_node_id();
    if claim(ORDER_KEYS, key_name, order_ref, PROVISIONAL_SECONDS) != order_ref {
        raise Refused(
            "in_progress", "This sale is still being set up. Try again in a moment."
        );
    }
    claim(OPEN_ORDERS, order_ref, node_id(cinema), PROVISIONAL_SECONDS);
    stamp = now();
    held: list[dict[str, any]] = [];  # jac:ignore[W1037]
    me = node_id(root);
    try {
        held = reserve_snacks(cinema, venue_id, lines);
        act_as(cinema.principal_root_id);
        order = Order(
            tenant_id=node_id(cinema),
            screening_id=booking.screening_id if booking is not None else "",
            booking_id=node_id(booking) if booking is not None else "",
            pickup_reference=booking.pickup_reference if booking is not None else "",
            pickup_qr=booking.pickup_qr if booking is not None else "",
            holder=holder,
            hold_id="",
            idempotency_key=idempotency_key,
            reference=secrets.token_hex(4).upper(),
            currency=CURRENCY,
            total_cents=cents,
            snack_request=json.dumps(asked, sort_keys=True),
            snack_lines=lines,
            snacks_cents=cents,
            snack_venue_id=venue_id,
            snack_stock=held,
            created_at=stamp.isoformat(),
            pay_by=(
                stamp + timedelta(seconds=seconds_from_env(PAY_ENV, PAY_SECONDS))
            ).isoformat()
        );
        assign_id(order, order_ref);
        if booking is None {
            venue ++> order;
        } else {
            screening = find_screening(cinema, booking.screening_id);
            booking ++> order;
            if screening is None {
                raise NotFound();
            }
            screening ++> order;
            order.pay_by = min(order.pay_by, screening.starts_at);
        }
        attach_to_tenant(order, cinema);
        commit_now();
    } except Exception as e {
        restore(me);
        release_snacks(cinema, venue_id, held);
        release(OPEN_ORDERS, order_ref, node_id(cinema));
        release(ORDER_KEYS, key_name, order_ref);
        raise e;
    }
    restore(me);
    renew(ORDER_KEYS, key_name, order_ref, KEY_SECONDS);
    renew(OPEN_ORDERS, order_ref, node_id(cinema), 0);
    return {"ok": True, "order": _view(order)};
}

def _waiting(scope: TenantScope, venue: Venue, holder: str) -> Order {
    order = _pending(scope.tenant, venue, holder);
    if order is None {
        raise Refused("no_order", "Add the snacks to the sale first.");
    }
    if datetime.fromisoformat(order.pay_by) <= now() {
        raise Refused("order_expired", "This sale took too long. Start it again.");
    }
    return order;
}

def _cash(tenant: str, venue_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, venue) = _venue(tenant, venue_id);
    # The pickup code is signed as tickets are (P12.9): no key, no code.
    try {
        ticket_key();
    } except TicketKeyMissing {
        raise Refused(
            "tickets_unavailable",
            "Sales can't be completed right now (the server has no signing key). Ask an administrator."
        );
    }
    return cash_sale(scope, _waiting(scope, venue, holder));
}

def cash_sale(scope: TenantScope, order: Order) -> dict[str, any] {  # jac:ignore[W1037]
    require_counted(
        scope.tenant,
        scope.ctx.member_root_id,
        shift_started_at(scope.ctx.tenant_id, scope.ctx.member_root_id)
    );
    order_id = node_id(order);
    active = claim_holder(ORDER_PAYMENT, order_id);
    if active is not None {
        intent = stored_intent(scope.tenant, active);
        if intent is not None and not is_final(PaymentState(intent.state)) {
            raise Refused(
                "payment_in_progress",
                "An M-Pesa prompt for this sale is still open on the customer's phone."
            );
        }
    }
    member = scope.ctx.member_root_id;
    mine = f"cash:{member}|{fresh_node_id()}";
    if claim(FINALIZE, order_id, mine, PROVISIONAL_SECONDS) != mine {
        raise Refused("already_paid", "This sale has been paid.");
    }
    try {
        confirm_order(
            scope.tenant,
            order,
            Takings(
                payment_id=f"cash-{fresh_node_id()}",
                amount_cents=order.total_cents,
                receipt=f"CASH-{order.reference}",
                note="Cash at the box office, extra snacks"
                    if order.booking_id
                    else "Cash at the box office, snacks only",
                method="cash",
                recorded_by=member
            )
        );
    } except Exception as e {
        release(FINALIZE, order_id, mine);
        raise e;
    }
    renew(FINALIZE, order_id, mine, 0);
    return {"ok": True, "order": _view(order)};
}

def _mpesa(
    tenant: str, venue_id: str, holder: str, phone: str, email: str, key: str
) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, venue) = _venue(tenant, venue_id);

    def find -> Order | None {
        return _pending(scope.tenant, venue, holder);
    }
    return pay_order(
        scope.tenant,
        find,
        "Add the snacks to the sale first.",
        holder,
        phone,
        email,
        key,
        scope.ctx.member_root_id
    );
}

def _status(tenant: str, venue_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The sale's latest order and its latest payment, for the counter page to follow.
    (scope, venue) = _venue(tenant, venue_id);
    found = _orders(scope.tenant, venue, holder);
    if not found {
        raise Refused("no_order", "Add the snacks to the sale first.");
    }
    order = found[-1];
    intent = latest_intent(scope.tenant, order);
    return {
        "ok": True,
        "order": _view(order),
        "payment": payment_view(intent) if intent is not None else None
    };
}

def:protect counter_snack_venues(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _venues(tenant); });  # jac:ignore[W1037]
}

def:protect counter_price_snacks(
    tenant: str,
    venue_id: str,
    lines: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _price(tenant, venue_id, lines); });  # jac:ignore[W1037]
}

def:protect counter_snack_menu(tenant: str, venue_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _menu(tenant, venue_id); });  # jac:ignore[W1037]
}

def:protect place_snack_order(
    tenant: str,
    venue_id: str,
    holder: str,
    idempotency_key: str,
    snacks: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _place(
            tenant, venue_id, holder, idempotency_key, snacks
        ); }  # jac:ignore[W1037]
    );
}

def:protect sell_snacks_for_cash(
    tenant: str, venue_id: str, holder: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "sale.snacks_cash",
        "order",
        "",
        lambda -> any { return _cash(tenant, venue_id, holder); }  # jac:ignore[W1037]
    );
}

def:protect sell_snacks_with_mpesa(
    tenant: str,
    venue_id: str,
    holder: str,
    phone: str,
    email: str,
    idempotency_key: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "sale.snacks_mpesa",
        "order",
        "",
        lambda -> any { return _mpesa(
            tenant, venue_id, holder, phone, email, idempotency_key
        ); }  # jac:ignore[W1037]
    );
}

def:protect counter_snack_payment(
    tenant: str, venue_id: str, holder: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _status(tenant, venue_id, holder); });  # jac:ignore[W1037]
}
