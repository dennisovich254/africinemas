"""Test-only app entry for starting payments (P5.3). Never imported by main.jac.

The production endpoints a priced showtime, a hold, an order and a payment need, plus
probes into the simulated M-Pesa (how many prompts a payment caused, a scripted outcome
per phone number) and the payments stored for a showtime. Run with
AFRICINEMAS_PAYMENTS=simulator.
"""

import from core.tenancy.signup { create_cinema }  # jac:ignore[W2037]
import from core.tenancy.tenant_api { start_shift }  # jac:ignore[W2037]
import from core.tenancy.staff_api {
    invite_staff,  # jac:ignore[W2037]
    accept_invite,  # jac:ignore[W2037]
    change_staff_roles  # jac:ignore[W2037]
}
import from core.audit.audit_api { audit_log }  # jac:ignore[W2037]
import from core.audit.log { Opened, collection_of, _close }
import from core.tenancy.registry { lookup_slug }
import from core.booking.redeem_api {
    redeem_ticket,  # jac:ignore[W2037]
    door_showtimes  # jac:ignore[W2037]
}
import from core.booking.ticket_delivery {
    tickets_by_link,  # jac:ignore[W2037]
    resend_tickets,  # jac:ignore[W2037]
    send_due
}
import from core.notify.mailer { OUTBOX }
import from core.booking.counter_api {
    counter_showtimes,  # jac:ignore[W2037]
    sell_for_cash,  # jac:ignore[W2037]
    sell_with_mpesa  # jac:ignore[W2037]
}
import from core.reporting.report_api { sales_report }  # jac:ignore[W2037]
import from core.booking.customer_tickets {
    save_booking,  # jac:ignore[W2037]
    my_tickets  # jac:ignore[W2037]
}
import from core.catalog.venue_api { create_venue, create_auditorium }  # jac:ignore[W2037]
import from core.catalog.layout_api { save_layout, publish_layout }  # jac:ignore[W2037]
import from core.catalog.movie_api { create_movie }  # jac:ignore[W2037]
import from core.catalog.screening_api {
    create_screening,  # jac:ignore[W2037]
    schedule_screening,  # jac:ignore[W2037]
    publish_screening  # jac:ignore[W2037]
}
import from core.catalog.pricing_api { save_price_list }  # jac:ignore[W2037]
import from core.catalog.storefront_api { public_seat_availability }  # jac:ignore[W2037]
import from core.booking.hold_api { hold_seats }  # jac:ignore[W2037]
import from core.booking.order_api { place_order, my_order }  # jac:ignore[W2037]
import from core.payments.payment_api { start_payment }  # jac:ignore[W2037]
import from core.payments.settlement {
    my_payment,  # jac:ignore[W2037]
    mpesa_callback,  # jac:ignore[W2037]
    process_inbox,  # jac:ignore[W2037]
    tenant_by_id
}
import from core.payments.resolver { resolve, end_my_order }  # jac:ignore[W2037]
import from core.payments.ledger { LedgerEntry }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id, act_as, restore, commit_now }
import from core.tenancy.models { Tenant }
import from core.catalog.venues { find_screening, slots_of }
import from core.catalog.models { Screening }
import from core.booking.models { Order, Ticket }
import from core.payments.models { PaymentIntent, RefundTask }
import from core.payments.choice { payment_provider }
import from core.payments.simulator { SimulatedProvider }
import from core.claims { claim, holder }
import from core.booking.ticket_codes { REFS, reserve_reference }
import from datetime { datetime, timedelta }
import from core.clock { freeze, reset }

def _simulator -> SimulatedProvider {
    made = payment_provider();
    assert isinstance(made, SimulatedProvider);
    return made as SimulatedProvider;
}

def:pub pay_push_count(reference: str) -> int {
    return _simulator().push_count(reference);
}

def:pub pay_script(phone: str, outcome: str) -> bool {
    _simulator().outcomes[phone] = outcome;
    return True;
}

def:pub pay_stored(slug: str, screening_id: str) -> list[list[str]] {
    # Every payment stored for the showtime: [reference, state], oldest first.
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: list[PaymentIntent] = [];
        for o in [screening-->[?:Order]] {
            for p in [o-->[?:PaymentIntent]] {
                found.append(p);
            }
        }
    } finally {
        restore(me);
    }
    ordered = sorted(
        found,
        key=lambda (p: PaymentIntent) -> str { return p.created_at; }  # jac:ignore[W1037]
    );
    return [[p.reference, p.state] for p in ordered];
}

def _showtime(slug: str, screening_id: str) -> tuple[Tenant, Screening] {
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    return (cinema, screening);
}

def _intent(slug: str, screening_id: str, reference: str) -> PaymentIntent {
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: list[PaymentIntent] = [];
        for o in [screening-->[?:Order]] {
            for p in [o-->[?:PaymentIntent]] {
                if p.reference == reference {
                    found.append(p);
                }
            }
        }
    } finally {
        restore(me);
    }
    assert found , reference;
    return found[0];
}

def _body(
    checkout: str, code: int, receipt: str, cents: int, phone: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # Safaricom's STK callback body (Daraja's format).
    callback: dict[str, any] = {  # jac:ignore[W1037]
        "MerchantRequestID": "sim-merchant",
        "CheckoutRequestID": checkout,
        "ResultCode": code,
        "ResultDesc": "simulated"
    };
    if code == 0 {
        callback["CallbackMetadata"] = {
            "Item": [
                {"Name": "Amount", "Value": cents / 100},
                {"Name": "MpesaReceiptNumber", "Value": receipt},
                {"Name": "TransactionDate", "Value": 20261006120000},
                {"Name": "PhoneNumber", "Value": int(phone)}
            ]
        };
    }
    return {"Body": {"stkCallback": callback}};
}

def:pub pay_callback(slug: str, screening_id: str, reference: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The callback Safaricom would send for this payment now: {token, body} (body None
    # while M-Pesa has nothing to say).
    intent = _intent(slug, screening_id, reference);
    said = _simulator().callback(intent.checkout_request_id);
    body = _body(
        intent.checkout_request_id,
        said.result_code,
        said.receipt,
        said.amount_cents,
        said.phone or intent.phone
    )
        if said is not None
        else None;
    return {"token": intent.callback_token, "body": body};
}

def:pub pay_forged(
    slug: str, screening_id: str, reference: str, code: int, cents: int, receipt: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # A callback that says whatever the test wants: {token, body}.
    intent = _intent(slug, screening_id, reference);
    return {
        "token": intent.callback_token,
        "body": _body(intent.checkout_request_id, code, receipt, cents, intent.phone)
    };
}

def:pub pay_late(slug: str, screening_id: str, reference: str) -> bool {
    _simulator().pay_late(_intent(slug, screening_id, reference).checkout_request_id);
    return True;
}

def:pub pay_resolve -> dict[str, int] {
    return resolve();
}

def:pub pay_process -> int {
    return process_inbox();
}

def:pub pay_expire_order(slug: str, screening_id: str, reference: str) -> bool {
    # Stands in for plan 5.5: the order stops waiting for payment.
    (cinema, screening) = _showtime(slug, screening_id);
    intent = _intent(slug, screening_id, reference);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        order: any = jobj(intent.order_id);  # jac:ignore[W1037]
        (order as Order).status = "expired";
        commit_now();
    } finally {
        restore(me);
    }
    return True;
}

def:pub pay_overview(slug: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # What is stored: payments [reference, state, attention], orders' statuses,
    # tickets, open refund tasks, and the seats' stored states.
    (cinema, screening) = _showtime(slug, screening_id);
    seats = slots_of(cinema, screening);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        payments: list[list[str]] = [];
        orders: list[str] = [];
        tickets: list[str] = [];
        refunds: list[str] = [];
        ledger: list[list[any]] = [];  # jac:ignore[W1037]
        balances: list[list[any]] = [];  # jac:ignore[W1037]
        for o in [screening-->[?:Order]] {
            orders.append(o.status);
            entries = [o-->[?:LedgerEntry]];
            for e in entries {
                ledger.append([e.kind, e.amount_cents]);
            }
            balances.append(
                [o.status, o.total_cents, sum([e.amount_cents for e in entries])]
            );
            for t in [o-->[?:Ticket]] {
                tickets.append(t.seat_label);
            }
            for p in [o-->[?:PaymentIntent]] {
                payments.append([p.reference, p.state, p.attention_reason]);
                for r in [p-->[?:RefundTask]] {
                    refunds.append(r.reason);
                }
            }
        }
        states = {x.label: x.state for x in seats};
    } finally {
        restore(me);
    }
    return {
        "payments": sorted(payments),
        "orders": sorted(orders),
        "tickets": sorted(tickets),
        "refunds": sorted(refunds),
        "ledger": sorted(ledger),
        "balances": sorted(balances),
        "seats": states
    };
}

def:pub pay_ticket_codes(slug: str, screening_id: str) -> list[dict[str, str]] {
    # Each stored ticket of the showtime: its seat, reference, QR payload, ids, and who
    # holds its reference's claim (P6.1).
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: list[dict[str, str]] = [];
        for o in [screening-->[?:Order]] {
            for t in [o-->[?:Ticket]] {
                found.append(
                    {
                        "seat_label": t.seat_label,
                        "reference": t.reference,
                        "qr": t.qr,
                        "ticket_id": node_id(t),
                        "tenant_id": t.tenant_id
                    }
                );
            }
        }
    } finally {
        restore(me);
    }
    for f in found {
        f["claimed_by"] = holder(REFS, f["reference"]) or "";
    }
    return sorted(
        found, key=lambda (f: dict[str, str]) -> str { return f["seat_label"]; }
    );
}

def:pub pay_reserve_collision(taken: str, fresh: str) -> list[str] {
    # Someone holds `taken`; reserving draws it first, then `fresh`. Returns the
    # reference reserved and who holds each (P6.1).
    claim(REFS, taken, "someone-else");
    drawn = iter([taken, fresh]);
    got = reserve_reference("me", 60, lambda -> str { return next(drawn); });
    return [got, holder(REFS, taken) or "", holder(REFS, fresh) or ""];
}

def:pub rd_freeze(slug: str, screening_id: str, minutes: int) -> str {
    # Freezes the clock `minutes` after the showtime starts (negative: before it), for
    # the door's time window (P6.2). Needs AFRICINEMAS_CLOCK_CONTROL=1.
    (_, screening) = _showtime(slug, screening_id);
    at = datetime.fromisoformat(screening.starts_at) + timedelta(minutes=minutes);
    freeze(at);
    return at.isoformat();
}

def:pub rd_unfreeze -> bool {
    reset();
    return True;
}

def _ticket_by_reference(reference: str) -> tuple[Tenant, Ticket] {
    owner = holder(REFS, reference);
    assert owner is not None , reference;
    (tenant_id, ticket_id) = owner.split("|");
    cinema = tenant_by_id(tenant_id);
    assert cinema is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(ticket_id);  # jac:ignore[W1037]
    } finally {
        restore(me);
    }
    assert isinstance(found, Ticket);
    return (cinema, found as Ticket);
}

def:pub rd_ticket(reference: str) -> dict[str, str] {
    # A ticket's stored status and who used it when (P6.2).
    (_, t) = _ticket_by_reference(reference);
    return {"status": t.status, "used_at": t.used_at, "used_by": t.used_by};
}

def:pub rd_set_status(reference: str, status: str) -> bool {
    # Stands in for voiding and refunds, which come later.
    (cinema, t) = _ticket_by_reference(reference);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        t.status = status;
        commit_now();
    } finally {
        restore(me);
    }
    return True;
}

def:pub rd_foreign_reference(reference: str) -> bool {
    # A reference claimed for another cinema's ticket.
    return claim(REFS, reference, "another-tenant-id|another-ticket-id") != "";
}

def:pub tm_send_mail -> int {
    # Runs the ticket mail job once (P6.3); returns how many emails it sent.
    return send_due();
}

def:pub tm_outbox -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The development outbox: every email "sent", oldest first.
    return [
        {"to": m.to, "subject": m.subject, "text": m.text, "images": len(m.images)}
        for m in OUTBOX
    ];
}

def:pub tm_clear_outbox -> bool {
    OUTBOX.clear();
    return True;
}

def:pub bo_ledger(slug: str, screening_id: str) -> list[list[any]] {  # jac:ignore[W1037]
    # The showtime's ledger entries: [kind, amount, method, recorded_by] (P6.5).
    (cinema, screening) = _showtime(slug, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            [e.kind, e.amount_cents, e.method, e.recorded_by]
            for o in [screening-->[?:Order]] for e in [o-->[?:LedgerEntry]]
        ];
    } finally {
        restore(me);
    }
    return found;
}

def:priv audit_refinish(slug: str, event_id: str) -> bool {
    # Tries to finish the cinema's audit event `event_id` again, as "ok" (P7.2): only
    # a pending event is ever finished, so a finished one must not change.
    cinema = lookup_slug(slug);
    _close(Opened(collection=collection_of(str(cinema)), event_id=event_id), "ok", "x");
    return True;
}
