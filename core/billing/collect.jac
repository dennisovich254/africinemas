"""Collecting what's owed (P15.5, ADR-0084): paying an invoice, reminders, suspension.

**Paying.** A cinema pays an invoice in full from its Billing page: Pay now sends an
M-Pesa prompt to the phone it gives, for exactly the invoice's amount (payable_of: the
amount due in whole shillings), with the invoice number as the account. Nobody types an
amount (owner, 2026-10-28). It goes to AfriCinemas' own M-Pesa app (DARAJA_*, the
paybill AFRICINEMAS_BILLING_PAYBILL names), never a cinema's. Each payment is a
BillPayment under the cinema; one at a time per invoice.

**Settling**, as bookings do (ADR-0018): Safaricom's callback
(POST /hooks/mpesa-bill/{token}) is only filed; M-Pesa is then asked directly what
happened, by the job every SETTLE_SECONDS or when the Billing page asks. Paid for the
right amount while the invoice is still owed: the invoice is paid, once (a receipt is
claimed once, shared with bookings). Paid but the invoice was already paid or waived,
or for another amount: **unmatched**, for platform staff to match to an invoice by hand
or record as refunded. Failed or cancelled: the invoice is still owed.

**Reminders**: REMINDERS, by days from the due date, to the cinema's owners, each once
(a claim per invoice and kind), skipped while the invoice is disputed. A run that
missed a day sends the latest one due, not every one missed.

**Suspension** is never automatic: core/billing/billing_api.jac.
"""

import os;
import re;
import json;
import html;
import from datetime { date, datetime, timedelta }
import from http { HTTPMethod }
import from core.clock { now }
import from core.claims { claim, release, claims_in, holder }
import from core.catalog.answers { Refused }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id
}
import from core.site { main_address }
import from core.platform.cinemas_api { owners_of }
import from core.payments.phone { msisdn, InvalidPhone }
import from core.payments.provider { StkRequest, valid_push, PaymentProvider }
import from core.payments.state { PaymentState }
import from core.payments.choice { payment_provider, ProviderNotConfigured }
import from core.payments.daraja { parse_callback }
import from core.payments.mpesa_api { MAIL_QUEUE }
import from core.billing.statements {
    Statement,
    statements_of,
    statement_numbered,
    status_of,
    payable_of,
    disputed,
    update_statement,
    local_today
}
import from core.billing.billing_text { kes, day_label }

glob TOKENS: str = "bill-callback-token",
     INBOX: str = "bill-inbox",
     PENDING: str = "bill-pending",
     RECEIPTS: str = "mpesa-receipt",
     REMINDED: str = "bill-reminder",
     TOKEN_PATTERN: str = "[A-Za-z0-9_-]{16,64}",
     CALLBACK_ENV: str = "DARAJA_CALLBACK_BASE",
     NO_CALLBACK: str = "https://callbacks.invalid",
     # A prompt still unanswered after this long is given up on.
     EXPIRE_S: int = 15 * 60,
     SETTLE_SECONDS: int = int(os.environ.get("AFRICINEMAS_SETTLE_SECONDS", "5")),
     ACK: dict[str, any] = {"ResultCode": 0, "ResultDesc": "Accepted"},  # jac:ignore[W1037]
     # (kind, days after the due date) (owner, 2026-10-28): latest first.
     REMINDERS: list[tuple[str, int]] = [
         ("late_7", 7),
         ("late_3", 3),
         ("due_today", 0),
         ("before", -2)
     ],
     OWED: list[str] = ["due", "overdue"];

node BillPayment {
    # state: "stk_requested", then "paid", "failed", "cancelled", "expired" or
    # "unmatched"; an unmatched one becomes "matched" or "refunded" by hand.
    has tenant_id: str,
        number: str,
        reference: str,
        phone: str,
        amount_cents: int,
        state: str = "stk_requested",
        checkout_request_id: str = "",
        callback_token: str = "",
        receipt: str = "",
        paid_cents: int = 0,
        result_text: str = "",
        unmatched_reason: str = "",
        created_at: str = "",
        settled_at: str = "",
        started_by: str = "",
        resolved_by: str = "",
        resolved_note: str = "";
}

def masked(phone: str) -> str {
    return phone[:5] + "***" + phone[-3:] if len(phone) > 8 else "***";
}

def payment_view(p: BillPayment) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "reference": p.reference,
        "number": p.number,
        "phone": masked(p.phone),
        "amount_cents": p.amount_cents,
        "paid_cents": p.paid_cents,
        "state": p.state,
        "receipt": p.receipt,
        "result_text": p.result_text,
        "unmatched_reason": p.unmatched_reason,
        "created_at": p.created_at,
        "settled_at": p.settled_at,
        "resolved_by": p.resolved_by,
        "resolved_note": p.resolved_note
    };
}

def payments_of(cinema: Tenant) -> list[BillPayment] {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [cinema-->[?:BillPayment]];
    } finally {
        restore(me);
    }
    return sorted(
        found, key=lambda (p: BillPayment) -> str { return p.created_at; }, reverse=True
    );
}

def payment_named(cinema: Tenant, reference: str) -> BillPayment | None {
    for p in payments_of(cinema) {
        if p.reference == reference {
            return p;
        }
    }
    return None;
}

def _set(cinema: Tenant, p: BillPayment, changes: dict[str, any]) {  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        for (field, value) in changes.items() {
            setattr(p, field, value);
        }
        flush_now();
    } finally {
        restore(me);
    }
}

def callback_url(token: str) -> str {
    base = os.environ.get(CALLBACK_ENV, "").strip().rstrip("/") or NO_CALLBACK;
    return f"{base}/hooks/mpesa-bill/{token}";
}

def _provider -> PaymentProvider {
    try {
        return payment_provider();
    } except ProviderNotConfigured {
        raise Refused(
            "payments_unavailable",
            "Paying by M-Pesa isn't available right now. Try again later."
        );
    }
}

def start_payment(cinema: Tenant, s: Statement, phone: str, who: str) -> BillPayment {
    # Sends the prompt for the invoice's full amount to `phone`.
    status = status_of(s, local_today(cinema));
    if status not in OWED {
        raise Refused(
            "nothing_to_pay",
            "This invoice is paid."
                if status == "paid"
                else "There's nothing to pay on this invoice."
        );
    }
    try {
        number = msisdn(phone);
    } except InvalidPhone as e {
        raise Refused("invalid_phone", str(e));
    }
    at = now();
    for p in payments_of(cinema) {
        if p.number == s.number and p.state == "stk_requested" {
            started = datetime.fromisoformat(p.created_at);
            if (at - started).total_seconds() < EXPIRE_S {
                raise Refused(
                    "payment_in_progress",
                    "A prompt for this invoice is already on its way. Answer it on the phone, or wait a few minutes and try again."
                );
            }
        }
    }
    provider = _provider();
    reference = "BILL" + fresh_node_id().replace("-", "")[:12].upper();
    token = fresh_node_id().replace("-", "") + fresh_node_id().replace("-", "")[:8];
    request = StkRequest(
        reference=reference,
        phone=number,
        amount_cents=payable_of(s),
        account=s.number,
        description=f"AfriCinemas invoice {s.number}",
        callback_url=callback_url(token)
    );
    wrong = valid_push(request);
    if wrong {
        raise Refused("invalid_payment", wrong);
    }
    tenant_id = node_id(cinema);
    claim(TOKENS, token, f"{tenant_id}|{reference}");
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        made = BillPayment(
            tenant_id=tenant_id,
            number=s.number,
            reference=reference,
            phone=number,
            amount_cents=request.amount_cents,
            callback_token=token,
            created_at=at.isoformat(),
            started_by=who
        );
        cinema ++> made;
        attach_to_tenant(made, cinema);
        flush_now();
    } finally {
        restore(me);
    }
    claim(PENDING, reference, tenant_id);
    pushed = provider.stk_push(request);
    if pushed.accepted or pushed.uncertain {
        _set(cinema, made, {"checkout_request_id": pushed.checkout_request_id});
    } else {
        _set(
            cinema,
            made,
            {
                "state": "failed",
                "result_text": pushed.message or "M-Pesa didn't take the request.",
                "settled_at": now().isoformat()
            }
        );
        release(PENDING, reference, tenant_id);
    }
    return made;
}

def file_callback(token: str, body: any) -> bool {  # jac:ignore[W1037]
    # Files Safaricom's callback for the payment `token` names; repeats change nothing.
    if not isinstance(token, str) or not re.fullmatch(TOKEN_PATTERN, token) {
        return False;
    }
    if holder(TOKENS, token) is None {
        return False;
    }
    status = parse_callback(body);
    if status is None {
        return False;
    }
    claim(
        INBOX,
        token,
        json.dumps(
            {
                "checkout_request_id": status.checkout_request_id,
                "result_code": status.result_code
            }
        )
    );
    return True;
}

@restspec(method=HTTPMethod.POST, path="/hooks/mpesa-bill/{token}")
def:pub mpesa_bill_callback(token: str, Body: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # Always acknowledged; what it says is checked with M-Pesa before anything changes.
    # Body is required, not defaulted (JI-025).
    file_callback(token, {"Body": Body});
    return ACK;
}

def _final(cinema: Tenant, p: BillPayment, changes: dict[str, any]) {  # jac:ignore[W1037]
    _set(cinema, p, {** changes, "settled_at": now().isoformat()});
    release(PENDING, p.reference, node_id(cinema));
}

def settle(cinema: Tenant, p: BillPayment) -> str {
    # Asks M-Pesa what happened to `p`; its state afterwards.
    if p.state != "stk_requested" {
        return p.state;
    }
    if not p.checkout_request_id {
        if (now() - datetime.fromisoformat(p.created_at)).total_seconds() >= EXPIRE_S {
            _final(cinema, p, {"state": "expired"});
        }
        return p.state;
    }
    status = _provider().query(p.checkout_request_id);
    if status.state in [PaymentState.FAILED, PaymentState.CANCELLED] {
        _final(
            cinema,
            p,
            {
                "state": "failed"
                    if status.state == PaymentState.FAILED
                    else "cancelled",
                "result_text": status.result_text
            }
        );
        return p.state;
    }
    if status.state != PaymentState.SUCCESS {
        if (now() - datetime.fromisoformat(p.created_at)).total_seconds() >= EXPIRE_S {
            _final(cinema, p, {"state": "expired"});
        }
        return p.state;
    }
    # Paid. One receipt pays once, here or for a booking.
    receipt = status.receipt or f"SIM-{p.reference}";
    if claim(RECEIPTS, receipt, f"bill|{p.reference}") != f"bill|{p.reference}" {
        _final(
            cinema,
            p,
            {
                "state": "unmatched",
                "receipt": receipt,
                "paid_cents": status.amount_cents,
                "unmatched_reason": "receipt_used"
            }
        );
        return p.state;
    }
    paid = status.amount_cents or p.amount_cents;
    s = statement_numbered(cinema, p.number);
    reason = "";
    if s is None {
        reason = "no_invoice";
    } elif status_of(s, local_today(cinema)) not in OWED {
        reason = "already_settled";
    } elif paid != payable_of(s) {
        reason = "amount_differs";
    }
    if reason or s is None {
        _final(
            cinema,
            p,
            {
                "state": "unmatched",
                "receipt": receipt,
                "paid_cents": paid,
                "unmatched_reason": reason
            }
        );
        return p.state;
    }
    stamp = now().isoformat();
    update_statement(
        cinema,
        s,
        {
            "paid_at": stamp,
            "paid_receipt": receipt,
            "paid_reference": p.reference,
            "paid_how": "mpesa"
        }
    );
    _final(cinema, p, {"state": "paid", "receipt": receipt, "paid_cents": paid});
    queue_mail(
        cinema,
        f"{cinema.name}: invoice {s.number} is paid",
        f"Thank you. We've received {kes(paid)} for invoice {s.number} (M-Pesa {receipt})."
    );
    return p.state;
}

def settle_due -> int {
    # Settles every payment waiting for M-Pesa's answer; how many became final.
    done = 0;
    for (reference, tenant_id, _) in claims_in(PENDING) {
        cinema = tenant_by_id(str(tenant_id));
        if cinema is None {
            continue;
        }
        p = payment_named(cinema, str(reference));
        if p is None {
            continue;
        }
        try {
            if settle(cinema, p) != "stk_requested" {
                done += 1;
            }
        } except Exception as e {
            print(f"billing: settling {reference} failed: {e}");
        }
    }
    return done;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=SETTLE_SECONDS)
def settle_bill_payments {
    # Runs as Jac's system identity on every server copy.
    settle_due();
}

def queue_mail(cinema: Tenant, subject: str, lead: str) {
    # To every owner, through the mail queue the M-Pesa job sends (core/payments/mpesa_api.jac).
    office = f"{main_address()}/app/{cinema.slug}/billing";
    text = f"{lead}\n\nBilling: {office}\n\nAfriCinemas\n";
    body = f'<p>{html.escape(lead)}</p><p><a href="{html.escape(
        office
    )}">Open the Billing page</a></p>';
    for address in owners_of(cinema) {
        claim(
            MAIL_QUEUE,
            fresh_node_id(),
            json.dumps({"to": address, "subject": subject, "text": text, "html": body})
        );
    }
}

def reminder_due(s: Statement, today: date) -> str {
    # The latest reminder `s` has reached as of `today` ("" for none): it's owed, not
    # disputed, and the day has come.
    if status_of(s, today) not in OWED or disputed(s) {
        return "";
    }
    after = (today - date.fromisoformat(s.due_on)).days;
    for (kind, days) in REMINDERS {
        if after >= days {
            return kind;
        }
    }
    return "";
}

def _reminder_text(cinema: Tenant, s: Statement, kind: str) -> tuple[str, str] {
    amount = kes(payable_of(s));
    due = day_label(s.due_on);
    if kind == "before" {
        return (
            f"{cinema.name}: invoice {s.number} is due on {due}",
            f"Invoice {s.number} for {amount} is due on {due}. Pay it from your Billing page: Pay now sends the M-Pesa prompt."
        );
    }
    if kind == "due_today" {
        return (
            f"{cinema.name}: invoice {s.number} is due today",
            f"Invoice {s.number} for {amount} is due today. Pay it from your Billing page."
        );
    }
    return (
        f"{cinema.name}: invoice {s.number} is overdue",
        f"Invoice {s.number} for {amount} was due on {due} and isn't paid. Pay it from your Billing page. If it isn't paid, AfriCinemas may suspend your cinema; if something on it is wrong, tell us on the invoice."
    );
}

def remind_due(cinemas: list[Tenant]) -> int {
    # Queues every reminder due now; how many invoices were reminded.
    sent = 0;
    for cinema in cinemas {
        today = local_today(cinema);
        for s in statements_of(cinema) {
            kind = reminder_due(s, today);
            if not kind {
                continue;
            }
            # One email per invoice and kind; an earlier one is skipped once a later is due.
            mine = fresh_node_id();
            if claim(REMINDED, f"{s.number}|{kind}", mine) != mine {
                continue;
            }
            (subject, lead) = _reminder_text(cinema, s, kind);
            queue_mail(cinema, subject, lead);
            sent += 1;
        }
    }
    return sent;
}

def unmatched_payments(cinemas: list[Tenant]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for cinema in cinemas {
        for p in payments_of(cinema) {
            if p.state == "unmatched" {
                rows.append(
                    {
                        ** payment_view(p),
                        "slug": cinema.slug,
                        "cinema_name": cinema.name
                    }
                );
            }
        }
    }
    return rows;
}

def resolve_payment(
    cinema: Tenant, p: BillPayment, action: str, number: str, note: str, who: str
) {
    # Platform staff match an unmatched payment to one of the cinema's invoices still
    # owed, for its full amount, or record that it was refunded.
    if p.state != "unmatched" {
        raise Refused("not_unmatched", "That payment isn't waiting to be matched.");
    }
    clean = " ".join(str(note or "").split())[:300];
    if action == "refund" {
        if not clean {
            raise Refused("note_needed", "Say how it was refunded.");
        }
        _set(
            cinema, p, {"state": "refunded", "resolved_by": who, "resolved_note": clean}
        );
        return;
    }
    if action != "match" {
        raise Refused("invalid_action", "Match it to an invoice or record a refund.");
    }
    s = statement_numbered(cinema, str(number));
    if s is None {
        raise Refused("not_found", "That cinema has no invoice with that number.");
    }
    if status_of(s, local_today(cinema)) not in OWED {
        raise Refused("nothing_to_pay", "That invoice isn't owed.");
    }
    if p.paid_cents != payable_of(s) {
        raise Refused(
            "amount_differs",
            f"The payment ({kes(p.paid_cents)}) isn't the invoice's amount ({kes(
                payable_of(s)
            )})."
        );
    }
    update_statement(
        cinema,
        s,
        {
            "paid_at": now().isoformat(),
            "paid_receipt": p.receipt,
            "paid_reference": p.reference,
            "paid_how": "matched"
        }
    );
    _set(
        cinema,
        p,
        {
            "state": "matched",
            "number": s.number,
            "resolved_by": who,
            "resolved_note": clean
        }
    );
}
