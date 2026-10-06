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
import from tests.support.served { Served, served }
import from tests.support.storefront_setup {
    Cinema,
    open_cinema_for,
    add_movie,
    add_screening,
    set_prices,
    browse,
    code_of
}

glob APP: str = path.join(
         path.dirname(path.dirname(path.abspath(__file__))), "apps", "payment_app.jac"
     ),
     PAYMENTS: str = "AFRICINEMAS_PAYMENTS",
     FAULTS: str = "AFRICINEMAS_FAULTS",
     ANNA: str = "holder-anna-0123456789abcdef";

def _setup -> tuple[Served, str] {  # jac:ignore[W1037]
    # A priced showtime where Anna holds A1 and A2 and has ordered them (KES 1,660).
    os.environ[PAYMENTS] = "simulator";
    app = served(APP, ["owner"]);
    nova = open_cinema_for(app, "owner", "nova", "Nova Cinemas");
    add_movie(app, "owner", nova, "Rafiki");
    set_prices(app, "owner", nova);
    screening = add_screening(app, "owner", nova, "Rafiki", 0);
    held = browse(
        app,
        "hold_seats",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "labels": ["A1", "A2"]
        }
    );
    assert held["ok"] , held;
    ordered = browse(
        app,
        "place_order",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [
                {"seat_label": "A1", "ticket_type": "ADULT"},
                {"seat_label": "A2", "ticket_type": "ADULT"}
            ]
        }
    );
    assert ordered["ok"] , ordered;
    return (app, screening);
}

def _pay(app: Served, screening: str, phone: str, key: str = "") -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "start_payment",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "phone": phone,
            "idempotency_key": key or f"pay-{uuid.uuid4().hex}"
        }
    );
}

def _pushes(app: Served, reference: str) -> int {
    return app.call("owner", "pay_push_count", {"reference": reference});
}

def _stored(app: Served, screening: str) -> list[list[str]] {
    return app.call("owner", "pay_stored", {"slug": "nova", "screening_id": screening});
}

def _phone -> str {
    # A fresh number per test: the simulator scripts outcomes by number.
    return f"2547{uuid.uuid4().int % 100000000:08d}";
}

test "paying sends one PIN prompt, and the payment waits for the PIN" {
    (app, screening) = _setup();
    try {
        local = "0" + _phone()[3:];
        started = _pay(app, screening, local);
        assert started["ok"] , started;
        payment = started["payment"];
        assert payment["state"] == "stk_requested";
        assert payment["amount_cents"] == 166000 and payment["currency"] == "KES";
        assert "*" in payment["phone"] and "PIN" in payment["message"];
        assert _pushes(app, payment["reference"]) == 1;
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
    (app, screening) = _setup();
    try {
        phone = _phone();
        first = _pay(app, screening, phone, "pay-key-anna-0000000001");
        again = _pay(app, screening, phone, "pay-key-anna-0000000001");
        assert again["ok"] and again["payment"] == first["payment"] , again;
        assert _pushes(app, first["payment"]["reference"]) == 1;
        other = _pay(app, screening, phone, "pay-key-anna-0000000002");
        assert code_of(other) == "payment_in_progress" , other;
        assert other["error"]["payment"]["reference"] == first["payment"]["reference"];
        changed = _pay(app, screening, _phone(), "pay-key-anna-0000000001");
        assert code_of(changed) == "key_reused";
        assert len(_stored(app, screening)) == 1;
    } finally {
        app.close();
    }
}

test "a replay before the payment commits still sends exactly one prompt" {
    (app, screening) = _setup();
    os.environ[FAULTS] = f"replay:payment_before_commit,nonce:{uuid.uuid4().hex}";
    try {
        started = _pay(app, screening, _phone());
        assert started["ok"]
            and started["payment"]["state"] == "stk_requested" , started;
        assert _pushes(app, started["payment"]["reference"]) == 1;
        assert len(_stored(app, screening)) == 1;
    } finally {
        os.environ.pop(FAULTS, None);
        app.close();
    }
}

test "a replay after the commit, before the prompt, still sends exactly one prompt" {
    (app, screening) = _setup();
    os.environ[FAULTS] = f"replay:payment_after_commit,nonce:{uuid.uuid4().hex}";
    try {
        started = _pay(app, screening, _phone());
        assert started["ok"]
            and started["payment"]["state"] == "stk_requested" , started;
        assert _pushes(app, started["payment"]["reference"]) == 1;
        assert _stored(app, screening)
            == [[started["payment"]["reference"], "stk_requested"]];
    } finally {
        os.environ.pop(FAULTS, None);
        app.close();
    }
}

test "a refused prompt fails the payment, and the visitor can try again" {
    (app, screening) = _setup();
    try {
        busy = _phone();
        app.call("owner", "pay_script", {"phone": busy, "outcome": "reject"});
        refused = _pay(app, screening, busy);
        assert refused["ok"] and refused["payment"]["state"] == "failed" , refused;
        assert "didn't go through" in refused["payment"]["message"];
        retried = _pay(app, screening, _phone());
        assert retried["ok"] and retried["payment"]["state"] == "stk_requested";
        assert [row[1] for row in _stored(app, screening)]
            == ["failed", "stk_requested"];
    } finally {
        app.close();
    }
}

test "bad numbers, missing orders, bad keys and switched-off payments are refused" {
    (app, screening) = _setup();
    try {
        assert code_of(_pay(app, screening, "0202345678")) == "invalid_phone";
        assert code_of(_pay(app, screening, _phone(), "short")) == "invalid_key";
        nobody = browse(
            app,
            "start_payment",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": "holder-ben-0123456789abcdefgh",
                "phone": _phone(),
                "idempotency_key": "pay-key-ben-00000000001"
            }
        );
        assert code_of(nobody) == "no_order";
        os.environ.pop(PAYMENTS, None);
        assert code_of(_pay(app, screening, _phone())) == "payments_unavailable";
        assert _stored(app, screening) == [];
    } finally {
        os.environ[PAYMENTS] = "simulator";
        app.close();
    }
}

test "an order whose time to pay is up can't be paid" {
    os.environ["AFRICINEMAS_PAY_SECONDS"] = "1";
    (app, screening) = _setup();
    try {
        time.sleep(1.5);
        assert code_of(_pay(app, screening, _phone())) == "order_expired";
    } finally {
        os.environ.pop("AFRICINEMAS_PAY_SECONDS", None);
        app.close();
    }
}
