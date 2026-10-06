"""Test-only app entry for starting payments (P5.3). Never imported by main.jac.

The production endpoints a priced showtime, a hold, an order and a payment need, plus
probes into the simulated M-Pesa (how many prompts a payment caused, a scripted outcome
per phone number) and the payments stored for a showtime. Run with
AFRICINEMAS_PAYMENTS=simulator.
"""

import from core.tenancy.signup { create_cinema }  # jac:ignore[W2037]
import from core.tenancy.tenant_api { start_shift }  # jac:ignore[W2037]
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
import from core.payments.settlement { my_payment, mpesa_callback, process_inbox }  # jac:ignore[W2037]
import from core.payments.resolver { resolve }
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
