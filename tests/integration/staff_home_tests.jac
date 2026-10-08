"""P7.4: the staff home page's data (core/reporting/staff_home.jac, staff_home).

In-process app (tests/apps/payment_app.jac) with the clock frozen an hour before Nova's
Rafiki showtime, so "today" is the showtime's day. One request gives the Overview what
the caller's roles allow:

- setup (who can configure venues): seven steps, each done or not, with its section;
- today's showtimes at the venues where the caller may read showtimes, each with seats
  sold and on sale, and whether the caller may sell or scan there;
- today's figures (financial_reports.read): money taken, tickets, occupancy;
- recent activity (audit.read): the last five audit events.

It needs a shift, like every staff endpoint (ADR-0006).
"""

import io;
import os;
import uuid;
import base64;
import from PIL { Image }
import from tests.support.served { Served }
import from tests.support.storefront_setup { add_screening, browse, code_of }
import from tests.support.payment_setup { paying_cinema, hire }

glob TICKET: int = 93000,
     STEPS: list[str] = [
         "venue",
         "screen",
         "prices",
         "movie",
         "showtime",
         "branding",
         "team"
     ];

def _at(app: Served, screening: str, minutes: int) {
    app.call(
        "owner",
        "rd_freeze",
        {"slug": "nova", "screening_id": screening, "minutes": minutes}
    );
}

def _home(app: Served, who: str, tenant: str = "nova") -> any {  # jac:ignore[W1037]
    return app.call(who, "staff_home", {"tenant": tenant});
}

def _cash_sale(app: Served, screening: str) {
    # The agent sells A3 and A4 for cash at the counter.
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": "nova", "screening_id": screening, "holder": holder};
    assert browse(app, "hold_seats", {** where, "labels": ["A3", "A4"]})["ok"];
    assert browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [
                {"seat_label": "A3", "ticket_type": "ADULT"},
                {"seat_label": "A4", "ticket_type": "ADULT"}
            ]
        }
    )["ok"];
    sold = app.call(
        "agent",
        "sell_for_cash",
        {"tenant": "nova", "screening_id": screening, "holder": holder, "email": ""}
    );
    assert sold["ok"] , sold;
}

test "the owner's home: setup steps, today's showtimes, today's figures, recent activity" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, first) = paying_cinema(["agent"]);
    try {
        tomorrow = add_screening(app, "owner", nova, "Rafiki", 24);
        hire(app, "agent", "box_office_agent", nova.venue);
        _at(app, first, -60);
        _cash_sale(app, first);
        home = _home(app, "owner");
        assert home["ok"] , home;
        assert home["cinema"]["name"] == "Nova Cinemas";
        assert home["cinema"]["today"] and home["cinema"]["timezone"];
        setup = home["setup"];
        assert [s["key"] for s in setup["steps"]] == STEPS;
        assert [
            s["key"]
            for s in setup["steps"]
            if not s["done"]
        ]
            == ["branding"] , setup;
        assert setup["done"] == 6 and setup["total"] == 7;
        assert all([s["label"] and s["section"] for s in setup["steps"]]);
        # Today's showtimes: Rafiki, not tomorrow's.
        shows = home["showtimes"];
        assert [s["screening_id"] for s in shows] == [first] , shows;
        assert tomorrow not in [s["screening_id"] for s in shows];
        show = shows[0];
        assert show["movie_title"] == "Rafiki" and show["venue"] and show["screen"];
        assert [show["seats_sold"], show["seats_on_sale"]] == [2, 5];
        # The page's artwork: the movie's public key; Rafiki has no images here.
        assert show["movie_key"] and show["has_poster"] == False;
        assert show["has_backdrop"] == False;
        assert show["can_sell"] and show["can_scan"];
        figures = home["figures"];
        assert figures["takings_net_cents"] == 2 * TICKET , figures;
        assert figures["tickets_sold"] == 2 and figures["showtimes"] == 1;
        assert figures["occupancy_pct"] == 40.0 and figures["currency"] == "KES";
        activity = home["activity"];
        assert 0 < len(activity) <= 5;
        assert activity[0]["action"] == "sale.cash" , activity;
    } finally {
        app.call("owner", "rd_unfreeze");
        app.close();
    }
}

test "each role sees its part: sell or scan, figures, nothing else" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, first) = paying_cinema(["agent", "usher", "finance", "elsewhere"]);
    try {
        mall = app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Mall", "city": "", "address": ""}
        )["venue"]["venue_id"];
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "usher", "usher", nova.venue);
        hire(app, "finance", "finance_manager", "");
        hire(app, "elsewhere", "box_office_agent", mall);
        _at(app, first, -60);
        agent = _home(app, "agent");
        assert agent["ok"] , agent;
        assert agent["setup"] is None and agent["figures"] is None;
        assert agent["activity"] is None;
        assert [
            [s["screening_id"], s["can_sell"], s["can_scan"]]
            for s in agent["showtimes"]
        ]
            == [[first, True, False]];
        usher = _home(app, "usher");
        assert [[s["can_sell"], s["can_scan"]] for s in usher["showtimes"]]
            == [[False, True]];
        assert usher["figures"] is None;
        finance = _home(app, "finance");
        assert finance["figures"] is not None and finance["activity"] is None;
        assert finance["setup"] is None;
        assert [[s["can_sell"], s["can_scan"]] for s in finance["showtimes"]]
            == [[False, False]];
        # An agent limited to another venue sees no showtimes of this one.
        assert _home(app, "elsewhere")["showtimes"] == [];
    } finally {
        app.call("owner", "rd_unfreeze");
        app.close();
    }
}

def _poster_png -> str {
    out = io.BytesIO();
    Image.new("RGB", (400, 600), "#E7B03A").save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _art(app: Served, who: str, screening: str, kind: str) -> any {  # jac:ignore[W1037]
    return app.call(
        who, "showtime_art", {"tenant": "nova", "screening_id": screening, "kind": kind}
    );
}

test "a showtime's artwork for staff who read its showtimes, public or not" {
    (app, nova, first) = paying_cinema(["usher", "elsewhere"]);
    try {
        mall = app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Mall", "city": "", "address": ""}
        )["venue"]["venue_id"];
        hire(app, "usher", "usher", nova.venue);
        hire(app, "elsewhere", "box_office_agent", mall);
        # No poster yet.
        assert code_of(_art(app, "owner", first, "poster")) == "no_poster";
        uploaded = app.call(
            "owner",
            "upload_poster",
            {
                "tenant": "nova",
                "movie_id": nova.movies["Rafiki"],
                "content_type": "image/png",
                "data_base64": _poster_png()
            }
        );
        assert uploaded["ok"] , uploaded;
        shown = _art(app, "usher", first, "poster");
        assert shown["ok"]
            and shown["image"].startswith("data:image/webp;base64,") , shown;
        assert code_of(_art(app, "owner", first, "backdrop")) == "no_backdrop";
        assert code_of(_art(app, "owner", first, "trailer")) == "bad_kind";
        # Staff of another venue can't read this showtime, nor can anyone pick a
        # showtime that isn't one.
        assert code_of(_art(app, "elsewhere", first, "poster")) == "forbidden";
        assert code_of(_art(app, "owner", "not-a-showtime", "poster")) == "not_found";
    } finally {
        app.close();
    }
}

test "off shift or outside the cinema, the home page has nothing" {
    (app, nova, _) = paying_cinema(["agent", "outsider"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        assert app.call("agent", "end_shift", {"tenant": "nova"})["ok"];
        assert code_of(_home(app, "agent")) == "no_shift";
        assert code_of(_home(app, "outsider")) == "not_found";
    } finally {
        app.close();
    }
}
