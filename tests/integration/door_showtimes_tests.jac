"""P6.4: the showtimes a member of staff can check tickets for right now (door_showtimes).

In-process app (tests/apps/payment_app.jac) with a frozen clock. The scanner page lists
the published showtimes whose door is open (from two hours before the start until the
showtime ends, as redeeming checks, ADR-0021), at the venues where the caller may scan
tickets. A box office agent, who can't scan, is refused; another cinema's showtimes
never show.
"""

import os;
import from tests.support.served { Served }
import from tests.support.storefront_setup { add_screening, code_of, open_cinema_for }
import from tests.support.payment_setup { paying_cinema, hire }

def _at(app: Served, screening: str, minutes: int) {
    app.call(
        "owner",
        "rd_freeze",
        {"slug": "nova", "screening_id": screening, "minutes": minutes}
    );
}

def _open(app: Served, who: str, tenant: str = "nova") -> any {  # jac:ignore[W1037]
    return app.call(who, "door_showtimes", {"tenant": tenant});
}

test "the showtimes whose door is open now, with what the scanner shows" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, first) = paying_cinema(["usher"]);
    try {
        later = add_screening(app, "owner", nova, "Rafiki", 3);
        hire(app, "usher", "usher", nova.venue);
        _at(app, first, -30);
        shown = _open(app, "usher");
        assert shown["ok"] , shown;
        listed = shown["showtimes"];
        assert [s["screening_id"] for s in listed] == [first] , listed;
        assert listed[0]["movie_title"] == "Rafiki";
        assert listed[0]["starts_at"] and listed[0]["venue"] and listed[0]["screen"];
        assert shown["timezone"];
        # Both doors open: the later one's opened (two hours before its start) while
        # the first is still on (90 minutes plus the 15-minute cleaning buffer).
        _at(app, first, 90);
        assert sorted([s["screening_id"] for s in _open(app, "usher")["showtimes"]])
            == sorted([first, later]);
        # Before any door opens, nothing.
        _at(app, first, -121);
        assert _open(app, "usher")["showtimes"] == [];
    } finally {
        app.call("owner", "rd_unfreeze");
        app.close();
    }
}

test "only showtimes at venues where the caller may scan; an agent can't scan at all" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, first) = paying_cinema(["agent", "elsewhere", "rival"]);
    try {
        mall = app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Mall", "city": "", "address": ""}
        )["venue"]["venue_id"];
        hire(app, "elsewhere", "usher", mall);
        hire(app, "agent", "box_office_agent", nova.venue);
        _at(app, first, -30);
        assert _open(app, "elsewhere")["showtimes"] == [];
        assert code_of(_open(app, "agent")) == "forbidden";
        assert [s["screening_id"] for s in _open(app, "owner")["showtimes"]] == [first];
        # Another cinema's staff see nothing of Nova.
        open_cinema_for(app, "rival", "rift", "Rift Cinemas");
        assert code_of(_open(app, "rival")) == "not_found";
        assert _open(app, "rival", "rift")["showtimes"] == [];
    } finally {
        app.call("owner", "rd_unfreeze");
        app.close();
    }
}
