"""P5.5: the resolver job and the ledger (in-process app: tests/apps/payment_app.jac).

Stuck payments are settled from M-Pesa's own answer, without a callback; one M-Pesa
still calls "processing" times out and settles later. An order past its time to pay
expires and its seats go back on sale, unless a payment for it went through, which
wins. Every movement of money is an append-only ledger entry: a confirmed booking
balances to its total, money that bought nothing to zero, and resolving again adds
nothing. Thresholds are shortened through the environment.
"""

import os;
import time;
import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { ANNA, paying_setup, pay, fresh_phone }

glob STUCK: str = "AFRICINEMAS_STUCK_SECONDS",
     TIMEOUT: str = "AFRICINEMAS_TIMEOUT_SECONDS",
     PAY_TIME: str = "AFRICINEMAS_PAY_SECONDS",
     BEN: str = "holder-ben-0123456789abcdefgh";

def _env(values: dict[str, str]) {
    for (k, v) in values.items() {
        os.environ[k] = v;
    }
}

def _clear {
    for k in [STUCK, TIMEOUT, PAY_TIME] {
        os.environ.pop(k, None);
    }
}

def _started(app: Served, screening: str, outcome: str = "") -> str {
    phone = fresh_phone();
    if outcome {
        app.call("owner", "pay_script", {"phone": phone, "outcome": outcome});
    }
    started = pay(app, screening, phone);
    assert started["ok"] and started["payment"]["state"] == "stk_requested" , started;
    return started["payment"]["reference"];
}

def _overview(app: Served, screening: str) -> dict[str, any] {  # jac:ignore[W1037]
    return app.call(
        "owner", "pay_overview", {"slug": "nova", "screening_id": screening}
    );
}

def _resolve(app: Served) -> dict[str, int] {
    return app.call("owner", "pay_resolve");
}

test "a payment with no callback is settled by the resolver, and the ledger balances" {
    _env({STUCK: "0"});
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening);
        assert _resolve(app)["payments"] == 1;
        after = _overview(app, screening);
        assert after["payments"] == [[reference, "success", ""]] , after;
        assert after["tickets"] == ["A1", "A2"] and after["seats"]["A1"] == "sold";
        assert after["ledger"] == [["payment", 186000]];
        assert after["balances"] == [["confirmed", 186000, 186000]];
        # Resolving again changes nothing, the ledger included.
        _resolve(app);
        assert _overview(app, screening) == after;
    } finally {
        _clear();
        app.close();
    }
}

test "a payment M-Pesa reports failed fails, and the order can still be paid" {
    _env({STUCK: "0"});
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening, "timeout");
        _resolve(app);
        after = _overview(app, screening);
        assert after["payments"] == [[reference, "failed", ""]] , after;
        assert after["orders"] == ["pending_payment"] and after["ledger"] == [];
        assert _started(app, screening) != reference;
    } finally {
        _clear();
        app.close();
    }
}

test "a payment still processing times out, then settles when the customer pays late" {
    _env({STUCK: "0", TIMEOUT: "0"});
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening, "late_success");
        _resolve(app);
        assert _overview(app, screening)["payments"] == [[reference, "timeout", ""]];
        app.call(
            "owner",
            "pay_late",
            {"slug": "nova", "screening_id": screening, "reference": reference}
        );
        _resolve(app);
        after = _overview(app, screening);
        assert after["payments"] == [[reference, "success", ""]] , after;
        assert after["tickets"] == ["A1", "A2"];
    } finally {
        _clear();
        app.close();
    }
}

test "an unpaid order past its time expires, and its seats can be held by others" {
    _env({PAY_TIME: "1"});
    (app, screening) = paying_setup();
    try {
        time.sleep(1.5);
        assert _resolve(app)["expired"] == 1;
        after = _overview(app, screening);
        assert after["orders"] == ["expired"] , after;
        assert after["seats"]["A1"] == "available"
            and after["seats"]["A2"] == "available";
        held = browse(
            app,
            "hold_seats",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": BEN,
                "labels": ["A1", "A2"]
            }
        );
        assert held["ok"] , held;
        assert _resolve(app)["expired"] == 0;
    } finally {
        _clear();
        app.close();
    }
}

test "an order past its time whose payment went through is confirmed, not expired" {
    _env({PAY_TIME: "2", STUCK: "3600"});
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening);
        time.sleep(2.5);
        result = _resolve(app);
        assert result["expired"] == 0 , result;
        after = _overview(app, screening);
        assert after["orders"] == ["confirmed"] , after;
        assert after["payments"] == [[reference, "success", ""]];
        assert after["tickets"] == ["A1", "A2"];
    } finally {
        _clear();
        app.close();
    }
}

test "an order past its time with an unanswered payment expires, and the payment fails" {
    _env({PAY_TIME: "2", STUCK: "3600"});
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening, "late_success");
        time.sleep(2.5);
        assert _resolve(app)["expired"] == 1;
        after = _overview(app, screening);
        assert after["orders"] == ["expired"] , after;
        assert after["payments"] == [[reference, "failed", ""]];
        assert after["seats"]["A1"] == "available" and after["tickets"] == [];
        mine = browse(
            app,
            "my_payment",
            {"slug": "nova", "screening_id": screening, "holder": ANNA}
        );
        assert "time to pay ran out" in mine["payment"]["message"] , mine;
    } finally {
        _clear();
        app.close();
    }
}

test "money that bought nothing balances to zero: a payment and a refund due" {
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening);
        forged = app.call(
            "owner",
            "pay_forged",
            {
                "slug": "nova",
                "screening_id": screening,
                "reference": reference,
                "code": 0,
                "cents": 100000,
                "receipt": "SHORT00002"
            }
        );
        app.client.set_auth_token("");
        resp = app.client.post(f"/hooks/mpesa/{forged['token']}", json=forged["body"]);
        assert resp.status_code == 200;
        app.call("owner", "pay_process");
        after = _overview(app, screening);
        assert after["ledger"]
            == [["payment", 100000], ["refund_due", -100000]] , after;
        assert after["balances"] == [["pending_payment", 186000, 0]];
        assert after["refunds"] == ["amount_mismatch"];
    } finally {
        _clear();
        app.close();
    }
}
