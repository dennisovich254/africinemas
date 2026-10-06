"""Resolving stuck payments and releasing unpaid orders (P5.5, architecture §24, §124;
ADR-0019).

A scheduled job (resolve_payments) makes sure nothing waits forever:

1. Open payments (OPEN_PAYMENTS, listed when a payment starts). One older than
   STUCK_SECONDS is settled from M-Pesa's own answer (settlement.settle, ADR-0018),
   with or without a callback: paid makes tickets, failed or cancelled frees the order.
   One M-Pesa still calls "processing" after TIMEOUT_SECONDS is TIMEOUT, and is asked
   again on later runs (a late payment can still settle). A payment whose push a
   crashed request committed but never sent is sent now, if its order can still be
   paid. A final payment leaves the list.
2. Open orders (OPEN_ORDERS, listed when an order is placed). One past its pay_by is
   given a last chance: its open payments are settled first, so a payment that went
   through wins. Otherwise the order expires: its payments that never settled fail,
   its hold expires, its seats are available again and their claims, the hold's order
   claim and the order's payment claim are released, so others can book the seats
   (PAYMENT_PENDING never sticks).

Every step is safe to repeat, so the job runs on every server copy (ADR-0005).
"""

import os;
import from datetime { datetime }
import from core.clock { now }
import from core.claims { claims_in, release, holder as claim_holder }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore, commit_now }
import from core.catalog.models { SeatSlot }
import from core.catalog.venues { find_screening, slots_of }
import from core.booking.models { Order, SeatHold }
import from core.booking.availability { SeatState }
import from core.booking.hold_api { seat_namespace }
import from core.booking.order_api { OPEN_ORDERS, ORDER_HOLDS }
import from core.payments.models { PaymentIntent }
import from core.payments.state { PaymentState, transition, is_final }
import from core.payments.provider { PaymentProvider }
import from core.payments.choice { payment_provider, ProviderNotConfigured }
import from core.payments.payment_api {
    OPEN_PAYMENTS,
    ORDER_PAYMENT,
    stored_intent,
    ensure_pushed
}
import from core.payments.settlement { settle, tenant_by_id, order_of }

glob RESOLVE_SECONDS: int = int(
         os.environ.get("AFRICINEMAS_RESOLVE_SECONDS", "30")
     ),
     DANGLING_SECONDS: int = 300;

def _seconds(env: str, fallback: int) -> int {
    # A threshold from the environment, read each run (tests shorten them).
    try {
        return int(os.environ.get(env, str(fallback)));
    } except ValueError {
        return fallback;
    }
}

def _age(stamp: str) -> float {
    if not stamp {
        return 0.0;
    }
    return (now() - datetime.fromisoformat(stamp)).total_seconds();
}

def _payable(order: Order | None) -> bool {
    return order is not None
        and order.status == "pending_payment"
        and bool(order.pay_by)
        and datetime.fromisoformat(order.pay_by) > now();
}

def _timed_out(cinema: Tenant, intent: PaymentIntent) {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        intent.state = transition(
            PaymentState(intent.state), PaymentState.TIMEOUT
        ).value;
        intent.updated_at = now().isoformat();
        commit_now();
    } finally {
        restore(me);
    }
}

def resolve_payment(
    cinema: Tenant, intent: PaymentIntent, provider: PaymentProvider
) -> str {
    # One open payment's next step; returns its state afterwards.
    if is_final(PaymentState(intent.state)) {
        return intent.state;
    }
    if _age(intent.created_at) < _seconds("AFRICINEMAS_STUCK_SECONDS", 60) {
        return intent.state;
    }
    if intent.state == PaymentState.CREATED.value {
        # The push was never answered (uncertain) or never sent (a crashed request).
        if not intent.push_uncertain and _payable(order_of(cinema, intent)) {
            ensure_pushed(cinema, intent, provider);
        }
        return intent.state;
    }
    state = settle(cinema, intent, provider);
    if state == PaymentState.STK_REQUESTED.value
        and _age(intent.created_at) >= _seconds("AFRICINEMAS_TIMEOUT_SECONDS", 180) {
        _timed_out(cinema, intent);
    }
    return intent.state;
}

def _intents_of(cinema: Tenant, order: Order) -> list[PaymentIntent] {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [order-->[?:PaymentIntent]];
    } finally {
        restore(me);
    }
    return found;
}

def expire_order(cinema: Tenant, order: Order) {
    # The order's time to pay is up: it expires, its unsettled payments fail, and its
    # seats go back on sale.
    screening = find_screening(cinema, order.screening_id);
    slots: list[SeatSlot] = slots_of(cinema, screening)
        if screening is not None
        else [];
    intents = _intents_of(cinema, order);
    freed: list[str] = [];
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        order.status = "expired";
        hold: any = jobj(order.hold_id);  # jac:ignore[W1037]
        if isinstance(hold, SeatHold) {
            (hold as SeatHold).status = "expired";
        }
        for x in slots {
            if x.hold_id == order.hold_id
                and x.state == SeatState.PAYMENT_PENDING.value {
                x.state = SeatState.AVAILABLE.value;
                x.hold_expires_at = "";
                x.hold_id = "";
                freed.append(x.label);
            }
        }
        for p in intents {
            if not is_final(PaymentState(p.state)) {
                p.state = transition(PaymentState(p.state), PaymentState.FAILED).value;
                p.result_text = "The time to pay ran out.";
                p.updated_at = now().isoformat();
            }
        }
        commit_now();
    } finally {
        restore(me);
    }
    order_id = node_id(order);
    space = seat_namespace(order.screening_id);
    for label in freed {
        release(space, label, order.holder);
    }
    release(ORDER_HOLDS, order.hold_id, order_id);
    active = claim_holder(ORDER_PAYMENT, order_id);
    if active is not None {
        release(ORDER_PAYMENT, order_id, active);
    }
}

def _order(cinema: Tenant, order_id: str) -> Order | None {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(order_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as Order if isinstance(found, Order) else None;
}

def resolve -> dict[str, int] {
    # One pass: open payments, then open orders past their time to pay.
    try {
        provider = payment_provider();
    } except ProviderNotConfigured {
        return {"payments": 0, "expired": 0};
    }
    settled = 0;
    for (ref, tenant_id, age) in claims_in(OPEN_PAYMENTS) {
        cinema = tenant_by_id(tenant_id);
        intent = stored_intent(cinema, ref) if cinema is not None else None;
        if cinema is None or intent is None {
            if age >= DANGLING_SECONDS {
                release(OPEN_PAYMENTS, ref, tenant_id);
            }
            continue;
        }
        state = resolve_payment(cinema as Tenant, intent as PaymentIntent, provider);
        if is_final(PaymentState(state)) {
            release(OPEN_PAYMENTS, ref, tenant_id);
            settled += 1;
        }
    }
    expired = 0;
    for (order_id, tenant_id, age) in claims_in(OPEN_ORDERS) {
        cinema = tenant_by_id(tenant_id);
        order = _order(cinema, order_id) if cinema is not None else None;
        if cinema is None or order is None {
            if age >= DANGLING_SECONDS {
                release(OPEN_ORDERS, order_id, tenant_id);
            }
            continue;
        }
        if order.status != "pending_payment" {
            release(OPEN_ORDERS, order_id, tenant_id);
            continue;
        }
        if _payable(order) {
            continue;
        }
        # Last chance: a payment that went through wins over expiry.
        for p in _intents_of(cinema as Tenant, order as Order) {
            if not is_final(PaymentState(p.state)) and p.checkout_request_id {
                settle(cinema as Tenant, p, provider);
            }
        }
        # Read it again: settling may have confirmed it.
        fresh = _order(cinema as Tenant, order_id);
        if fresh is not None and fresh.status == "pending_payment" {
            expire_order(cinema as Tenant, fresh as Order);
            expired += 1;
        }
        release(OPEN_ORDERS, order_id, tenant_id);
    }
    return {"payments": settled, "expired": expired};
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=RESOLVE_SECONDS)
def resolve_payments {
    # Runs as Jac's system identity on every server copy; every step is repeatable.
    resolve();
}
