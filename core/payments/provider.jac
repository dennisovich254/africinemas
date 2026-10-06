"""The payment provider interface (P5.1, architecture §29; ADR-0015).

The app asks a provider to send an STK push (the PIN prompt on the customer's phone)
and, later, what happened to it. M-Pesa answers each push twice over: Safaricom POSTs
the result to our callback URL, and a status query returns it on demand (§33: never
trust the browser). Both arrive as an StkStatus. Daraja (plan 5.2) and the simulator
(simulator.jac) implement it.

Amounts are in cents, like every price in the app, but M-Pesa takes whole shillings, so
a push for a fractional amount is refused before it is sent.
"""

import from core.payments.state { PaymentState }

obj StkRequest {
    # reference is ours (the payment's), sent to M-Pesa and echoed back.
    has reference: str,
        phone: str,
        amount_cents: int,
        account: str,
        description: str;
}

obj StkPushResult {
    # accepted: Daraja took the push and will answer for checkout_request_id.
    has accepted: bool,
        checkout_request_id: str = "",
        error_code: str = "",
        message: str = "";
}

obj StkStatus {
    # state is SUCCESS, FAILED or CANCELLED once M-Pesa has an answer, STK_REQUESTED
    # while the customer hasn't answered yet, UNKNOWN if M-Pesa doesn't know the push.
    # receipt is the M-Pesa receipt number on success.
    has checkout_request_id: str,
        state: PaymentState,
        result_code: int = -1,
        result_text: str = "",
        receipt: str = "",
        amount_cents: int = 0,
        phone: str = "";
}

obj PaymentProvider {
    def stk_push(request: StkRequest) -> StkPushResult abst;
    def query(checkout_request_id: str) -> StkStatus abst;
}

def state_for_result(code: int) -> PaymentState {
    # M-Pesa's ResultCode: 0 paid, 1032 cancelled by the customer; anything else
    # (1 insufficient funds, 1037 phone unreachable, 2001 wrong PIN, ...) failed.
    if code == 0 {
        return PaymentState.SUCCESS;
    }
    if code == 1032 {
        return PaymentState.CANCELLED;
    }
    return PaymentState.FAILED;
}

def valid_push(request: StkRequest) -> str {
    # Why a push can't be sent ("" if it can): M-Pesa wants 2547/2541 numbers and a
    # positive whole number of shillings.
    if len(request.phone) != 12
        or not request.phone.isdigit()
        or not request.phone.startswith(("2547", "2541")) {
        return "The phone number isn't in M-Pesa's form (2547XXXXXXXX).";
    }
    if request.amount_cents <= 0 or request.amount_cents % 100 != 0 {
        return "M-Pesa takes a positive whole number of shillings.";
    }
    return "";
}
