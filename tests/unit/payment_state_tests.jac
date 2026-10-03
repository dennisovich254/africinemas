"""P5.1: the payment state machine (architecture §32; core/payments/state.jac).

A payment is created, then the STK push is requested, then it ends in success,
failure or cancellation. A timeout (no callback in time) or an unknown answer is not
final: a status query settles it later. A payment that can't be settled automatically
(a wrong amount, or a success after the seats were released) needs attention. Any
other move is refused; repeating the current state is a harmless no-op, so a
duplicate callback changes nothing.
"""

import from core.payments.state {
    PaymentState,
    InvalidTransition,
    transition,
    is_final
}

def _refused(start: PaymentState, target: PaymentState) -> bool {
    try {
        transition(start, target);
    } except InvalidTransition {
        return True;
    }
    return False;
}

test "a payment goes from created through the STK push to an outcome" {
    pushed = transition(PaymentState.CREATED, PaymentState.STK_REQUESTED);
    assert pushed == PaymentState.STK_REQUESTED;
    for outcome in [
        PaymentState.SUCCESS,
        PaymentState.FAILED,
        PaymentState.CANCELLED,
        PaymentState.TIMEOUT,
        PaymentState.UNKNOWN,
        PaymentState.NEEDS_ATTENTION
    ] {
        assert transition(pushed, outcome) == outcome , outcome;
    }
    # Daraja can refuse the push itself.
    assert transition(PaymentState.CREATED, PaymentState.FAILED) == PaymentState.FAILED;
}

test "a timeout or an unknown answer is settled later" {
    for waiting in [PaymentState.TIMEOUT, PaymentState.UNKNOWN] {
        assert not is_final(waiting);
        for outcome in [
            PaymentState.SUCCESS,
            PaymentState.FAILED,
            PaymentState.CANCELLED,
            PaymentState.NEEDS_ATTENTION
        ] {
            assert transition(waiting, outcome) == outcome , (waiting, outcome);
        }
    }
    assert transition(PaymentState.TIMEOUT, PaymentState.UNKNOWN)
        == PaymentState.UNKNOWN;
}

test "invalid moves are refused" {
    assert _refused(PaymentState.CREATED, PaymentState.SUCCESS);
    assert _refused(PaymentState.SUCCESS, PaymentState.FAILED);
    assert _refused(PaymentState.FAILED, PaymentState.SUCCESS);
    assert _refused(PaymentState.CANCELLED, PaymentState.STK_REQUESTED);
    assert _refused(PaymentState.UNKNOWN, PaymentState.TIMEOUT);
    assert _refused(PaymentState.SUCCESS, PaymentState.NEEDS_ATTENTION);
}

test "a late success after failing, cancelling or timing out needs attention" {
    for ended in [PaymentState.FAILED, PaymentState.CANCELLED] {
        assert transition(ended, PaymentState.NEEDS_ATTENTION)
            == PaymentState.NEEDS_ATTENTION;
    }
}

test "repeating the current state changes nothing, and finals are final" {
    for state in [
        PaymentState.SUCCESS,
        PaymentState.FAILED,
        PaymentState.STK_REQUESTED
    ] {
        assert transition(state, state) == state;
    }
    for state in [
        PaymentState.SUCCESS,
        PaymentState.FAILED,
        PaymentState.CANCELLED,
        PaymentState.NEEDS_ATTENTION
    ] {
        assert is_final(state) , state;
    }
    for state in [PaymentState.CREATED, PaymentState.STK_REQUESTED] {
        assert not is_final(state) , state;
    }
}
