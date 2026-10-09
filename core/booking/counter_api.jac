"""Selling at the box office (P6.5; ADR-0025): a walk-in customer pays in cash or with
M-Pesa at the counter.

The agent books for the customer through the storefront's own endpoints (hold_seats,
place_order) under a counter holder id, one per sale, so seats, prices and holds work
exactly as online. Only the money differs:

- sell_for_cash confirms the order at once (confirm.confirm_order: seats sold, tickets
  issued) with a ledger entry of the whole amount, method "cash", recorded_by the agent.
  It takes the same per-order gate as M-Pesa settlement (FINALIZE), so an order is
  paid once, and it refuses while an M-Pesa prompt for the order is still open.
- sell_with_mpesa sends the customer the M-Pesa prompt (payment_api.counter_payment);
  an email address is optional at the counter. The page then follows the payment with
  my_payment, as the storefront does.
- counter_showtimes lists the showtimes on sale at the venues where the caller may sell.

All three need a login, an open shift and bookings.create at the showtime's venue
(box office agents and managers, general managers, admins, owners): an agent limited to
another venue, or an usher, is refused.
"""

import from datetime { datetime }
import from core.clock { now }
import from core.claims { claim, release, renew, holder as claim_holder }
import from core.authz.policy {
    Resource,
    Forbidden,
    ROLE_PERMISSIONS,
    authorize,
    require
}
import from core.authz.context { NotFound, TenantScope, on_shift }
import from core.tenancy.principal { node_id, fresh_node_id }
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Screening, PUBLISHED }
import from core.catalog.venues {
    find_screening,
    find_movie,
    find_venue,
    find_auditorium,
    screenings_of_cinema,
    slots_of
}
import from core.catalog.storefront_api { cinema_timezone }
import from core.booking.models { Order }
import from core.booking.availability { SeatState }
import from core.booking.hold_api { check_holder }
import from core.booking.order_api { pending_order }
import from core.booking.confirm { Takings, confirm_order }
import from core.booking.ticket_codes { ticket_key, TicketKeyMissing }
import from core.booking.ticket_delivery { booking_view, link_path }
import from core.notify.addresses { email_problem, clean_email, masked_email }
import from core.payments.payment_api { ORDER_PAYMENT, stored_intent, counter_payment }
import from core.payments.settlement { FINALIZE, PROVISIONAL_SECONDS }
import from core.payments.state { PaymentState, is_final }
import from core.audit.log { audited }

glob SELL: str = "bookings.create",
     SHOWTIMES_MAX: int = 30;

def _may_sell_somewhere(scope: TenantScope) {
    if not any([SELL in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments]) {
        raise Forbidden(SELL);
    }
}

def _showtime(tenant: str, screening_id: str) -> tuple[TenantScope, Screening] {
    # The caller's cinema and the showtime, once they may sell at its venue.
    scope = on_shift(tenant);
    screening = find_screening(scope.tenant, screening_id);
    if screening is None {
        raise NotFound();
    }
    require(
        scope.ctx,
        SELL,
        Resource(tenant_id=scope.ctx.tenant_id, venue_id=screening.venue_id)
    );
    return (scope, screening);
}

def _counter_showtimes(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    _may_sell_somewhere(scope);
    at = now();
    shown: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in screenings_of_cinema(scope.tenant) {
        if s.state != PUBLISHED or datetime.fromisoformat(s.starts_at) <= at {
            continue;
        }
        venue_ok = authorize(
            scope.ctx,
            SELL,
            Resource(tenant_id=scope.ctx.tenant_id, venue_id=s.venue_id)
        );
        if not venue_ok {
            continue;
        }
        movie = find_movie(scope.tenant, s.movie_id);
        seats = slots_of(scope.tenant, s);
        venue = find_venue(scope.tenant, s.venue_id);
        screen = find_auditorium(scope.tenant, s.auditorium_id);
        shown.append(
            {
                "screening_id": node_id(s),
                "movie_title": movie.title if movie is not None else "",
                "starts_at": s.starts_at,
                "venue": venue.name if venue is not None else "",
                "screen": screen.name if screen is not None else "",
                # For the box office's poster cards (P7.4, showtime_art) and seats left.
                "has_poster": movie is not None and movie.poster_key != "",
                "seats_on_sale": len(
                    [
                        x
                        for x in seats
                        if x.state != SeatState.NOT_FOR_SALE.value
                    ]
                ),
                "seats_sold": len(
                    [
                        x
                        for x in seats
                        if x.state == SeatState.SOLD.value
                    ]
                )
            }
        );
    }
    ordered = sorted(
        shown,
        key=lambda (s: dict[str, any]) -> str { return str(s["starts_at"]); }  # jac:ignore[W1037]
    );
    return {
        "ok": True,
        "slug": scope.tenant.slug,
        "timezone": cinema_timezone(scope.tenant),
        "showtimes": ordered[:SHOWTIMES_MAX]
    };
}

def _order(scope: TenantScope, screening: Screening, holder: str) -> Order {
    check_holder(holder);
    order = pending_order(scope.tenant, screening, holder);
    if order is None {
        raise Refused(
            "no_order", "There's no order waiting for payment for this sale."
        );
    }
    if not order.pay_by or datetime.fromisoformat(order.pay_by) <= now() {
        raise Refused(
            "order_expired",
            "The time to pay for this order is up. Choose the seats again."
        );
    }
    return order;
}

def _sell_for_cash(
    tenant: str, screening_id: str, holder: str, email: str
) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, screening) = _showtime(tenant, screening_id);
    # Tickets are signed (P6.1): without the key none can be issued, so refuse before
    # anything is claimed or changed, as online payments do.
    try {
        ticket_key();
    } except TicketKeyMissing {
        raise Refused(
            "tickets_unavailable",
            "Tickets can't be issued right now (the server has no ticket key). Ask an administrator."
        );
    }
    if email.strip() and email_problem(email) {
        raise Refused("invalid_email", email_problem(email));
    }
    order = _order(scope, screening, holder);
    order_id = node_id(order);
    active = claim_holder(ORDER_PAYMENT, order_id);
    if active is not None {
        intent = stored_intent(scope.tenant, active);
        if intent is not None and not is_final(PaymentState(intent.state)) {
            raise Refused(
                "payment_in_progress",
                "An M-Pesa prompt for this order is still open on the customer's phone."
            );
        }
    }
    member = scope.ctx.member_root_id;
    mine = f"cash:{member}|{fresh_node_id()}";
    if claim(FINALIZE, order_id, mine, PROVISIONAL_SECONDS) != mine {
        raise Refused("already_paid", "This order has been paid.");
    }
    address = clean_email(email) if email.strip() else "";

    def keep_email {
        if address {
            order.email = address;
        }
    }
    try {
        confirm_order(
            scope.tenant,
            order,
            Takings(
                payment_id=f"cash-{fresh_node_id()}",
                amount_cents=order.total_cents,
                receipt=f"CASH-{order.reference}",
                note="Cash at the box office",
                method="cash",
                recorded_by=member
            ),
            keep_email
        );
    } except Exception as e {
        release(FINALIZE, order_id, mine);
        raise e;
    }
    renew(FINALIZE, order_id, mine, 0);
    view = booking_view(scope.tenant, order);
    return {
        "ok": True,
        "payment": {
            "state": "success",
            "amount_cents": order.total_cents,
            "currency": order.currency,
            "reference": order.reference,
            "tickets": view["tickets"],
            "link": link_path(scope.tenant, order),
            "email": masked_email(order.email) if order.email else ""
        }
    };
}

def _sell_with_mpesa(
    tenant: str, screening_id: str, holder: str, phone: str, email: str
) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, _) = _showtime(tenant, screening_id);
    return counter_payment(
        scope.tenant.slug,
        screening_id,
        holder,
        phone,
        email,
        f"counter-{fresh_node_id()}",
        scope.ctx.member_root_id
    );
}

def:priv counter_showtimes(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _counter_showtimes(tenant); });  # jac:ignore[W1037]
}

def _do_sell_for_cash(
    tenant: str, screening_id: str, holder: str, email: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _sell_for_cash(tenant, screening_id, holder, email); }  # jac:ignore[W1037]
    );
}

def _do_sell_with_mpesa(
    tenant: str, screening_id: str, holder: str, phone: str, email: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _sell_with_mpesa(  # jac:ignore[W1037]
            tenant, screening_id, holder, phone, email
        ); }
    );
}

def:priv sell_for_cash(
    tenant: str, screening_id: str, holder: str, email: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "sale.cash",
        "showtime",
        screening_id,
        lambda -> any { return _do_sell_for_cash(tenant, screening_id, holder, email); }  # jac:ignore[W1037]
    );
}

def:priv sell_with_mpesa(
    tenant: str, screening_id: str, holder: str, phone: str, email: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "sale.mpesa_started",
        "showtime",
        screening_id,
        lambda -> any { return _do_sell_with_mpesa(
            tenant, screening_id, holder, phone, email
        ); }  # jac:ignore[W1037]
    );
}
