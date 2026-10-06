"""P5.3: starting a payment (in-process app: tests/apps/payment_app.jac, simulated M-Pesa).

A visitor with an order waiting for payment pays from their M-Pesa number: the payment
is recorded, and exactly one STK push (PIN prompt) is sent, even when Jac re-runs the
request before or after it commits (forced here with AFRICINEMAS_FAULTS "replay:...").
The idempotency key returns the same payment; an order has one active payment at a
time, and a refused prompt lets the visitor try again.
"""

import os;
import time;
import uuid;
import from os { path }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup {
    PAYMENTS,
    FAULTS,
    ANNA,
    paying_setup,
    pay,
    pushes,
    stored_payments,
    fresh_phone
}

test "paying sends one PIN prompt, and the payment waits for the PIN" {
    (app, screening) = paying_setup();
    try {
        local = "0" + fresh_phone()[3:];
        started = pay(app, screening, local);
        assert started["ok"] , started;
        payment = started["payment"];
        assert payment["state"] == "stk_requested";
        assert payment["amount_cents"] == 186000 and payment["currency"] == "KES";
        assert "*" in payment["phone"] and "PIN" in payment["message"];
        assert pushes(app, payment["reference"]) == 1;
        mine = browse(
            app,
            "my_payment",
            {"slug": "nova", "screening_id": screening, "holder": ANNA}
        );
        assert mine["payment"] == payment;
        # The seats stay taken while the customer pays.
        seats = browse(
            app, "public_seat_availability", {"slug": "nova", "screening_id": screening}
        )["seats"];
        assert {s["label"]: s["state"] for s in seats}["A1"] == "held";
    } finally {
        app.close();
    }
}

test "the same key returns the same payment; another key while one is active is refused" {
    (app, screening) = paying_setup();
    try {
        phone = fresh_phone();
        first = pay(app, screening, phone, "pay-key-anna-0000000001");
        again = pay(app, screening, phone, "pay-key-anna-0000000001");
        assert again["ok"] and again["payment"] == first["payment"] , again;
        assert pushes(app, first["payment"]["reference"]) == 1;
        other = pay(app, screening, phone, "pay-key-anna-0000000002");
        assert code_of(other) == "payment_in_progress" , other;
        assert other["error"]["payment"]["reference"] == first["payment"]["reference"];
        changed = pay(app, screening, fresh_phone(), "pay-key-anna-0000000001");
        assert code_of(changed) == "key_reused";
        assert len(stored_payments(app, screening)) == 1;
    } finally {
        app.close();
    }
}

test "a replay before the payment commits still sends exactly one prompt" {
    (app, screening) = paying_setup();
    os.environ[FAULTS] = f"replay:payment_before_commit,nonce:{uuid.uuid4().hex}";
    try {
        started = pay(app, screening, fresh_phone());
        assert started["ok"]
            and started["payment"]["state"] == "stk_requested" , started;
        assert pushes(app, started["payment"]["reference"]) == 1;
        assert len(stored_payments(app, screening)) == 1;
    } finally {
        os.environ.pop(FAULTS, None);
        app.close();
    }
}

test "a replay after the commit, before the prompt, still sends exactly one prompt" {
    (app, screening) = paying_setup();
    os.environ[FAULTS] = f"replay:payment_after_commit,nonce:{uuid.uuid4().hex}";
    try {
        started = pay(app, screening, fresh_phone());
        assert started["ok"]
            and started["payment"]["state"] == "stk_requested" , started;
        assert pushes(app, started["payment"]["reference"]) == 1;
        assert stored_payments(app, screening)
            == [[started["payment"]["reference"], "stk_requested"]];
    } finally {
        os.environ.pop(FAULTS, None);
        app.close();
    }
}

test "a refused prompt fails the payment, and the visitor can try again" {
    (app, screening) = paying_setup();
    try {
        busy = fresh_phone();
        app.call("owner", "pay_script", {"phone": busy, "outcome": "reject"});
        refused = pay(app, screening, busy);
        assert refused["ok"] and refused["payment"]["state"] == "failed" , refused;
        assert "didn't go through" in refused["payment"]["message"];
        retried = pay(app, screening, fresh_phone());
        assert retried["ok"] and retried["payment"]["state"] == "stk_requested";
        assert [row[1] for row in stored_payments(app, screening)]
            == ["failed", "stk_requested"];
    } finally {
        app.close();
    }
}

test "bad numbers, missing orders, bad keys and switched-off payments are refused" {
    (app, screening) = paying_setup();
    try {
        assert code_of(pay(app, screening, "0202345678")) == "invalid_phone";
        assert code_of(pay(app, screening, fresh_phone(), "short")) == "invalid_key";
        nobody = browse(
            app,
            "start_payment",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": "holder-ben-0123456789abcdefgh",
                "phone": fresh_phone(),
                "idempotency_key": "pay-key-ben-00000000001"
            }
        );
        assert code_of(nobody) == "no_order";
        os.environ.pop(PAYMENTS, None);
        assert code_of(pay(app, screening, fresh_phone())) == "payments_unavailable";
        assert stored_payments(app, screening) == [];
    } finally {
        os.environ[PAYMENTS] = "simulator";
        app.close();
    }
}

test "an order whose time to pay is up can't be paid" {
    os.environ["AFRICINEMAS_PAY_SECONDS"] = "1";
    (app, screening) = paying_setup();
    try {
        time.sleep(1.5);
        assert code_of(pay(app, screening, fresh_phone())) == "order_expired";
    } finally {
        os.environ.pop("AFRICINEMAS_PAY_SECONDS", None);
        app.close();
    }
}
