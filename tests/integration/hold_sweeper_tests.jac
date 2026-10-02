"""P4.4: the hold expiry sweeper (in-process app: tests/apps/sweeper_app.jac).

Holds lapse by themselves on every read (P4.2), so the sweeper is housekeeping: it marks
a hold whose time is up as expired, frees its seats' slots and deletes the lapsed seat
claims. Every server copy runs it, so running it again must change nothing. It never
touches a paying hold (PAYMENT_PENDING), and it never frees a seat that a newer hold has
since taken. The scheduled run itself needs a served process; see
hold_sweeper_schedule_tests.jac.
"""

import os;
import time;
import from os { path }
import from tests.support.served { Served, served }
import from tests.support.storefront_setup {
    open_cinema_for,
    add_movie,
    add_screening,
    browse
}

glob APP: str = path.join(
         path.dirname(path.dirname(path.abspath(__file__))), "apps", "sweeper_app.jac"
     ),
     HOLD_ENV: str = "AFRICINEMAS_HOLD_SECONDS",
     ANNA: str = "holder-anna-0123456789abcdef",
     BEN: str = "holder-ben-0123456789abcdefgh";

def _setup -> tuple[Served, str] {  # jac:ignore[W1037]
    app = served(APP, ["owner"]);
    nova = open_cinema_for(app, "owner", "nova", "Nova Cinemas");
    add_movie(app, "owner", nova, "Rafiki");
    return (app, add_screening(app, "owner", nova, "Rafiki", 0));
}

def _hold(
    app: Served, screening: str, holder: str, labels: list[str], seconds: int
) -> any {  # jac:ignore[W1037]
    os.environ[HOLD_ENV] = str(seconds);
    try {
        return browse(
            app,
            "hold_seats",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": holder,
                "labels": labels
            }
        );
    } finally {
        os.environ.pop(HOLD_ENV, None);
    }
}

def _stored(app: Served, screening: str) -> dict[str, any] {  # jac:ignore[W1037]
    return app.call("owner", "sw_stored", {"slug": "nova", "screening_id": screening});
}

def _claim(app: Served, screening: str, label: str) -> str | None {
    return app.call(
        "owner", "sw_seat_claim", {"screening_id": screening, "label": label}
    );
}

test "a lapsed hold is expired and its seats freed; running the sweep again changes nothing" {
    (app, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1", "A2"], 1)["ok"];
        assert _hold(app, screening, BEN, ["A3"], 600)["ok"];
        time.sleep(2.2);
        assert app.call("owner", "sw_sweep")["expired"] == 1;
        after = _stored(app, screening);
        assert after["slots"]
            == {
                "A1": "available",
                "A2": "available",
                "A3": "held",
                "A4": "available",
                "A5": "available"
            } , after;
        assert after["holds"] == [[ANNA, "expired"], [BEN, "held"]] , after;
        assert _claim(app, screening, "A1") is None;
        assert _claim(app, screening, "A3") == BEN;
        assert app.call("owner", "sw_open_holds") == 1;
        # Another server copy sweeping too: nothing left to do.
        assert app.call("owner", "sw_sweep")["expired"] == 0;
        assert _stored(app, screening) == after;
        assert _claim(app, screening, "A3") == BEN;
    } finally {
        app.close();
    }
}

test "a paying hold is never released, however late" {
    (app, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1"], 1)["ok"];
        assert app.call(
            "owner",
            "sw_pay",
            {"slug": "nova", "screening_id": screening, "holder_id": ANNA}
        );
        time.sleep(2.2);
        for _ in range(2) {
            assert app.call("owner", "sw_sweep")["expired"] == 0;
            stored = _stored(app, screening);
            assert stored["slots"]["A1"] == "payment_pending" , stored;
            assert stored["holds"] == [[ANNA, "held"]] , stored;
            assert app.call("owner", "sw_open_holds") == 1;
        }
    } finally {
        app.close();
    }
}

test "a seat taken again after a hold lapsed stays with its new hold" {
    (app, screening) = _setup();
    try {
        # Anna's hold lapses; she holds the same seat again (a new hold), and Ben takes
        # the other seat she had.
        assert _hold(app, screening, ANNA, ["A1", "A2"], 1)["ok"];
        time.sleep(2.2);
        assert _hold(app, screening, ANNA, ["A1"], 600)["ok"];
        assert _hold(app, screening, BEN, ["A2"], 600)["ok"];
        assert app.call("owner", "sw_sweep")["expired"] == 1;
        stored = _stored(app, screening);
        assert stored["slots"]["A1"] == "held"
            and stored["slots"]["A2"] == "held" , stored;
        assert stored["holds"]
            == [[ANNA, "expired"], [ANNA, "held"], [BEN, "held"]] , stored;
        assert _claim(app, screening, "A1") == ANNA;
        assert _claim(app, screening, "A2") == BEN;
    } finally {
        app.close();
    }
}

test "a released hold leaves the list of open holds and its seats stay free" {
    (app, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1"], 600)["ok"];
        assert app.call("owner", "sw_open_holds") == 1;
        assert browse(
            app,
            "release_hold",
            {"slug": "nova", "screening_id": screening, "holder": ANNA}
        )["ok"];
        assert app.call("owner", "sw_sweep")["expired"] == 0;
        assert app.call("owner", "sw_open_holds") == 0;
        assert _stored(app, screening)["slots"]["A1"] == "available";
    } finally {
        app.close();
    }
}
