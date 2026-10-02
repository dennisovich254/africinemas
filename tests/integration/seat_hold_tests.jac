"""P4.3: seat holds, through the production app (main.jac).

A visitor (no login, ADR-0010) holds seats of a showtime for a few minutes while they
check out. The browser names the visitor with a random holder id it keeps for the visit;
a hold is one per (showtime, holder). Each seat is an atomic claim (ADR-0007), so a seat
is held by one holder at most, and a request either holds all its seats or none.
Holding again replaces the holder's seats; a hold can be extended up to a limit, and
released. A hold whose time is up lapses: its seats are available again.
"""

import os;
import time;
import from os { path }
import from tests.support.served { Served, served }
import from tests.support.storefront_setup {
    Cinema,
    open_cinema_for,
    add_movie,
    add_screening,
    browse,
    code_of
}

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     HOLD_ENV: str = "AFRICINEMAS_HOLD_SECONDS",
     ANNA: str = "holder-anna-0123456789abcdef",
     BEN: str = "holder-ben-0123456789abcdefgh";

def _setup -> tuple[Served, Cinema, str] {  # jac:ignore[W1037]
    app = served(MAIN, ["owner"]);
    nova = open_cinema_for(app, "owner", "nova", "Nova Cinemas");
    add_movie(app, "owner", nova, "Rafiki");
    return (app, nova, add_screening(app, "owner", nova, "Rafiki", 0));
}

def _hold(app: Served, screening: str, holder: str, labels: list[str]) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "hold_seats",
        {"slug": "nova", "screening_id": screening, "holder": holder, "labels": labels}
    );
}

def _call(app: Served, name: str, screening: str, holder: str) -> any {  # jac:ignore[W1037]
    return browse(
        app, name, {"slug": "nova", "screening_id": screening, "holder": holder}
    );
}

def _states(app: Served, screening: str) -> dict[str, str] {
    seats = browse(
        app, "public_seat_availability", {"slug": "nova", "screening_id": screening}
    )["seats"];
    return {s["label"]: s["state"] for s in seats};
}

test "a visitor holds seats, others see them held, and the visitor sees their hold" {
    (app, nova, screening) = _setup();
    try {
        held = _hold(app, screening, ANNA, ["A1", "A2"]);
        assert held["ok"] , held;
        assert held["hold"]["seats"] == ["A1", "A2"];
        assert held["hold"]["expires_at"];
        assert _states(app, screening)
            == {
                "A1": "held",
                "A2": "held",
                "A3": "available",
                "A4": "available",
                "A5": "available"
            };
        mine = _call(app, "my_hold", screening, ANNA);
        assert mine["ok"] and mine["hold"]["seats"] == ["A1", "A2"] , mine;
        assert code_of(_call(app, "my_hold", screening, BEN)) == "no_hold";
    } finally {
        app.close();
    }
}

test "a seat held by someone else can't be held, and a request never holds part of its seats" {
    (app, nova, screening) = _setup();
    try {
        _hold(app, screening, ANNA, ["A1", "A2"]);
        refused = _hold(app, screening, BEN, ["A2", "A3"]);
        assert code_of(refused) == "seats_taken" , refused;
        assert refused["error"]["seats"] == ["A2"];
        # A3 wasn't left held by the refused request.
        assert _states(app, screening)["A3"] == "available";
        assert _hold(app, screening, BEN, ["A3"])["ok"];
    } finally {
        app.close();
    }
}

test "holding again replaces the holder's seats, up to the per-visitor limit" {
    (app, nova, screening) = _setup();
    try {
        _hold(app, screening, ANNA, ["A1", "A2"]);
        again = _hold(app, screening, ANNA, ["A2", "A3"]);
        assert again["ok"] and again["hold"]["seats"] == ["A2", "A3"] , again;
        states = _states(app, screening);
        assert states["A1"] == "available" and states["A3"] == "held";
        many = [f"A{i}" for i in range(1, 12)];
        assert code_of(_hold(app, screening, ANNA, many)) == "too_many_seats";
        assert code_of(_hold(app, screening, ANNA, [])) == "no_seats";
    } finally {
        app.close();
    }
}

test "a hold can be released, freeing its seats" {
    (app, nova, screening) = _setup();
    try {
        _hold(app, screening, ANNA, ["A1"]);
        assert _call(app, "release_hold", screening, ANNA)["ok"];
        assert _states(app, screening)["A1"] == "available";
        assert code_of(_call(app, "my_hold", screening, ANNA)) == "no_hold";
        assert _hold(app, screening, BEN, ["A1"])["ok"];
    } finally {
        app.close();
    }
}

test "a hold can be extended, but not beyond its limit" {
    os.environ[HOLD_ENV] = "60";
    os.environ["AFRICINEMAS_HOLD_MAX_SECONDS"] = "90";
    (app, nova, screening) = _setup();
    try {
        first = _hold(app, screening, ANNA, ["A1"])["hold"]["expires_at"];
        time.sleep(1.1);
        extended = _call(app, "extend_hold", screening, ANNA);
        assert extended["ok"] and extended["hold"]["expires_at"] > first , extended;
        # Already past half the limit: another full extension would exceed it, so it
        # stops at the limit instead.
        capped = _call(app, "extend_hold", screening, ANNA);
        assert capped["ok"] , capped;
        assert code_of(_call(app, "extend_hold", screening, BEN)) == "no_hold";
    } finally {
        os.environ.pop(HOLD_ENV, None);
        os.environ.pop("AFRICINEMAS_HOLD_MAX_SECONDS", None);
        app.close();
    }
}

test "a hold whose time is up lapses, and its seats can be held by someone else" {
    os.environ[HOLD_ENV] = "1";
    (app, nova, screening) = _setup();
    try {
        assert _hold(app, screening, ANNA, ["A1"])["ok"];
        time.sleep(2.2);
        assert _states(app, screening)["A1"] == "available";
        assert code_of(_call(app, "my_hold", screening, ANNA)) == "no_hold";
        assert _hold(app, screening, BEN, ["A1"])["ok"];
    } finally {
        os.environ.pop(HOLD_ENV, None);
        app.close();
    }
}

test "unknown seats, bad holders and showtimes not on sale are refused" {
    (app, nova, screening) = _setup();
    try {
        assert code_of(_hold(app, screening, ANNA, ["Z9"])) == "unknown_seats";
        assert code_of(_hold(app, screening, "short", ["A1"])) == "invalid_holder";
        unpublished = add_screening(app, "owner", nova, "Rafiki", 3, state="scheduled");
        assert code_of(_hold(app, unpublished, ANNA, ["A1"])) == "not_found";
        assert code_of(_hold(app, "no-such-showtime", ANNA, ["A1"])) == "not_found";
        assert _states(app, screening)["A1"] == "available";
    } finally {
        app.close();
    }
}

test "blocked and house seats can't be held" {
    (app, nova, screening) = _setup();
    try {
        hall = app.call(
            "owner",
            "create_auditorium",
            {"tenant": "nova", "venue_id": nova.venue, "name": "Screen 2"}
        )["auditorium"]["auditorium_id"];
        app.call(
            "owner",
            "save_layout",
            {
                "tenant": "nova",
                "auditorium_id": hall,
                "rows": 1,
                "cols": 3,
                "seats": [
                    {"label": "B1", "row": 0, "col": 0},
                    {"label": "B2", "row": 0, "col": 1, "seat_type": "BLOCKED"},
                    {"label": "B3", "row": 0, "col": 2, "seat_type": "HOUSE"}
                ]
            }
        );
        app.call("owner", "publish_layout", {"tenant": "nova", "auditorium_id": hall});
        nova.screen = hall;
        other = add_screening(app, "owner", nova, "Rafiki", 0);
        for label in ["B2", "B3"] {
            refused = _hold(app, other, ANNA, ["B1", label]);
            assert code_of(refused) == "not_for_sale" , refused;
            assert refused["error"]["seats"] == [label];
        }
        assert _states(app, other)["B1"] == "available";
    } finally {
        app.close();
    }
}
