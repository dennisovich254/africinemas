"""Orders (P4.5, architecture §26, §27; ADR-0007, ADR-0010): public endpoints, no login,
listed in tests/isolation/registry.jac.

A visitor holding seats (P4.3) places an order: a ticket type for each seat of their
hold, no more and no fewer. The server prices every line from the cinema's price list
(the client's prices are never read) and the order keeps that snapshot: each line's
price, extras and fee, the total, the currency and the price list version. The order
waits for payment (Phase 5) until pay_by; its hold becomes "paying", its seats
PAYMENT_PENDING, and their seat claims permanent, so nobody else can hold them and the
sweeper (P4.4) leaves them alone.

Idempotency (§26): the browser sends a key with the order. The key is an atomic claim
naming the order made for it (claim first, then create; ADR-0007), so the same key
again returns the same order, even from racing requests; one that arrives while the
order is still being made is told to ask again ("order_in_progress"). The same key
with a different request is refused ("key_reused"). The hold is claimed by its order
too, so different keys for one hold still make one order ("already_ordered").
Claims are provisional until the order commits (explicitly: commit_now, JI-038); a
failed request releases them.

For checkout (P4.6): public_ticket_types lists the tickets to choose from and
quote_hold prices the holder's seats exactly as place_order would, saving nothing.

Still to come (Phase 5): payment, and ending an order not paid by pay_by.
"""

import secrets;
import re;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, release, renew, holder as claim_holder }
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { open_cinema }
import from core.authz.context { NotFound }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id,
    assign_id
}
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Screening, SeatSlot, PriceList }
import from core.catalog.venues { slots_of }
import from core.catalog.pricing { PriceTable, parse_price_list }
import from core.catalog.pricing_api { cinema_prices, price_seats }
import from core.booking.models { Order, SeatHold }
import from core.booking.availability { SeatState }
import from core.booking.hold_api {
    MAX_SEATS,
    seconds_from_env,
    seat_namespace,
    showtime_on_sale,
    check_holder,
    current_hold
}

glob KEY_PATTERN: str = "[A-Za-z0-9_-]{16,64}",
     ORDER_KEYS: str = "order-key",
     ORDER_HOLDS: str = "order-hold",
     # How long a key keeps its order once made (§26: keys expire), and how long a
     # claim stays provisional while its request runs.
     KEY_SECONDS: int = 24 * 60 * 60,
     PROVISIONAL_SECONDS: int = 60,
     PAY_ENV: str = "AFRICINEMAS_PAY_SECONDS",
     PAY_SECONDS: int = 900;

def request_lines(items: list[any]) -> list[list[str]] {  # jac:ignore[W1037]
    # The request's [seat, ticket type] pairs, cleaned and sorted, so the same order
    # sent again compares equal. Refuses an empty, oversized or repeated request.
    if not isinstance(items, list)
        or not items
        or len(items) > MAX_SEATS
        or any(not isinstance(i, dict) for i in items) {
        raise Refused(
            "no_seats", f"Choose between 1 and {MAX_SEATS} seats, each with a ticket."
        );
    }
    pairs = [
        [
            str(i.get("seat_label", "")).strip().upper(),
            str(i.get("ticket_type", "")).strip().upper()
        ] for i in items
    ];
    labels = [p[0] for p in pairs];
    for label in labels {
        if labels.count(label) > 1 {
            raise Refused("duplicate_seat", f"Seat {label} is in the order twice.");
        }
    }
    return sorted(pairs);
}

def check_key(key: str) {
    if not isinstance(key, str) or not re.fullmatch(KEY_PATTERN, key) {
        raise Refused(
            "invalid_key",
            "This page lost track of your order. Reload it and try again."
        );
    }
}

def _view(order: Order) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "reference": order.reference,
        "status": order.status,
        "seats": [l["seat_label"] for l in order.lines],
        "currency": order.currency,
        "price_list_version": order.price_list_version,
        "lines": [dict(l) for l in order.lines],
        "total_cents": order.total_cents,
        "created_at": order.created_at,
        "pay_by": order.pay_by
    };
}

def _stored(cinema: Tenant, order_ref: str) -> Order | None {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(order_ref);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as Order if isinstance(found, Order) else None;
}

def _replay(
    cinema: Tenant, order_ref: str, screening_id: str, wanted: list[list[str]]
) -> dict[str, any] {  # jac:ignore[W1037]
    # The answer for a key that already names an order.
    order = _stored(cinema, order_ref);
    if order is None {
        raise Refused(
            "order_in_progress",
            "Your order is still being placed. Try again in a moment."
        );
    }
    if order.screening_id != screening_id or order.request != wanted {
        raise Refused(
            "key_reused", "This page sent a different order. Reload it and try again."
        );
    }
    return {"ok": True, "order": _view(order)};
}

def _settle(
    key_name: str,
    hold_id: str,
    order_ref: str,
    screening_id: str,
    holder: str,
    seats: list[str]
) {
    # Once the order has committed: the key keeps naming it for KEY_SECONDS, the hold
    # and its seats stay claimed until payment ends the order (Phase 5).
    renew(ORDER_KEYS, key_name, order_ref, KEY_SECONDS);
    renew(ORDER_HOLDS, hold_id, order_ref, 0);
    for label in seats {
        renew(seat_namespace(screening_id), label, holder, 0);
    }
}

def _priced(
    cinema: Tenant, screening: Screening, holder: str, wanted: list[list[str]]
) -> tuple[SeatHold, PriceList, PriceTable, list[SeatSlot], list[dict[str, any]]] {  # jac:ignore[W1037]
    # The holder's live hold, priced for `wanted`: a ticket for each of its seats, and
    # only those. The server's prices, never the client's.
    hold = current_hold(cinema, screening, holder);
    if hold is None {
        raise Refused("no_hold", "Your seats are no longer held. Choose them again.");
    }
    if sorted([p[0] for p in wanted]) != sorted(hold.seats) {
        raise Refused(
            "seats_not_held", "Choose a ticket for each of your seats, and only those."
        );
    }
    price_list = cinema_prices(cinema);
    if price_list is None {
        raise Refused("no_prices", "This cinema isn't selling tickets online yet.");
    }
    (parsed, _) = parse_price_list(price_list.data);
    table = parsed as PriceTable;
    hold_id = node_id(hold);
    slots = slots_of(cinema, screening);
    lines = price_seats(
        table,
        {x.label: x for x in slots},
        [{"seat_label": p[0], "ticket_type": p[1]} for p in wanted],
        datetime.fromisoformat(screening.starts_at),
        lambda (slot: SeatSlot) -> bool { return slot.hold_id == hold_id
            and slot.state == SeatState.HELD.value; }
    );
    return (hold, price_list, table, slots, lines);
}

def _place_order(
    slug: str,
    screening_id: str,
    holder: str,
    idempotency_key: str,
    items: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, screening) = showtime_on_sale(slug, screening_id);
    check_holder(holder);
    check_key(idempotency_key);
    wanted = request_lines(items);
    key_name = f"{node_id(cinema)}:{holder}:{idempotency_key}";
    existing = claim_holder(ORDER_KEYS, key_name);
    if existing is not None {
        return _replay(cinema, existing, screening_id, wanted);
    }
    (hold, price_list, table, slots, lines) = _priced(
        cinema, screening, holder, wanted
    );
    hold_id = node_id(hold);
    order_ref = fresh_node_id();
    won = claim(ORDER_KEYS, key_name, order_ref, PROVISIONAL_SECONDS);
    if won != order_ref {
        return _replay(cinema, won, screening_id, wanted);
    }
    if claim(ORDER_HOLDS, hold_id, order_ref, PROVISIONAL_SECONDS) != order_ref {
        release(ORDER_KEYS, key_name, order_ref);
        raise Refused(
            "already_ordered", "These seats are already in an order. Reload the page."
        );
    }
    stamp = now();
    seats = list(hold.seats);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        order = Order(
            tenant_id=node_id(cinema),
            screening_id=screening_id,
            holder=holder,
            hold_id=hold_id,
            idempotency_key=idempotency_key,
            reference=secrets.token_hex(4).upper(),
            request=wanted,
            currency=table.currency,
            price_list_version=price_list.version,
            lines=lines,
            total_cents=sum([l["total_cents"] for l in lines]),
            created_at=stamp.isoformat(),
            pay_by=(
                stamp + timedelta(seconds=seconds_from_env(PAY_ENV, PAY_SECONDS))
            ).isoformat()
        );
        assign_id(order, order_ref);
        screening ++> order;
        attach_to_tenant(order, cinema);
        hold.status = "paying";
        for x in slots {
            if x.hold_id == hold_id and x.state == SeatState.HELD.value {
                x.state = SeatState.PAYMENT_PENDING.value;
            }
        }
        commit_now();
    } except Exception as e {
        # Graph work rolls back with the request; undo the claims, which don't.
        restore(me);
        release(ORDER_HOLDS, hold_id, order_ref);
        release(ORDER_KEYS, key_name, order_ref);
        raise e;
    }
    restore(me);
    # commit_now has committed the order (it raises otherwise), so settle the claims.
    _settle(key_name, hold_id, order_ref, screening_id, holder, seats);
    return {"ok": True, "order": _view(order)};
}

def pending_order(cinema: Tenant, screening: Screening, holder: str) -> Order | None {
    # The holder's latest order for this showtime that is waiting for payment.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = sorted(
            [
                o
                for o in [screening-->[?:Order]]
                if o.holder == holder and o.status == "pending_payment"
            ],
            key=lambda (o: Order) -> str { return o.created_at; }  # jac:ignore[W1037]
        );
    } finally {
        restore(me);
    }
    return found[-1] if found else None;
}

def order_view(order: Order) -> dict[str, any] {  # jac:ignore[W1037]
    return _view(order);
}

def _my_order(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, screening) = showtime_on_sale(slug, screening_id);
    check_holder(holder);
    found = pending_order(cinema, screening, holder);
    if found is None {
        raise Refused("no_order", "You haven't placed an order for this showtime.");
    }
    return {"ok": True, "order": _view(found)};
}

def _quote_hold(
    slug: str,
    screening_id: str,
    holder: str,
    items: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # What the order would cost, priced exactly as place_order would: nothing is saved.
    (cinema, screening) = showtime_on_sale(slug, screening_id);
    check_holder(holder);
    wanted = request_lines(items);
    (_, price_list, table, _, lines) = _priced(cinema, screening, holder, wanted);
    return {
        "ok": True,
        "quote": {
            "currency": table.currency,
            "price_list_version": price_list.version,
            "lines": lines,
            "total_cents": sum([l["total_cents"] for l in lines])
        }
    };
}

def _public_ticket_types(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The tickets a visitor can choose from, in the cinema's order; prices come with
    # quote_hold, since they depend on the seat and the time.
    cinema = open_cinema(slug);
    if cinema is None {
        raise NotFound();
    }
    price_list = cinema_prices(cinema);
    if price_list is None {
        return {"ok": True, "currency": "", "ticket_types": []};
    }
    (parsed, _) = parse_price_list(price_list.data);
    table = parsed as PriceTable;
    return {
        "ok": True,
        "currency": table.currency,
        "ticket_types": [
            {"code": code, "name": name} for (code, name) in table.ticket_types.items()
        ]
    };
}

def:pub quote_hold(
    slug: str,
    screening_id: str,
    holder: str,
    items: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _quote_hold(slug, screening_id, holder, items); }  # jac:ignore[W1037]
    );
}

def:pub public_ticket_types(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _public_ticket_types(slug); });  # jac:ignore[W1037]
}

def:pub place_order(
    slug: str,
    screening_id: str,
    holder: str,
    idempotency_key: str,
    items: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _place_order(  # jac:ignore[W1037]
            slug, screening_id, holder, idempotency_key, items
        ); }
    );
}

def:pub my_order(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _my_order(slug, screening_id, holder); });  # jac:ignore[W1037]
}
