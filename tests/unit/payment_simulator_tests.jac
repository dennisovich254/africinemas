"""P5.1: the simulated M-Pesa provider (core/payments/provider.jac, simulator.jac).

The rest of the app talks to a PaymentProvider: send an STK push, and later ask what
happened. The simulator stands in for Daraja in tests and demos, scripted per phone
number: success, fail (insufficient funds), cancel (the customer dismissed the
prompt), timeout (no answer at all), late_success (no answer in time, then success)
and reject (Daraja refuses the push). What Safaricom would POST to our callback URL is
callback(); what a status query returns is query().
"""

import from core.payments.state { PaymentState }
import from core.payments.provider { StkRequest, StkStatus, state_for_result }
import from core.payments.simulator { SimulatedProvider }

glob PHONE: str = "254712345678";

def _request(reference: str, phone: str = PHONE, cents: int = 156000) -> StkRequest {
    return StkRequest(
        reference=reference,
        phone=phone,
        amount_cents=cents,
        account="NOVA",
        description="Tickets"
    );
}

def _called(sim: SimulatedProvider, checkout: str) -> StkStatus {
    # The callback Safaricom would have sent; there must be one.
    found = sim.callback(checkout);
    assert found is not None , checkout;
    return found;
}

def _sim(outcome: str) -> SimulatedProvider {
    return SimulatedProvider(outcomes={PHONE: outcome});
}

test "M-Pesa result codes map to payment states" {
    assert state_for_result(0) == PaymentState.SUCCESS;
    assert state_for_result(1032) == PaymentState.CANCELLED;
    for code in [1, 1037, 2001, 17] {
        assert state_for_result(code) == PaymentState.FAILED , code;
    }
}

test "success: the callback and the query both say paid, with a receipt" {
    sim = _sim("success");
    pushed = sim.stk_push(_request("ord-1"));
    assert pushed.accepted and pushed.checkout_request_id;
    called = sim.callback(pushed.checkout_request_id);
    assert called is not None and called.state == PaymentState.SUCCESS;
    assert called.receipt and called.amount_cents == 156000 and called.phone == PHONE;
    asked = sim.query(pushed.checkout_request_id);
    assert asked.state == PaymentState.SUCCESS and asked.receipt == called.receipt;
}

test "fail and cancel answer with their result codes and no receipt" {
    for (outcome, state, code) in [
        ("fail", PaymentState.FAILED, 1),
        ("cancel", PaymentState.CANCELLED, 1032)
    ] {
        sim = _sim(outcome);
        pushed = sim.stk_push(_request("ord-2"));
        called = _called(sim, pushed.checkout_request_id);
        assert called.state == state and called.result_code == code , outcome;
        assert not called.receipt;
        assert sim.query(pushed.checkout_request_id).state == state;
    }
}

test "timeout: no callback ever comes, and the query says it failed" {
    sim = _sim("timeout");
    pushed = sim.stk_push(_request("ord-3"));
    assert sim.callback(pushed.checkout_request_id) is None;
    asked = sim.query(pushed.checkout_request_id);
    assert asked.state == PaymentState.FAILED and asked.result_code == 1037;
}

test "late success: nothing in time, then the customer pays after all" {
    sim = _sim("late_success");
    pushed = sim.stk_push(_request("ord-4"));
    assert sim.callback(pushed.checkout_request_id) is None;
    assert sim.query(pushed.checkout_request_id).state == PaymentState.STK_REQUESTED;
    sim.pay_late(pushed.checkout_request_id);
    assert _called(sim, pushed.checkout_request_id).state == PaymentState.SUCCESS;
    assert sim.query(pushed.checkout_request_id).state == PaymentState.SUCCESS;
}

test "reject: Daraja refuses the push" {
    pushed = _sim("reject").stk_push(_request("ord-5"));
    assert not pushed.accepted and not pushed.checkout_request_id;
    assert pushed.error_code;
}

test "pushes are counted per reference, each with its own checkout id" {
    sim = SimulatedProvider();
    first = sim.stk_push(_request("ord-6"));
    second = sim.stk_push(_request("ord-6"));
    sim.stk_push(_request("ord-7"));
    assert first.checkout_request_id != second.checkout_request_id;
    assert sim.push_count("ord-6") == 2 and sim.push_count("ord-7") == 1;
    assert sim.push_count("ord-8") == 0;
    # Unscripted numbers succeed.
    assert _called(sim, first.checkout_request_id).state == PaymentState.SUCCESS;
}

test "bad pushes are refused before they reach M-Pesa" {
    sim = SimulatedProvider();
    for bad in [
        _request("ord-9", phone="0712345678"),
        _request("ord-9", cents=0),
        _request("ord-9", cents=150050)
    ] {
        pushed = sim.stk_push(bad);
        assert not pushed.accepted and pushed.error_code == "invalid_request" , bad;
    }
    assert sim.push_count("ord-9") == 0;
    assert sim.query("ws_CO_unknown").state == PaymentState.UNKNOWN;
}

test "the test numbers script outcomes for demos and browser tests" {
    sim = SimulatedProvider();
    for (number, state) in [
        ("254700000001", PaymentState.FAILED),
        ("254700000002", PaymentState.CANCELLED),
        ("254712345678", PaymentState.SUCCESS)
    ] {
        pushed = sim.stk_push(_request(f"ord-{number}", phone=number));
        assert sim.query(pushed.checkout_request_id).state == state , number;
    }
    timed_out = sim.stk_push(_request("ord-t", phone="254700000003"));
    assert sim.callback(timed_out.checkout_request_id) is None;
    assert not sim.stk_push(_request("ord-r", phone="254700000004")).accepted;
}
