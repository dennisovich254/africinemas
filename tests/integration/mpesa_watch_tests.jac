"""P16.3: is M-Pesa down? Safaricom's side, told apart from customers and cinemas.

In-process app (payment_app.jac), the simulated M-Pesa, the development outbox, the
clock frozen and moved. One cinema is enough (owner, 2026-10-30).
- Customers' failures (insufficient funds, cancelled, a phone that's off) and a
  cinema's keys refused never say M-Pesa is down; the keys show on the cinema's health.
- Three payments failing on Safaricom's side within 15 minutes (no answer, Daraja
  unreachable), at least half of the attempts, do: the overview says so with
  Safaricom's channels, and the team is emailed once; 15 minutes on, it clears.
- Asking Daraja ourselves: two checks in a row without an answer say it's down, with
  no payments at all; answering again clears it. Our own keys refused is its own alert.
"""

import os;
import uuid;
import tempfile;
import from datetime { datetime, timedelta, timezone }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, add_screening }
import from tests.support.payment_setup { paying_cinema, fresh_phone }
import from tests.support.platform_setup { ADMINS_ENV, super_admin }

glob BOSS: str = "boss@example.com",
     # The clock starts at the real time, so the showtimes (days ahead) stay ahead.
     START: datetime = datetime.now(timezone.utc).replace(microsecond=0);

def _try(app: Served, screening: str, seat: str, phone: str) {
    # A customer orders `seat` at Nova and pays from `phone`.
    holder = f"holder-{uuid.uuid4().hex}";
    where = {"slug": "nova", "screening_id": screening, "holder": holder};
    assert browse(app, "hold_seats", {** where, "labels": [seat]})["ok"];
    assert browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": seat, "ticket_type": "ADULT"}]
        }
    )["ok"];
    browse(
        app,
        "start_payment",
        {
            ** where,
            "phone": phone,
            "email": "customer@example.com",
            "idempotency_key": f"pay-{uuid.uuid4().hex}",
            "adult": "yes"
        }
    );
}

def _at(app: Served, minutes: int) {
    assert app.call(
        "owner", "t_clock_at", {"at": (START + timedelta(minutes=minutes)).isoformat()}
    );
}

def _alerts(app: Served) -> list[str] {
    return [
        m["subject"]
        for m in app.call("owner", "tm_outbox")
        if m["to"] == BOSS and "M-Pesa" in m["subject"]
    ];
}

test "Safaricom's side failing is told apart from customers and a cinema's keys" {
    os.environ["AFRICINEMAS_OUTBOX_DIR"] = tempfile.mkdtemp(
        prefix="africinemas-outbox-"
    );
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, _) = paying_cinema([]);
    try {
        super_admin(app, "boss", BOSS);
        app.call("owner", "tm_clear_outbox");
        _at(app, 0);
        show = add_screening(app, "owner", nova, "Rafiki", 24);
        # Customers' failures, and the cinema's keys refused: not M-Pesa being down.
        for (seat, phone) in [
            ("A1", "254700000001"),
            ("A2", "254700000002"),
            ("A3", "254700000003"),
            ("A4", "254700000007"),
            ("A5", "254700000007")
        ] {
            _try(app, show, seat, phone);
        }
        state = app.call("owner", "t_mpesa_state");
        assert state["attempts"] == 5 and state["failures"] == 0 , state;
        assert not state["likely_down"];
        assert app.call("owner", "t_check_mpesa") == 0;
        health = {
            s["key"]: s
            for s in app.call("boss", "platform_cinema", {"slug": "nova"})["cinema"][
                "health"
            ]["signals"]
        };
        assert health["mpesa_keys"]["up"] and health["mpesa_keys"]["count"] == 2;
        # Fifteen minutes on, three payments fail on Safaricom's side: likely down.
        _at(app, 20);
        later = add_screening(app, "owner", nova, "Rafiki", 48);
        for (seat, phone) in [
            ("A1", "254700000005"),
            ("A2", "254700000006"),
            ("A3", "254700000005"),
            ("A4", fresh_phone())
        ] {
            _try(app, later, seat, phone);
        }
        state = app.call("owner", "t_mpesa_state");
        assert state["failures"] == 3 and state["attempts"] == 4 , state;
        assert state["likely_down"] and state["why"] == ["payments"] , state;
        assert "x.com/SafaricomPLC" in state["links"][0][1];
        shown = app.call("boss", "platform_overview", {})["mpesa"];
        assert shown["likely_down"];
        assert app.call("owner", "t_check_mpesa") == 1;
        assert app.call("owner", "t_check_mpesa") == 0;
        assert _alerts(app) == ["AfriCinemas: M-Pesa is likely down"];
        # Fifteen minutes later those are old: it clears, with one more email.
        _at(app, 40);
        assert not app.call("owner", "t_mpesa_state")["likely_down"];
        assert app.call("owner", "t_check_mpesa") == 1;
        assert _alerts(app)[-1]
            == "AfriCinemas: M-Pesa payments are going through again";
        # No payments at all, and Daraja stops answering us: two checks in a row say so.
        assert app.call("owner", "t_sim_daraja", {"down": True, "keys_refused": False});
        _at(app, 45);
        assert app.call("owner", "t_check_mpesa") == 0;
        _at(app, 50);
        assert app.call("owner", "t_check_mpesa") == 1;
        state = app.call("owner", "t_mpesa_state");
        assert state["why"] == ["daraja"] and state["probe"]["result"] == "unreachable";
        assert _alerts(app)[-1] == "AfriCinemas: M-Pesa is likely down";
        # Answering again clears it.
        assert app.call(
            "owner", "t_sim_daraja", {"down": False, "keys_refused": False}
        );
        _at(app, 55);
        assert app.call("owner", "t_check_mpesa") == 1;
        assert not app.call("owner", "t_mpesa_state")["likely_down"];
        # Our own keys refused: its own alert, never "M-Pesa is down".
        assert app.call("owner", "t_sim_daraja", {"down": False, "keys_refused": True});
        _at(app, 60);
        assert app.call("owner", "t_check_mpesa") == 1;
        state = app.call("owner", "t_mpesa_state");
        assert state["our_keys_refused"] and not state["likely_down"];
        assert _alerts(app)[-1] == "AfriCinemas: M-Pesa refused our own keys";
        assert app.call(
            "owner", "t_sim_daraja", {"down": False, "keys_refused": False}
        );
        _at(app, 65);
        assert app.call("owner", "t_check_mpesa") == 1;
        assert _alerts(app)[-1] == "AfriCinemas: M-Pesa accepts our keys again";
    } finally {
        app.call("owner", "t_sim_daraja", {"down": False, "keys_refused": False});
        app.call("owner", "t_clock_reset");
        for name in [
            "AFRICINEMAS_OUTBOX_DIR",
            "AFRICINEMAS_CLOCK_CONTROL",
            ADMINS_ENV
        ] {
            os.environ.pop(name, None);
        }
        app.close();
    }
}
