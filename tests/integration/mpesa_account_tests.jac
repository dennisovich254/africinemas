"""P15.3: each cinema's own M-Pesa.

In-process app (payment_app.jac, the simulated M-Pesa). Kim's Cinema is verified by
AfriCinemas (P14.5), registered as "Kim's Cinema Ltd".
- Only a verified cinema connects, with the verified business's name, valid keys and
  the owner's password again; no answer ever carries a key.
- A KES 1 test payment must go through before the account is used; then customers'
  payments go to the cinema's own paybill (the simulator records where each went).
- A change is emailed to the owners and waits 24 hours, while payments keep going to
  the account in use; it can be cancelled before then.
- Where each cinema must use its own M-Pesa, a cinema that hasn't connected can't take
  M-Pesa payments.
"""

import os;
import uuid;
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
import from tests.support.payment_setup { APP, ANNA, fresh_phone }
import from tests.support.platform_setup { super_admin }
import from tests.support.verification_setup {
    KIM,
    PASSWORD,
    sign_up_with_email,
    confirm_kim,
    submitted,
    close_app
}

glob KEYS: dict[str, str] = {
         # Made-up keys, built so no secret-looking text is in the source.
         "consumer_key": "k" * 16 + "WXYZ",
         "consumer_secret": "s" * 24,
         "passkey": "p" * 64
     },
     PAYBILL: dict[str, any] = {  # jac:ignore[W1037]
         "tenant": "kims",
         "kind": "paybill",
         "shortcode": "600100",
         "till_number": "",
         "registered_name": "KIM'S CINEMA LIMITED",
         "keys": KEYS,
         "password": PASSWORD,
         "sign_in": KIM
     };

def _app -> tuple[Served, str] {  # jac:ignore[W1037]
    # Kim's verified cinema with a published showtime; Rift (rival's) isn't verified.
    os.environ["AFRICINEMAS_PAYMENTS"] = "simulator";
    os.environ.setdefault("AFRICINEMAS_TICKET_KEY", "test" * 10);
    os.environ["AFRICINEMAS_MPESA_KEY"] = "mpesa-test-sealing-key-0123456789abcdef";
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    os.environ["AFRICINEMAS_OUTBOX_DIR"] = os.path.join(
        "/tmp", f"africinemas-outbox-{uuid.uuid4().hex}"
    );
    os.environ.pop("AFRICINEMAS_SMTP_HOST", None);
    app = served(APP, ["owner", "rival"]);
    sign_up_with_email(app, "kim", KIM);
    confirm_kim(app);
    kims: Cinema = open_cinema_for(
        app, "kim", "kims", "Kim's Cinema", live=False, email=KIM
    );
    set_prices(app, "kim", kims);
    submitted(app);
    super_admin(app, "boss", "boss@example.com");
    approved = app.call(
        "boss",
        "platform_decide",
        {"slug": "kims", "decision": "approve", "reasons": []}
    );
    assert approved["ok"] , approved;
    add_movie(app, "kim", kims, "Rafiki");
    screening = add_screening(app, "kim", kims, "Rafiki", 0);
    app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
    app.call("rival", "start_shift", {"tenant": "rift"});
    return (app, screening);
}

def _done(app: Served) {
    app.call("owner", "t_clock_reset");
    for name in ["AFRICINEMAS_CLOCK_CONTROL", "AFRICINEMAS_OWN_MPESA"] {
        os.environ.pop(name, None);
    }
    close_app(app);
}

def _connected(app: Served, body: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # Kim connects `body` and its KES 1 test payment goes through.
    made = app.call("kim", "connect_mpesa", body);
    assert made["ok"] and made["pending"]["state"] == "testing" , made;
    assert app.call("kim", "test_mpesa", {"tenant": "kims", "phone": "0712345678"})[
        "ok"
    ];
    return app.call("kim", "mpesa_test_status", {"tenant": "kims"});
}

def _order(app: Served, screening: str, holder: str, seat: str) {
    held = browse(
        app,
        "hold_seats",
        {"slug": "kims", "screening_id": screening, "holder": holder, "labels": [seat]}
    );
    assert held["ok"] , held;
    ordered = browse(
        app,
        "place_order",
        {
            "slug": "kims",
            "screening_id": screening,
            "holder": holder,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": seat, "ticket_type": "ADULT"}]
        }
    );
    assert ordered["ok"] , ordered;
}

def _pay(app: Served, screening: str, holder: str) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "start_payment",
        {
            "slug": "kims",
            "screening_id": screening,
            "holder": holder,
            "phone": fresh_phone(),
            "email": "anna@example.com",
            "idempotency_key": f"pay-{uuid.uuid4().hex}"
        }
    );
}

def _paid_to(app: Served, screening: str, seat: str) -> str {
    # A new visitor orders `seat` and starts paying: the paybill or till her payment
    # went to.
    holder = f"holder-{uuid.uuid4().hex}";
    _order(app, screening, holder, seat);
    started = _pay(app, screening, holder);
    assert started["ok"] , started;
    return app.call(
        "owner", "pay_paid_to", {"reference": started["payment"]["reference"]}
    );
}

def _no_keys(answer: any) -> bool {  # jac:ignore[W1037]
    text = str(answer);
    return all([value not in text for value in KEYS.values()]);
}

test "only a verified cinema connects, as the verified business, with the password" {
    (app, _) = _app();
    try {
        rift = {** PAYBILL, "tenant": "rift"};
        assert code_of(app.call("rival", "connect_mpesa", rift)) == "not_verified";
        assert code_of(
            app.call(
                "kim", "connect_mpesa", {** PAYBILL, "registered_name": "Other Ltd"}
            )
        )
            == "name_mismatch";
        assert code_of(
            app.call("kim", "connect_mpesa", {** PAYBILL, "password": "wrong-one"})
        )
            == "wrong_password";
        assert code_of(
            app.call(
                "kim",
                "connect_mpesa",
                {** PAYBILL, "keys": {** KEYS, "passkey": "has spaces in it"}}
            )
        )
            == "invalid_keys";
        assert code_of(app.call("kim", "connect_mpesa", {** PAYBILL, "kind": "till"}))
            == "invalid_till";
        # Without the server's sealing key, no keys are kept at all.
        sealing = os.environ.pop("AFRICINEMAS_MPESA_KEY");
        assert code_of(app.call("kim", "connect_mpesa", PAYBILL)) == "not_ready";
        os.environ["AFRICINEMAS_MPESA_KEY"] = sealing;
        # Rift's owner can't see or change Kim's.
        assert code_of(app.call("rival", "mpesa_settings", {"tenant": "kims"}))
            == "not_found";
        nothing = app.call("kim", "mpesa_settings", {"tenant": "kims"});
        assert nothing["active"] is None and nothing["pending"] is None;
        assert nothing["may_change"] and nothing["blocked"] == "";
    } finally {
        _done(app);
    }
}

test "the test payment comes first, then payments go to the cinema's own paybill" {
    (app, screening) = _app();
    try {
        made = app.call("kim", "connect_mpesa", PAYBILL);
        assert made["ok"] and _no_keys(made) , made;
        assert made["pending"]["key_hint"] == "WXYZ";
        # Until its test payment goes through, payments don't use it.
        assert _paid_to(app, screening, "A1") == "";
        assert app.call("kim", "test_mpesa", {"tenant": "kims", "phone": "0700000001"})[
            "ok"
        ];
        failed = app.call("kim", "mpesa_test_status", {"tenant": "kims"});
        assert failed["pending"]["state"] == "testing"
            and "didn't go through" in failed["pending"]["test_text"] , failed;
        assert app.call("kim", "test_mpesa", {"tenant": "kims", "phone": "0712345678"})[
            "ok"
        ];
        passed = app.call("kim", "mpesa_test_status", {"tenant": "kims"});
        assert passed["pending"] is None , passed;
        assert passed["active"]["pays_to"] == "600100" and passed["active"]["in_use"];
        assert _no_keys(passed);
        assert _paid_to(app, screening, "A2") == "600100";
        assert app.call("owner", "t_send_mpesa_mail") == 1;
        mails = [
            m
            for m in app.call("owner", "tm_outbox")
            if m["to"] == KIM
        ];
        assert "M-Pesa is being connected" in mails[-1]["subject"] , mails;
        assert "600100" in mails[-1]["text"] and _no_keys(mails);
    } finally {
        _done(app);
    }
}

test "a change is emailed and waits 24 hours, and can be cancelled before then" {
    (app, screening) = _app();
    try {
        _connected(app, PAYBILL);
        app.call("owner", "t_send_mpesa_mail");
        app.call("owner", "tm_clear_outbox");
        till = {
            ** PAYBILL,
            "kind": "till",
            "shortcode": "700200",
            "till_number": "800300"
        };
        waiting = _connected(app, till);
        assert waiting["active"]["pays_to"] == "600100" , waiting;
        assert waiting["pending"]["state"] == "ready"
            and waiting["pending"]["is_change"]
            and not waiting["pending"]["in_use"];
        assert app.call("owner", "t_send_mpesa_mail") == 1;
        mails = app.call("owner", "tm_outbox");
        assert "being changed" in mails[-1]["subject"] , mails;
        assert "800300" in mails[-1]["text"] and "24 hours" in mails[-1]["text"];
        assert _paid_to(app, screening, "A1") == "600100";
        app.call("owner", "t_clock_ahead", {"hours": 25});
        moved = app.call("kim", "mpesa_settings", {"tenant": "kims"});
        assert moved["active"]["pays_to"] == "800300" and moved["pending"] is None;
        assert _paid_to(app, screening, "A2") == "800300";
        # A change asked for and cancelled changes nothing.
        assert app.call("kim", "connect_mpesa", PAYBILL)["ok"];
        cancelled = app.call(
            "kim", "cancel_mpesa_change", {"tenant": "kims", "sign_in": KIM}
        );
        assert cancelled["pending"] is None
            and cancelled["active"]["pays_to"] == "800300" , cancelled;
    } finally {
        _done(app);
    }
}

test "where cinemas must use their own M-Pesa, one not connected can't take it" {
    (app, screening) = _app();
    try {
        os.environ["AFRICINEMAS_OWN_MPESA"] = "required";
        _order(app, screening, ANNA, "A1");
        assert code_of(_pay(app, screening, ANNA)) == "mpesa_not_connected";
        _connected(app, PAYBILL);
        assert _pay(app, screening, ANNA)["ok"];
    } finally {
        _done(app);
    }
}
