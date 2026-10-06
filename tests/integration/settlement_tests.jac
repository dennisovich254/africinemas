"""P5.4: Safaricom's callback, and settling payments from M-Pesa's own answer.

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa. The callback
(POST /hooks/mpesa/{token}) only files a receipt; settling asks M-Pesa (the status
query) and only then marks the payment paid, the order confirmed, the seats sold and
one ticket per seat issued, in one commit. Three duplicate callbacks make one ticket
set; a callback that M-Pesa contradicts changes nothing it claims; a wrong amount or a
success after the order stopped waiting needs attention, with a refund task.
"""

import os;
import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { ANNA, paying_setup, pay, fresh_phone }

def _started(app: Served, screening: str, phone: str = "") -> str {
    # Anna starts paying; returns the payment's reference.
    started = pay(app, screening, phone or fresh_phone());
    assert started["ok"] and started["payment"]["state"] == "stk_requested" , started;
    return started["payment"]["reference"];
}

def _post(app: Served, token: str, body: any) -> any {  # jac:ignore[W1037]
    # Safaricom calling us: no login, the raw callback body.
    app.client.set_auth_token("");
    resp = app.client.post(f"/hooks/mpesa/{token}", json=body);
    assert resp.status_code == 200 , resp.text;
    return resp;
}

def _callback(app: Served, screening: str, reference: str) -> dict[str, any] {  # jac:ignore[W1037]
    return app.call(
        "owner",
        "pay_callback",
        {"slug": "nova", "screening_id": screening, "reference": reference}
    );
}

def _deliver(app: Served, screening: str, reference: str, times: int = 1) {
    sent = _callback(app, screening, reference);
    assert sent["body"] is not None , sent;
    for _ in range(times) {
        _post(app, sent["token"], sent["body"]);
    }
}

def _overview(app: Served, screening: str) -> dict[str, any] {  # jac:ignore[W1037]
    return app.call(
        "owner", "pay_overview", {"slug": "nova", "screening_id": screening}
    );
}

def _mine(app: Served, screening: str) -> any {  # jac:ignore[W1037]
    return browse(
        app, "my_payment", {"slug": "nova", "screening_id": screening, "holder": ANNA}
    );
}

test "a callback only files a receipt; settling confirms with M-Pesa and issues tickets" {
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening);
        _deliver(app, screening, reference);
        before = _overview(app, screening);
        assert before["payments"] == [[reference, "stk_requested", ""]] , before;
        assert before["tickets"] == [] and before["orders"] == ["pending_payment"];
        assert app.call("owner", "pay_process") == 1;
        after = _overview(app, screening);
        assert after["payments"] == [[reference, "success", ""]] , after;
        assert after["orders"] == ["confirmed"];
        assert after["tickets"] == ["A1", "A2"];
        assert after["seats"]["A1"] == "sold" and after["seats"]["A2"] == "sold";
        mine = _mine(app, screening)["payment"];
        assert mine["state"] == "success" and len(mine["tickets"]) == 2;
        assert mine["tickets"][0]["seat_label"] == "A1"
            and mine["tickets"][0]["reference"];
        seats = browse(
            app, "public_seat_availability", {"slug": "nova", "screening_id": screening}
        )["seats"];
        assert {s["label"]: s["state"] for s in seats}["A1"] == "sold";
    } finally {
        app.close();
    }
}

test "three duplicate callbacks, settled again and again, make one ticket set" {
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening);
        _deliver(app, screening, reference, times=3);
        app.call("owner", "pay_process");
        app.call("owner", "pay_process");
        _mine(app, screening);
        _deliver(app, screening, reference);
        app.call("owner", "pay_process");
        after = _overview(app, screening);
        assert after["tickets"] == ["A1", "A2"] , after;
        assert after["payments"] == [[reference, "success", ""]];
        assert after["refunds"] == [];
    } finally {
        app.close();
    }
}

test "the visitor's own status check settles a filed receipt without the job" {
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening);
        assert _mine(app, screening)["payment"]["state"] == "stk_requested";
        _deliver(app, screening, reference);
        mine = _mine(app, screening)["payment"];
        assert mine["state"] == "success" and len(mine["tickets"]) == 2 , mine;
    } finally {
        app.close();
    }
}

test "a callback claiming success that M-Pesa contradicts changes nothing it claims" {
    (app, screening) = paying_setup();
    try {
        broke = fresh_phone();
        app.call("owner", "pay_script", {"phone": broke, "outcome": "fail"});
        reference = _started(app, screening, broke);
        forged = app.call(
            "owner",
            "pay_forged",
            {
                "slug": "nova",
                "screening_id": screening,
                "reference": reference,
                "code": 0,
                "cents": 186000,
                "receipt": "FORGED0001"
            }
        );
        _post(app, forged["token"], forged["body"]);
        app.call("owner", "pay_process");
        after = _overview(app, screening);
        assert after["payments"] == [[reference, "failed", ""]] , after;
        assert after["tickets"] == [] and after["orders"] == ["pending_payment"];
        assert after["seats"]["A1"] == "payment_pending";
        # The order is free for another attempt.
        assert _started(app, screening) != reference;
    } finally {
        app.close();
    }
}

test "a cancelled prompt cancels the payment, and the visitor can pay again" {
    (app, screening) = paying_setup();
    try {
        changed_mind = fresh_phone();
        app.call("owner", "pay_script", {"phone": changed_mind, "outcome": "cancel"});
        reference = _started(app, screening, changed_mind);
        _deliver(app, screening, reference);
        assert _mine(app, screening)["payment"]["state"] == "cancelled";
        again = _started(app, screening);
        _deliver(app, screening, again);
        assert _mine(app, screening)["payment"]["state"] == "success";
        assert _overview(app, screening)["tickets"] == ["A1", "A2"];
    } finally {
        app.close();
    }
}

test "a paid amount that differs needs attention, with a refund task and no tickets" {
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
                "cents": 100,
                "receipt": "SHORT00001"
            }
        );
        _post(app, forged["token"], forged["body"]);
        app.call("owner", "pay_process");
        after = _overview(app, screening);
        assert after["payments"]
            == [[reference, "needs_attention", "amount_mismatch"]] , after;
        assert after["refunds"] == ["amount_mismatch"] and after["tickets"] == [];
        assert "cinema will be in touch" in _mine(app, screening)["payment"]["message"];
    } finally {
        app.close();
    }
}

test "a success after the order stopped waiting needs attention, with a refund task" {
    (app, screening) = paying_setup();
    try {
        slow = fresh_phone();
        app.call("owner", "pay_script", {"phone": slow, "outcome": "late_success"});
        reference = _started(app, screening, slow);
        where = {"slug": "nova", "screening_id": screening, "reference": reference};
        app.call("owner", "pay_expire_order", where);
        app.call("owner", "pay_late", where);
        _deliver(app, screening, reference);
        app.call("owner", "pay_process");
        after = _overview(app, screening);
        assert after["payments"]
            == [[reference, "needs_attention", "late_success"]] , after;
        assert after["refunds"] == ["late_success"] and after["tickets"] == [];
        assert after["seats"]["A1"] != "sold";
    } finally {
        app.close();
    }
}

test "a callback for an unknown payment, or that isn't one, is acknowledged and ignored" {
    (app, screening) = paying_setup();
    try {
        reference = _started(app, screening);
        resp = _post(
            app,
            f"unknown-{uuid.uuid4().hex}",
            {"Body": {"stkCallback": {"ResultCode": 0}}}
        );
        assert "ResultCode" in resp.text;
        sent = _callback(app, screening, reference);
        _post(app, sent["token"], {"Body": {"nonsense": True}});
        assert app.call("owner", "pay_process") == 0;
        assert _overview(app, screening)["payments"]
            == [[reference, "stk_requested", ""]];
    } finally {
        app.close();
    }
}
