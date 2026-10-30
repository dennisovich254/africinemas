"""Starting a payment (P5.3, architecture §26, §29; ADR-0017): public endpoints, no login,
listed in tests/isolation/registry.jac.

A visitor whose order waits for payment (P4.5: its seats are already PAYMENT_PENDING)
asks to pay from their M-Pesa number. start_payment records a PaymentIntent and sends
one STK push (the PIN prompt on their phone). my_payment (settlement.jac) says where
it stands.

Exactly one push per intent, however often the request runs:

1. The request only records the intent (state "created") and commits (commit_now,
   JI-038). Nothing is sent inside a unit of work Jac may replay.
2. After the commit, the push goes through a one-shot gate: an atomic claim per intent
   (STK_GATE). Whoever wins it sends; nobody else ever does, on any server.
3. The push's result is kept at once in STK_RESULT, outside the graph transaction, so a
   request replayed before it recorded the result on the intent finishes from it
   without sending again. Any later call for the intent (the same key again, or
   my_payment) completes a push a crashed request left unsent.

The browser sends an idempotency key: the same key again returns the same intent (a
different number under it is refused, "key_reused"). An order has one active intent at a
time (ORDER_PAYMENT); after a failed or cancelled attempt a new one may start. A push
is never retried (ADR-0016): one that got no answer is "uncertain" and waits for
Safaricom's reply or the resolver (plan 5.5).
"""

import os;
import json;
import secrets;
import from datetime { datetime }
import from core.clock { now }
import from core.faults { replay_point }
import from core.claims { claim, release, renew, holder as claim_holder }
import from core.tenancy.models { Tenant }
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
import from core.notify.addresses { email_problem, clean_email }
import from core.booking.models { Order }
import from core.booking.hold_api { showtime_on_sale, check_holder }
import from core.tenancy.open_cinema { require_live }
import from core.booking.order_api { pending_order, check_key }
import from core.payments.models { PaymentIntent }
import from core.payments.state { PaymentState, transition, is_final }
import from core.payments.phone { msisdn, InvalidPhone }
import from core.payments.provider { StkRequest, PaymentProvider }
import from core.payments.choice {
    NotConnected,
    ProviderNotConfigured,
    provider_for,
    shortcode_for,
    version_for_new
}
import from core.payments.daraja { masked }
import from core.catalog.policies { shown_at_checkout }
import from core.notify.offer_consent { sends_offers, record_consent }

glob PAY_KEYS: str = "pay-key",
     ORDER_PAYMENT: str = "order-payment",
     STK_GATE: str = "stk-gate",
     STK_RESULT: str = "stk-result",
     CALLBACK_TOKENS: str = "callback-token",
     # Payments not yet final, for the resolver job (P5.5).
     OPEN_PAYMENTS: str = "open-payment",
     PROVISIONAL_SECONDS: int = 60,
     KEY_SECONDS: int = 24 * 60 * 60,
     CALLBACK_ENV: str = "DARAJA_CALLBACK_BASE",
     NO_CALLBACK: str = "https://callbacks.invalid",
     MESSAGES: dict[str, str] = {
         "created": "Sending the payment request to your phone.",
         "stk_requested": "Check your phone and enter your M-Pesa PIN to pay.",
         "success": "Paid. Thank you.",
         "failed": "The payment didn't go through.",
         "cancelled": "The payment was cancelled on your phone.",
         "timeout": "We're still waiting for M-Pesa to confirm your payment.",
         "unknown": "We're still checking your payment with M-Pesa.",
         "needs_attention": "We're checking your payment. The cinema will be in touch."
     },
     UNCERTAIN: str = "We couldn't confirm the request reached your phone. If an M-Pesa prompt appears, you can pay it; otherwise try again in a few minutes.";

def payment_view(intent: PaymentIntent) -> dict[str, any] {  # jac:ignore[W1037]
    message = UNCERTAIN
        if intent.push_uncertain and intent.state == PaymentState.CREATED.value
        else MESSAGES.get(intent.state, "");
    if intent.state == PaymentState.FAILED.value and intent.result_text {
        message = f"{message} {intent.result_text}";
    }
    return {
        "reference": intent.reference,
        "state": intent.state,
        "amount_cents": intent.amount_cents,
        "currency": intent.currency,
        "phone": masked(intent.phone),
        "message": message,
        "created_at": intent.created_at,
        # A paid order's tickets (my_payment fills them in, P5.4).
        "tickets": [],
        # The ticket link and where the tickets were emailed, once paid (P6.3).
        "link": "",
        "email": "",
        # The paid order's snacks, to collect at the counter (my_payment, P12.8).
        "snacks": [],
        # Their pickup code once paid, {reference, qr} (my_payment, P12.9).
        "pickup": None
    };
}

def stored_intent(cinema: Tenant, ref: str) -> PaymentIntent | None {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(ref);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as PaymentIntent if isinstance(found, PaymentIntent) else None;
}

def callback_url(token: str) -> str {
    # Where Safaricom POSTs the result (the endpoint comes with plan 5.4).
    base = os.environ.get(CALLBACK_ENV, "").strip().rstrip("/") or NO_CALLBACK;
    return f"{base}/hooks/mpesa/{token}";
}

def _result_of(ref: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    kept = claim_holder(STK_RESULT, ref);
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

def _record(cinema: Tenant, intent: PaymentIntent, result: dict[str, any]) {  # jac:ignore[W1037]
    # Writes the push's outcome onto the intent (and frees the order for a new attempt
    # if the push was refused).
    ref = node_id(intent);
    refused = False;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        current = PaymentState(intent.state);
        if result.get("accepted") {
            intent.state = transition(current, PaymentState.STK_REQUESTED).value;
            intent.checkout_request_id = str(result.get("checkout_request_id", ""));
        } elif result.get("uncertain") {
            intent.push_uncertain = True;
            intent.push_error = str(result.get("error_code", ""));
        } else {
            intent.state = transition(current, PaymentState.FAILED).value;
            intent.result_text = str(result.get("message", ""));
            intent.push_error = str(result.get("error_code", ""));
            refused = True;
        }
        intent.updated_at = now().isoformat();
        commit_now();
    } finally {
        restore(me);
    }
    if refused {
        release(ORDER_PAYMENT, intent.order_id, ref);
    }
}

def ensure_pushed(cinema: Tenant, intent: PaymentIntent, provider: PaymentProvider) {
    # Sends the intent's one STK push if nobody has, and records its outcome.
    if intent.state != PaymentState.CREATED.value or intent.push_uncertain {
        return;
    }
    ref = node_id(intent);
    result = _result_of(ref);
    if result is None {
        mine = fresh_node_id();
        if claim(STK_GATE, ref, mine) != mine {
            # Another request is sending it right now; a later call records it.
            return;
        }
        pushed = provider.stk_push(
            StkRequest(
                reference=intent.reference,
                phone=intent.phone,
                amount_cents=intent.amount_cents,
                account=intent.reference,
                description="Cinema tickets",
                callback_url=callback_url(intent.callback_token),
                shortcode=shortcode_for(cinema, intent.mpesa_version)
            )
        );
        result = {
            "accepted": pushed.accepted,
            "checkout_request_id": pushed.checkout_request_id,
            "error_code": pushed.error_code,
            "message": pushed.message,
            "uncertain": pushed.uncertain
        };
        claim(STK_RESULT, ref, json.dumps(result));
    }
    _record(cinema, intent, result);
}

def provider_of(cinema: Tenant, intent: PaymentIntent) -> PaymentProvider | None {
    # The provider an intent is sent and checked with (its cinema's account, P15.3), or
    # None when this server can't reach it.
    try {
        return provider_for(cinema, intent.mpesa_version);
    } except ProviderNotConfigured {
        return None;
    }
}

def _provider(cinema: Tenant, version: int) -> PaymentProvider {
    try {
        return provider_for(cinema, version);
    } except NotConnected {
        raise Refused(
            "mpesa_not_connected", "This cinema can't take M-Pesa payments yet."
        );
    } except ProviderNotConfigured {
        raise Refused(
            "payments_unavailable", "Paying online isn't available right now."
        );
    }
}

def _number(phone: str) -> str {
    try {
        return msisdn(phone);
    } except InvalidPhone as e {
        raise Refused("invalid_phone", str(e));
    }
}

def _replay(cinema: Tenant, ref: str, number: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The answer for a key that already names an intent.
    intent = stored_intent(cinema, ref);
    if intent is None {
        raise Refused(
            "payment_in_progress",
            "Your payment is still being started. Try again in a moment."
        );
    }
    if intent.phone != number {
        raise Refused(
            "key_reused", "This page sent a different payment. Reload it and try again."
        );
    }
    ensure_pushed(cinema, intent, _provider(cinema, intent.mpesa_version));
    return {"ok": True, "payment": payment_view(intent)};
}

def _start_payment(  # jac:ignore[W3030] the payment, the seller and the consent
    slug: str,
    screening_id: str,
    holder: str,
    phone: str,
    email: str,
    idempotency_key: str,
    sold_by: str = "",
    offers: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # sold_by: the member of staff selling at the box office (P6.5), "" online. At the
    # counter the email address may be left out; online, the tickets always go by
    # email. The intent keeps sold_by, so the ledger records who took the money (P7.1).
    # Online, paying is agreeing to the policies shown above Pay (P14.3c): the order
    # keeps their versions. offers "yes": the customer ticked the box for the cinema's
    # offers.
    (cinema, screening) = showtime_on_sale(slug, screening_id);

    def find_order -> Order | None {
        return pending_order(cinema, screening, holder);
    }
    return pay_order(
        cinema,
        find_order,
        "You haven't placed an order for this showtime.",
        holder,
        phone,
        email,
        idempotency_key,
        sold_by,
        offers
    );
}

def pay_order(  # jac:ignore[W3030] the cinema, the order's lookup and the payment's details
    cinema: Tenant,
    find_order: any,  # jac:ignore[W1037]
    no_order: str,
    holder: str,
    phone: str,
    email: str,
    idempotency_key: str,
    sold_by: str = "",
    offers: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # Starts paying the order `find_order()` gives (pending, for `holder`), or refuses
    # with `no_order`: a showtime's (above) or a snacks-only sale at a venue's counter
    # (P12.10, core/booking/snack_sale.jac).
    # No money before AfriCinemas has verified the cinema (P14.1).
    require_live(cinema);
    check_holder(holder);
    check_key(idempotency_key);
    number = _number(phone);
    if (email.strip() or not sold_by) and email_problem(email) {
        raise Refused("invalid_email", email_problem(email));
    }
    address = clean_email(email) if email.strip() else "";
    # The cinema's own M-Pesa account in use now (P15.3): this payment's, for good.
    try {
        version = version_for_new(cinema);
    } except NotConnected {
        raise Refused(
            "mpesa_not_connected", "This cinema can't take M-Pesa payments yet."
        );
    }
    provider = _provider(cinema, version);
    key_name = f"{node_id(cinema)}:{holder}:{idempotency_key}";
    existing = claim_holder(PAY_KEYS, key_name);
    if existing is not None {
        return _replay(cinema, existing, number);
    }
    found: Order | None = find_order();
    if found is None {
        raise Refused("no_order", no_order);
    }
    order: Order = found;
    if not order.pay_by or datetime.fromisoformat(order.pay_by) <= now() {
        raise Refused(
            "order_expired",
            "The time to pay for this order is up. Choose your seats again."
        );
    }
    order_id = node_id(order);
    active = claim_holder(ORDER_PAYMENT, order_id);
    if active is not None {
        previous = stored_intent(cinema, active);
        if previous is not None and not is_final(PaymentState(previous.state)) {
            raise Refused(
                "payment_in_progress",
                "A payment for this order is already on its way to your phone.",
                {"payment": payment_view(previous)}
            );
        }
        release(ORDER_PAYMENT, order_id, active);
    }
    ref = fresh_node_id();
    won = claim(PAY_KEYS, key_name, ref, PROVISIONAL_SECONDS);
    if won != ref {
        return _replay(cinema, won, number);
    }
    if claim(ORDER_PAYMENT, order_id, ref, PROVISIONAL_SECONDS) != ref {
        release(PAY_KEYS, key_name, ref);
        raise Refused(
            "payment_in_progress",
            "A payment for this order is already on its way to your phone."
        );
    }
    # The callback URL's token names this intent (plan 5.4: the callback finds it).
    token = secrets.token_urlsafe(24);
    claim(CALLBACK_TOKENS, token, f"{node_id(cinema)}|{ref}", PROVISIONAL_SECONDS);
    claim(OPEN_PAYMENTS, ref, node_id(cinema), PROVISIONAL_SECONDS);
    stamp = now().isoformat();
    shown = shown_at_checkout(cinema) if not sold_by else {};
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        intent = PaymentIntent(
            tenant_id=node_id(cinema),
            order_id=order_id,
            screening_id=order.screening_id,
            holder=holder,
            idempotency_key=idempotency_key,
            reference=secrets.token_hex(5).upper(),
            phone=number,
            amount_cents=order.total_cents,
            currency=order.currency,
            callback_token=token,
            sold_by=sold_by,
            mpesa_version=version,
            created_at=stamp,
            updated_at=stamp
        );
        assign_id(intent, ref);
        order.email = address;
        if not sold_by {
            order.terms_shown = shown;
        }
        order ++> intent;
        attach_to_tenant(intent, cinema);
        replay_point("payment_before_commit");
        commit_now();
    } except Exception as e {
        # Graph work rolls back with the request; undo the claims, which don't.
        release(CALLBACK_TOKENS, token, f"{node_id(cinema)}|{ref}");
        release(OPEN_PAYMENTS, ref, node_id(cinema));
        release(ORDER_PAYMENT, order_id, ref);
        release(PAY_KEYS, key_name, ref);
        restore(me);
        raise e;
    }
    restore(me);
    renew(PAY_KEYS, key_name, ref, KEY_SECONDS);
    renew(ORDER_PAYMENT, order_id, ref, 0);
    renew(CALLBACK_TOKENS, token, f"{node_id(cinema)}|{ref}", 0);
    renew(OPEN_PAYMENTS, ref, node_id(cinema), 0);
    replay_point("payment_after_commit");
    if offers == "yes" and not sold_by and sends_offers(cinema) {
        record_consent(cinema, address, True, "checkout", order.reference);
    }
    ensure_pushed(cinema, intent, provider);
    return {"ok": True, "payment": payment_view(intent)};
}

def latest_intent(cinema: Tenant, order: Order) -> PaymentIntent | None {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = sorted(
            [order-->[?:PaymentIntent]],
            key=lambda (p: PaymentIntent) -> str { return p.created_at; }  # jac:ignore[W1037]
        );
    } finally {
        restore(me);
    }
    return found[-1] if found else None;
}

def counter_payment(
    slug: str,
    screening_id: str,
    holder: str,
    phone: str,
    email: str,
    key: str,
    sold_by: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # Starts paying an order at the box office (P6.5) for the member of staff `sold_by`:
    # as online, but the email address may be left out. The caller checks they may sell
    # there.
    return _start_payment(slug, screening_id, holder, phone, email, key, sold_by);
}

def:pub start_payment(  # jac:ignore[W3030] the order, the customer, the key, the two choices
    slug: str,
    screening_id: str,
    holder: str,
    phone: str,
    email: str,
    idempotency_key: str,
    offers: str = "",
    adult: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # offers: "yes" when the customer ticked the box for the cinema's offers (P14.3c).
    # adult: "yes" when they declared they're 18 or over (Data Protection Act s.33,
    # P15.0): an online payment isn't started without it, so every order paid online
    # was declared. Text, not a bool, for JI-060.
    return answer(
        lambda -> any { return _start_online(  # jac:ignore[W1037]
            slug, screening_id, holder, phone, email, idempotency_key, offers, adult
        ); }
    );
}

def _start_online(  # jac:ignore[W3030] start_payment's fields, and the declaration
    slug: str,
    screening_id: str,
    holder: str,
    phone: str,
    email: str,
    idempotency_key: str,
    offers: str,
    adult: str
) -> dict[str, any] {  # jac:ignore[W1037]
    if adult != "yes" {
        raise Refused(
            "adult_required", "Confirm you're 18 or over to book and pay online."
        );
    }
    return _start_payment(
        slug, screening_id, holder, phone, email, idempotency_key, "", offers
    );
}
