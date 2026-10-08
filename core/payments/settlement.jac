"""Callbacks and settling payments (P5.4, architecture §33-§35; ADR-0018).

Safaricom's callback is never proof of payment (§33):

1. mpesa_callback (POST /hooks/mpesa/{token}, public) only files a receipt: it checks
   the token (made per payment, P5.3), parses the body and keeps it in INBOX (the
   claims table; a duplicate callback is ignored), then answers at once. It writes
   nothing to the graph.
2. settle() asks M-Pesa directly (the status query) what happened. Paid: in one
   commit the payment is SUCCESS with its receipt, the order is confirmed, its seats
   SOLD and one ticket issued per seat. Failed or cancelled: the payment says so and
   the order is free for another attempt. Still waiting: nothing changes.
3. One ticket set, whatever arrives (§35): a per-order gate (FINALIZE, an atomic claim)
   lets one settle finalize; M-Pesa receipts are claimed once (RECEIPTS), so one
   receipt can't pay twice. Settling a final payment again changes nothing.
4. What can't settle cleanly needs attention, with a refund task (money was taken but
   bought nothing): a paid amount that differs, a success after the order stopped
   waiting for payment, a receipt already used, or a second payment for an order
   already paid.

The scheduled job (process_callbacks) settles every filed receipt; my_payment settles
the visitor's own payment when a receipt for it is waiting, so the page updates without
waiting for the job.
"""

import os;
import re;
import json;
import from http { HTTPMethod }
import from core.clock { now }
import from core.claims { claim, release, renew, claims_in, holder as claim_holder }
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id,
    system_root_id
}
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Screening }
import from core.booking.models { Order, Ticket }
import from core.booking.confirm { Takings, confirm_order }
import from core.booking.ticket_delivery { link_path }
import from core.notify.addresses { masked_email }
import from core.booking.hold_api { showtime_on_sale, check_holder }
import from core.payments.models { PaymentIntent, RefundTask }
import from core.payments.state { PaymentState, transition, is_final }
import from core.payments.provider { StkStatus, PaymentProvider }
import from core.payments.choice { payment_provider, ProviderNotConfigured }
import from core.payments.daraja { parse_callback }
import from core.payments.ledger { record_entry }
import from core.payments.payment_api {
    CALLBACK_TOKENS,
    ORDER_PAYMENT,
    payment_view,
    stored_intent,
    latest_intent,
    ensure_pushed
}

glob INBOX: str = "mpesa-inbox",
     FINALIZE: str = "order-paid",
     RECEIPTS: str = "mpesa-receipt",
     PROVISIONAL_SECONDS: int = 60,
     TOKEN_PATTERN: str = "[A-Za-z0-9_-]{16,64}",
     SETTLE_SECONDS: int = int(os.environ.get("AFRICINEMAS_SETTLE_SECONDS", "5")),
     ACK: dict[str, any] = {"ResultCode": 0, "ResultDesc": "Accepted"};  # jac:ignore[W1037]

def _intent_for(token: str) -> tuple[Tenant, PaymentIntent] | None {
    # The payment a callback token names, if any.
    named = claim_holder(CALLBACK_TOKENS, token);
    if named is None or "|" not in named {
        return None;
    }
    (tenant_id, ref) = named.split("|", 1);
    cinema = tenant_by_id(tenant_id);
    if cinema is None {
        return None;
    }
    intent = stored_intent(cinema, ref);
    return (cinema, intent) if intent is not None else None;
}

def _filed(token: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    # The receipt filed for a payment's callback token, if any.
    kept = claim_holder(INBOX, token);
    if kept is None {
        return None;
    }
    try {
        found = json.loads(kept);
    } except ValueError {
        return None;
    }
    return found if isinstance(found, dict) else None;
}

def file_callback(token: str, body: any) -> bool {  # jac:ignore[W1037]
    # Files Safaricom's callback for the payment `token` names; False (and nothing kept)
    # for an unknown token or a body that isn't an STK callback. The first callback
    # for a token is kept; repeats change nothing.
    if not isinstance(token, str) or not re.fullmatch(TOKEN_PATTERN, token) {
        return False;
    }
    if claim_holder(CALLBACK_TOKENS, token) is None {
        return False;
    }
    status = parse_callback(body);
    if status is None {
        return False;
    }
    # Only what settling needs: no raw payload, and no phone beyond the payment's own.
    kept = {
        "checkout_request_id": status.checkout_request_id,
        "result_code": status.result_code,
        "receipt": status.receipt,
        "amount_cents": status.amount_cents
    };
    claim(INBOX, token, json.dumps(kept));
    return True;
}

@restspec(method=HTTPMethod.POST, path="/hooks/mpesa/{token}")
def:pub mpesa_callback(token: str, Body: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # Safaricom's STK result. Always acknowledged (Safaricom only needs to know it
    # arrived); what it says is checked with M-Pesa before anything changes. Body is
    # required, not defaulted: an omitted defaulted parameter arrives as a string
    # (JI-025).
    file_callback(token, {"Body": Body});
    return ACK;
}

def _attention(
    cinema: Tenant,
    intent: PaymentIntent,
    reason: str,
    filed: dict[str, any] | None,  # jac:ignore[W1037]
    refund: bool
) {
    # The payment can't settle cleanly: it needs attention, and money that bought
    # nothing gets a refund task.
    receipt = str(filed.get("receipt", "")) if filed is not None else "";
    paid = int(filed.get("amount_cents", 0) or 0) if filed is not None else 0;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        intent.state = transition(
            PaymentState(intent.state), PaymentState.NEEDS_ATTENTION
        ).value;
        intent.attention_reason = reason;
        intent.receipt = receipt;
        intent.paid_amount_cents = paid;
        intent.updated_at = now().isoformat();
        if refund {
            owed = paid or intent.amount_cents;
            order = order_of(cinema, intent);
            if order is not None {
                record_entry(
                    cinema,
                    order as Order,
                    node_id(intent),
                    "payment",
                    owed,
                    receipt,
                    reason
                );
                record_entry(
                    cinema,
                    order as Order,
                    node_id(intent),
                    "refund_due",
                    0 - owed,
                    receipt,
                    reason
                );
            }
            task = RefundTask(
                tenant_id=node_id(cinema),
                intent_id=node_id(intent),
                order_id=intent.order_id,
                receipt=receipt,
                amount_cents=paid or intent.amount_cents,
                reason=reason,
                created_at=now().isoformat()
            );
            intent ++> task;
            attach_to_tenant(task, cinema);
        }
        commit_now();
    } finally {
        restore(me);
    }
}

def _ended(cinema: Tenant, intent: PaymentIntent, state: PaymentState, text: str) {
    # M-Pesa says it failed or was cancelled: record it and free the order.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        intent.state = transition(PaymentState(intent.state), state).value;
        intent.result_text = text;
        intent.updated_at = now().isoformat();
        commit_now();
    } finally {
        restore(me);
    }
    release(ORDER_PAYMENT, intent.order_id, node_id(intent));
}

def _finalize(
    cinema: Tenant, intent: PaymentIntent, order: Order, receipt: str, paid: int
) {
    # Paid and confirmed: the payment, with the order, seats and tickets, in one commit.
    stamp = now().isoformat();

    def mark_paid {
        intent.state = transition(
            PaymentState(intent.state), PaymentState.SUCCESS
        ).value;
        intent.receipt = receipt;
        intent.paid_amount_cents = paid;
        intent.updated_at = stamp;
    }
    confirm_order(
        cinema,
        order,
        Takings(
            payment_id=node_id(intent),
            amount_cents=paid,
            receipt=receipt,
            note="M-Pesa",
            method="mpesa",
            recorded_by=intent.sold_by
        ),
        mark_paid
    );
}

def order_of(cinema: Tenant, intent: PaymentIntent) -> Order | None {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(intent.order_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as Order if isinstance(found, Order) else None;
}

def settle(cinema: Tenant, intent: PaymentIntent, provider: PaymentProvider) -> str {
    # Settles one payment from M-Pesa's own answer; returns its state afterwards.
    current = PaymentState(intent.state);
    if current in [PaymentState.SUCCESS, PaymentState.NEEDS_ATTENTION] {
        return intent.state;
    }
    if not intent.checkout_request_id {
        # The push was never accepted: nothing at M-Pesa to ask about (plan 5.5).
        return intent.state;
    }
    filed = _filed(intent.callback_token);
    asked = provider.query(intent.checkout_request_id);
    if asked.state == PaymentState.STK_REQUESTED {
        return intent.state;
    }
    if asked.state == PaymentState.UNKNOWN {
        if current == PaymentState.STK_REQUESTED {
            me = node_id(root);
            act_as(cinema.principal_root_id);
            try {
                intent.state = transition(current, PaymentState.UNKNOWN).value;
                intent.updated_at = now().isoformat();
                commit_now();
            } finally {
                restore(me);
            }
        }
        return intent.state;
    }
    if asked.state in [PaymentState.FAILED, PaymentState.CANCELLED] {
        if not is_final(current) {
            _ended(cinema, intent, asked.state, asked.result_text);
        }
        return intent.state;
    }
    # M-Pesa confirms the payment.
    ref = node_id(intent);
    receipt = str(filed.get("receipt", "")) if filed is not None else "";
    paid = int(filed.get("amount_cents", 0) or 0) if filed is not None else 0;
    order = order_of(cinema, intent);
    if current in [PaymentState.FAILED, PaymentState.CANCELLED]
        or order is None
        or order.status != "pending_payment" {
        _attention(cinema, intent, "late_success", filed, True);
        return intent.state;
    }
    if filed is not None and paid != intent.amount_cents {
        _attention(cinema, intent, "amount_mismatch", filed, True);
        return intent.state;
    }
    if receipt and claim(RECEIPTS, receipt, ref) != ref {
        _attention(cinema, intent, "receipt_reused", filed, True);
        return intent.state;
    }
    # One finalize per order: the gate's owner is this intent and this attempt.
    mine = f"{ref}|{fresh_node_id()}";
    holder = claim(FINALIZE, intent.order_id, mine, PROVISIONAL_SECONDS);
    if holder != mine {
        if not holder.startswith(f"{ref}|") {
            _attention(cinema, intent, "order_already_paid", filed, True);
        }
        # Otherwise another settle of this payment is finalizing it right now.
        return intent.state;
    }
    try {
        _finalize(cinema, intent, order as Order, receipt, paid or intent.amount_cents);
    } except Exception as e {
        release(FINALIZE, intent.order_id, mine);
        raise e;
    }
    renew(FINALIZE, intent.order_id, mine, 0);
    return intent.state;
}

def process_inbox -> int {
    # Settles every payment with a filed callback; a final one leaves the inbox.
    # Returns how many payments it settled to a final state.
    settled = 0;
    for (token, kept, _) in claims_in(INBOX) {
        found = _intent_for(token);
        if found is None {
            continue;
        }
        (cinema, intent) = found;
        try {
            provider = payment_provider();
        } except ProviderNotConfigured {
            return settled;
        }
        state = settle(cinema, intent, provider);
        if is_final(PaymentState(state)) {
            # Settled for good: the receipt leaves the inbox (a later duplicate is filed
            # again and changes nothing).
            release(INBOX, token, kept);
            settled += 1;
        }
    }
    return settled;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=SETTLE_SECONDS)
def settle_callbacks {
    # Runs as Jac's system identity on every server copy; settling twice is harmless.
    process_inbox();
}

def _latest_order(cinema: Tenant, screening: Screening, holder: str) -> Order | None {
    # The holder's latest order for this showtime, whatever its status.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = sorted(
            [
                o
                for o in [screening-->[?:Order]]
                if o.holder == holder
            ],
            key=lambda (o: Order) -> str { return o.created_at; }  # jac:ignore[W1037]
        );
    } finally {
        restore(me);
    }
    return found[-1] if found else None;
}

def _tickets(cinema: Tenant, order: Order) -> list[dict[str, str]] {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            {
                "seat_label": t.seat_label,
                "ticket_name": t.ticket_name,
                "reference": t.reference,
                "qr": t.qr,
                "status": t.status
            } for t in [order-->[?:Ticket]]
        ];
    } finally {
        restore(me);
    }
    return sorted(
        found, key=lambda (t: dict[str, str]) -> str { return t["seat_label"]; }
    );  # jac:ignore[W1037]
}

def _my_payment(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The latest payment for the holder's order, settled first when M-Pesa has
    # answered; a paid order's tickets come with it.
    (cinema, screening) = showtime_on_sale(slug, screening_id);
    check_holder(holder);
    order = _latest_order(cinema, screening, holder);
    intent = latest_intent(cinema, order) if order is not None else None;
    if order is None or intent is None {
        raise Refused("no_payment", "You haven't started paying for this order.");
    }
    provider: PaymentProvider | None = None;
    try {
        provider = payment_provider();
    } except ProviderNotConfigured {
        provider = None;
    }
    if provider is not None {
        if intent.state == PaymentState.CREATED.value and not intent.push_uncertain {
            ensure_pushed(cinema, intent, provider);
        } elif _filed(intent.callback_token) is not None {
            settle(cinema, intent, provider);
        }
    }
    view = payment_view(intent);
    paid = intent.state == "success";
    view["tickets"] = _tickets(cinema, order) if paid else [];
    # Where the tickets live, and where they were emailed (P6.3).
    view["link"] = link_path(cinema, order) if paid else "";
    view["email"] = masked_email(order.email) if paid and order.email else "";
    return {"ok": True, "payment": view};
}

def:pub my_payment(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _my_payment(slug, screening_id, holder); });  # jac:ignore[W1037]
}
