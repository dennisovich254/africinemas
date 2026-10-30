"""P16.3: M-Pesa failing across most cinemas is likely Safaricom; at one, it isn't.

In-process app (payment_app.jac), the simulated M-Pesa, the development outbox. Each
cinema's payment uses a phone number the simulator refuses (254700000004: the prompt
isn't sent), or one that goes through.
- One cinema failing, the others fine: not M-Pesa; no alert.
- Most cinemas failing: likely M-Pesa; the overview says so with Safaricom's channels,
  and the team is emailed once; when payments go through again it clears, with one
  more email. Counts only.
- Failures more than an hour old don't count.
"""

import os;
import uuid;
import tempfile;
import from datetime { datetime, timedelta }
import from tests.support.served { Served }
import from tests.support.storefront_setup {
    browse,
    open_cinema_for,
    add_movie,
    set_prices,
    add_screening
}
import from tests.support.payment_setup { paying_cinema, fresh_phone }
import from tests.support.platform_setup { ADMINS_ENV, super_admin }

glob BOSS: str = "boss@example.com",
     REFUSED: str = "254700000004";

def _cinema(app: Served, slug: str) -> str {
    # Another cinema selling one showtime of Rafiki; its showtime.
    cinema = open_cinema_for(app, "owner", slug, f"Cinema {slug}");
    add_movie(app, "owner", cinema, "Rafiki");
    set_prices(app, "owner", cinema);
    return add_screening(app, "owner", cinema, "Rafiki", 0);
}

def _try(app: Served, slug: str, screening: str, seat: str, phone: str) {
    # A customer orders `seat` and pays from `phone`.
    holder = f"holder-{uuid.uuid4().hex}";
    where = {"slug": slug, "screening_id": screening, "holder": holder};
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
    started = browse(
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
    assert started["ok"] or phone == REFUSED , started;
}

def _alerts(app: Served) -> list[str] {
    return [
        m["subject"]
        for m in app.call("owner", "tm_outbox")
        if m["to"] == BOSS and "M-Pesa" in m["subject"]
    ];
}

test "M-Pesa failing at most cinemas is flagged as Safaricom, and at one it isn't" {
    os.environ["AFRICINEMAS_OUTBOX_DIR"] = tempfile.mkdtemp(
        prefix="africinemas-outbox-"
    );
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, _, _) = paying_cinema([]);
    try {
        super_admin(app, "boss", BOSS);
        app.call("owner", "tm_clear_outbox");
        shows = {
            slug: _cinema(app, slug) for slug in ["mtaa", "pwani", "ziwa", "rafu"]
        };
        # One cinema failing, the others fine: that cinema's problem, not M-Pesa's.
        for seat in ["A1", "A2"] {
            _try(app, "mtaa", shows["mtaa"], seat, REFUSED);
        }
        for slug in ["pwani", "ziwa", "rafu"] {
            _try(app, slug, shows[slug], "A1", fresh_phone());
            _try(app, slug, shows[slug], "A2", fresh_phone());
        }
        state = app.call("owner", "t_mpesa_state");
        assert state["trying"] == 4 and state["failing"] == 1 , state;
        assert not state["likely_down"];
        assert app.call("owner", "t_check_mpesa") == 0;
        # Most cinemas failing: likely M-Pesa.
        for slug in ["pwani", "ziwa"] {
            for seat in ["A3", "A4", "A5"] {
                _try(app, slug, shows[slug], seat, REFUSED);
            }
        }
        state = app.call("owner", "t_mpesa_state");
        assert state["failing"] == 3 and state["likely_down"] , state;
        assert len(state["links"]) == 3
            and "x.com/SafaricomPLC" in state["links"][0][1];
        assert "phone" not in str(state) and REFUSED not in str(state);
        shown = app.call("boss", "platform_overview", {})["mpesa"];
        assert shown["likely_down"] and shown["failing"] == 3;
        assert app.call("owner", "t_check_mpesa") == 1;
        assert app.call("owner", "t_check_mpesa") == 0;
        assert _alerts(app) == ["AfriCinemas: M-Pesa is likely down"];
        # An hour on, those failures are old: back to normal, and the team hears once.
        start = datetime.fromisoformat(state["since"]) + timedelta(minutes=60);
        assert app.call(
            "owner", "t_clock_at", {"at": (start + timedelta(minutes=61)).isoformat()}
        );
        assert not app.call("owner", "t_mpesa_state")["likely_down"];
        assert app.call("owner", "t_check_mpesa") == 1;
        assert _alerts(app)[-1]
            == "AfriCinemas: M-Pesa payments are going through again";
    } finally {
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
