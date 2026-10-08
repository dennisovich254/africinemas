"""Payments (P5.3, P5.4, architecture §29, §32): Order -> PaymentIntent -> RefundTask.

Owned by the cinema's principal (ADR-0003) and granted to its access group (ADR-0004),
like every tenant node. One intent is one attempt to pay an order: one STK push, at
most. A failed or cancelled attempt can be followed by another (a new intent).
"""

node PaymentIntent {
    # state is a PaymentState value (core/payments/state.jac). reference is for people
    # (receipts, support), never an internal id; callback_token is the unguessable part
    # of the callback URL that matches Safaricom's reply to this intent (plan 5.4).
    # push_uncertain: the push got no answer, so whether the prompt reached the phone is
    # unknown; it is never sent again (ADR-0016). sold_by is the member of staff who
    # started it at the box office (P6.5), "" online; its ledger entry records them.
    has tenant_id: str,
        order_id: str,
        screening_id: str,
        holder: str,
        idempotency_key: str,
        reference: str,
        phone: str,
        amount_cents: int,
        currency: str,
        state: str = "created",
        callback_token: str = "",
        checkout_request_id: str = "",
        result_code: int = -1,
        result_text: str = "",
        push_uncertain: bool = False,
        receipt: str = "",
        paid_amount_cents: int = 0,
        attention_reason: str = "",
        sold_by: str = "",
        created_at: str = "",
        updated_at: str = "";
}

node RefundTask {
    # Money M-Pesa took that bought nothing (P5.4): a success after the order was
    # released, a wrong amount, a receipt already used, or a second payment for an order
    # already paid. Staff refund it (refunds are ledger entries, plan 5.5 / section 38).
    # status: "open" until handled.
    has tenant_id: str,
        intent_id: str,
        order_id: str,
        receipt: str,
        amount_cents: int,
        reason: str,
        status: str = "open",
        created_at: str = "";
}
