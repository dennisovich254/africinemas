"""Payments (P5.3, architecture §29, §32): Order -> PaymentIntent.

Owned by the cinema's principal (ADR-0003) and granted to its access group (ADR-0004),
like every tenant node. One intent is one attempt to pay an order: one STK push, at
most. A failed or cancelled attempt can be followed by another (a new intent).
"""

node PaymentIntent {
    # state is a PaymentState value (core/payments/state.jac). reference is for people
    # (receipts, support), never an internal id; callback_token is the unguessable part
    # of the callback URL that matches Safaricom's reply to this intent (plan 5.4).
    # push_uncertain: the push got no answer, so whether the prompt reached the phone is
    # unknown; it is never sent again (ADR-0016).
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
        created_at: str = "",
        updated_at: str = "";
}
