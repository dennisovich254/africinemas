"""The payment state machine (P5.1, architecture §32; ADR-0015), as pure logic.

    CREATED --> STK_REQUESTED --> SUCCESS | FAILED | CANCELLED | TIMEOUT | UNKNOWN
    CREATED --> FAILED                      (Daraja refused the push)
    TIMEOUT --> UNKNOWN | SUCCESS | FAILED | CANCELLED   (settled by a status query)
    UNKNOWN --> SUCCESS | FAILED | CANCELLED

NEEDS_ATTENTION (added to §32; ADR-0015) is for what can't be settled automatically:
a paid amount that doesn't match, or a success that arrives after the payment failed,
was cancelled or timed out (the seats may be gone; plan 5.4 adds the refund task).
SUCCESS, FAILED, CANCELLED and NEEDS_ATTENTION are final for the machine; refunds and
reversals are ledger entries (§37), not states.

Moving to the state a payment is already in is a no-op, so a duplicate callback
changes nothing; any other move not listed raises InvalidTransition.
"""

enum PaymentState {
    CREATED = "created",
    STK_REQUESTED = "stk_requested",
    SUCCESS = "success",
    FAILED = "failed",
    CANCELLED = "cancelled",
    TIMEOUT = "timeout",
    UNKNOWN = "unknown",
    NEEDS_ATTENTION = "needs_attention"
}

class InvalidTransition(ValueError) {}

glob NEXT: dict[str, list[str]] = {
         "created": ["stk_requested", "failed"],
         "stk_requested": [
             "success",
             "failed",
             "cancelled",
             "timeout",
             "unknown",
             "needs_attention"
         ],
         "timeout": ["unknown", "success", "failed", "cancelled", "needs_attention"],
         "unknown": ["success", "failed", "cancelled", "needs_attention"],
         "failed": ["needs_attention"],
         "cancelled": ["needs_attention"],
         "success": [],
         "needs_attention": []
     },
     FINAL: list[str] = ["success", "failed", "cancelled", "needs_attention"];

def transition(current: PaymentState, target: PaymentState) -> PaymentState {
    # The state after moving `current` to `target`; raises InvalidTransition.
    if current == target {
        return current;
    }
    if target.value not in NEXT[current.value] {
        raise InvalidTransition(
            f"a payment can't go from {current.value} to {target.value}"
        );
    }
    return target;
}

def is_final(state: PaymentState) -> bool {
    # Final for the machine: only a late success (needs attention) leaves FAILED or
    # CANCELLED, and nothing leaves SUCCESS or NEEDS_ATTENTION.
    return state.value in FINAL;
}
