"""P13.5c: a cinema's technical health, for AfriCinemas' support team.

In-process app (payment_app.jac) with the simulated M-Pesa. Nova starts healthy. A
payment that M-Pesa completes after the order stopped waiting needs attention, with a
refund due; five attempts in a row that fail make M-Pesa failures a problem, while one
cancelled prompt doesn't; a payment left waiting and seen half an hour later is stuck.
Each shows on the cinema's directory page, beside its help requests, and on the
overview, which names the cinemas with problems and leaves out healthy ones. Counts
only: no customer's phone, email or holder.
"""

import os;
import json;
import from tests.support.served { Served }
import from tests.support.storefront_setup { open_cinema_for }
import from tests.support.payment_setup {
    ANNA,
    ANNA_EMAIL,
    paying_cinema,
    pay,
    settle,
    fresh_phone
}
import from tests.support.platform_setup { ADMINS_ENV, super_admin }

glob CLOCK: str = "AFRICINEMAS_CLOCK_CONTROL",
     FAILING_PHONE: str = "254700000001",
     CANCELLING_PHONE: str = "254700000002";

def _app -> tuple[Served, str] {  # jac:ignore[W1037]
    os.environ[CLOCK] = "1";
    (app, _, screening) = paying_cinema(["rival"]);
    open_cinema_for(app, "rival", "rift", "Imax Rift");
    super_admin(app, "boss", "boss@example.com");
    return (app, screening);
}

def _close(app: Served) {
    app.call("owner", "rd_unfreeze");
    os.environ.pop(ADMINS_ENV, None);
    os.environ.pop(CLOCK, None);
    app.close();
}

def _health(app: Served, slug: str = "nova") -> dict[str, dict[str, any]] {  # jac:ignore[W1037]
    page = app.call("boss", "platform_cinema", {"slug": slug});
    assert page["ok"] , page;
    return {s["key"]: s for s in page["cinema"]["health"]["signals"]};
}

def _up(app: Served, slug: str = "nova") -> list[str] {
    return sorted(
        [
            k
            for (k, s) in _health(app, slug).items()
            if s["up"]
        ]
    );
}

def _started(app: Served, screening: str, phone: str) -> str {
    started = pay(app, screening, phone);
    assert started["ok"] , started;
    return started["payment"]["reference"];
}

test "a payment that needs attention, and its refund, are problems" {
    (app, screening) = _app();
    try {
        assert _up(app) == [] , _health(app);
        slow = fresh_phone();
        app.call("owner", "pay_script", {"phone": slow, "outcome": "late_success"});
        reference = _started(app, screening, slow);
        where = {"slug": "nova", "screening_id": screening, "reference": reference};
        app.call("owner", "pay_expire_order", where);
        app.call("owner", "pay_late", where);
        settle(app, screening, reference);
        health = _health(app);
        assert health["payments_attention"]["count"] == 1 , health;
        assert health["refunds_due"]["count"] == 1 , health;
        assert health["refunds_due"]["amount_cents"] == 186000 , health;
        assert _up(app) == ["payments_attention", "refunds_due"];
        # Another cinema's health knows nothing of it.
        assert _up(app, "rift") == [];
        # The overview names Nova, and only Nova.
        seen = app.call("boss", "platform_overview");
        assert [(c["slug"], c["problems"]) for c in seen["with_problems"]]
            == [("nova", 2)] , seen["with_problems"];
        # Counts only.
        shown = json.dumps(
            app.call("boss", "platform_cinema", {"slug": "nova"})["cinema"]["health"]
        );
        for private in [ANNA, ANNA_EMAIL, slow, reference] {
            assert private not in shown , private;
        }
    } finally {
        _close(app);
    }
}

test "M-Pesa failures are a problem only when most attempts fail" {
    (app, screening) = _app();
    try {
        cancelled = _started(app, screening, CANCELLING_PHONE);
        settle(app, screening, cancelled);
        health = _health(app);
        assert health["mpesa_failures"]["count"] == 0
            and not health["mpesa_failures"]["up"];
        for _ in range(5) {
            failed = _started(app, screening, FAILING_PHONE);
            settle(app, screening, failed);
        }
        health = _health(app);
        assert health["mpesa_failures"]["count"] == 5 , health;
        assert "Of 6 in the last 7 days" == health["mpesa_failures"]["note"] , health;
        assert health["mpesa_failures"]["up"];
    } finally {
        _close(app);
    }
}

test "a payment still waiting half an hour on is stuck, and shows beside the cinema's requests" {
    (app, screening) = _app();
    try {
        _started(app, screening, fresh_phone());
        assert not _health(app)["stuck"]["up"];
        # The cinema asks for help now, while its shift is open.
        asked = app.call(
            "owner",
            "ask_for_help",
            {"tenant": "nova", "category": "payments", "text": "A payment is stuck."}
        );
        assert asked["ok"] , asked;
        request_id = asked["request"]["request_id"];
        # Half an hour and more later (the showtime's start, two days on).
        app.call(
            "owner",
            "rd_freeze",
            {"slug": "nova", "screening_id": screening, "minutes": 0}
        );
        health = _health(app);
        assert health["stuck"]["count"] >= 1 and health["stuck"]["up"] , health;
        # Beside the help request, for our support team.
        seen = app.call("boss", "platform_support_request", {"request_id": request_id});
        assert "stuck"
            in [
                s["key"]
                for s in seen["health"]["signals"]
                if s["up"]
            ] , seen;
    } finally {
        _close(app);
    }
}
