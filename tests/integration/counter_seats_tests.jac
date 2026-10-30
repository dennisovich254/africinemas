"""Seats kept for the counter (owner, 2026-10-30): online can't book them, the counter can.

In-process app (payment_app.jac). Nova's screen keeps A4 and A5 for the counter.
- Online, before the release time: they show as sold at the box office, and holding
  one is refused (counter_seats), alone or with other seats.
- The box office sees them, marked, and holds and sells them.
- One showtime can change them (add A3, free A5), kept as changes to the screen's.
- The release time (2 hours before unless changed) puts unsold ones on sale online.
- Who may: seats.configure for the screen, showtimes.update for a showtime, settings for
  the release time; unknown or unsellable seats and a bad release time are refused.
"""

import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { paying_cinema, hire }

def _public(app: Served, screening: str) -> dict[str, dict[str, any]] {  # jac:ignore[W1037]
    seen = browse(
        app, "public_seat_availability", {"slug": "nova", "screening_id": screening}
    );
    assert seen["ok"] , seen;
    return {s["label"]: s for s in seen["seats"]};
}

def _hold(app: Served, screening: str, labels: list[str]) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "hold_seats",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": f"web-{uuid.uuid4().hex}",
            "labels": labels
        }
    );
}

test "counter seats are kept from online sale until their release time" {
    (app, nova, screening) = paying_cinema(["agent"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        # The screen keeps A4 and A5 for the counter.
        set = app.call(
            "owner",
            "set_screen_counter_seats",
            {
                "tenant": "nova",
                "auditorium_id": nova.screen,
                "labels": ["a4", "A5", "A5"]
            }
        );
        assert set["ok"] , set;
        assert [
            s["label"]
            for s in set["seats"]
            if s["counter"]
        ]
            == ["A4", "A5"];
        assert set["release_hours"] == 2;
        # Online: shown as sold at the box office, and refused.
        seats = _public(app, screening);
        assert seats["A4"]["state"] == "not_for_sale"
            and seats["A4"]["text"] == "Counter only, sold at the box office"
            and seats["A4"]["counter_only"];
        assert seats["A3"]["state"] == "available";
        refused = _hold(app, screening, ["A3", "A4"]);
        assert code_of(refused) == "counter_seats" , refused;
        assert refused["error"]["seats"] == ["A4"];
        # Refused all or nothing: A3 wasn't kept either.
        assert _public(app, screening)["A3"]["state"] == "available";
        assert _hold(app, screening, ["A3"])["ok"];
        # The box office: marked, and its to sell.
        desk = app.call(
            "agent",
            "counter_seat_availability",
            {"tenant": "nova", "screening_id": screening}
        );
        mine = {s["label"]: s for s in desk["seats"]};
        assert mine["A4"]["state"] == "available" and mine["A4"]["counter"];
        assert not mine["A3"]["counter"];
        holder = f"counter-{uuid.uuid4().hex}";
        held = app.call(
            "agent",
            "counter_hold_seats",
            {
                "tenant": "nova",
                "screening_id": screening,
                "holder": holder,
                "labels": ["A4"]
            }
        );
        assert held["ok"] , held;
        # Not without selling there.
        assert not app.call(
            "owner",
            "counter_hold_seats",
            {
                "tenant": "rift",
                "screening_id": screening,
                "holder": holder,
                "labels": ["A5"]
            }
        )["ok"];
        # One showtime: A3 added, A5 freed; the rest still follow the screen.
        changed = app.call(
            "owner",
            "set_showtime_counter_seats",
            {"tenant": "nova", "screening_id": screening, "labels": ["A3", "A4"]}
        );
        assert changed["ok"] , changed;
        assert [
            s["label"]
            for s in changed["seats"]
            if s["counter"]
        ]
            == ["A3", "A4"];
        assert changed["from_screen"] == ["A4", "A5"];
        assert _public(app, screening)["A5"]["state"] == "available";
        # The screen's own choice is unchanged.
        screen = app.call(
            "owner",
            "screen_counter_seats",
            {"tenant": "nova", "auditorium_id": nova.screen}
        );
        assert [
            s["label"]
            for s in screen["seats"]
            if s["counter"]
        ]
            == ["A4", "A5"];
        # The release time: 72 hours before, and the showtime is sooner, so it's released.
        assert code_of(
            app.call(
                "owner", "set_counter_release_hours", {"tenant": "nova", "hours": 73}
            )
        )
            == "invalid_hours";
        assert app.call(
            "owner", "set_counter_release_hours", {"tenant": "nova", "hours": 72}
        )["counter_release_hours"]
            == 72;
        assert app.call("owner", "box_office_rules", {"tenant": "nova"})[
            "counter_release_hours"
        ]
            == 72;
        assert _public(app, screening)["A5"]["state"] == "available";
        # Released: none kept now, and A5 (freed above) is on sale online.
        mine = app.call(
            "owner",
            "showtime_counter_seats",
            {"tenant": "nova", "screening_id": screening}
        );
        assert mine["released"]
            and [
                s["label"]
                for s in mine["seats"]
                if s["counter"]
            ]
                == [] , mine;
        assert _public(app, screening)["A5"]["state"] == "available";
        # Kept after the release time: kept online until the start, and still the box
        # office's to sell.
        late = app.call(
            "owner",
            "set_showtime_counter_seats",
            {"tenant": "nova", "screening_id": screening, "labels": ["A5"]}
        );
        assert [
            s["label"]
            for s in late["seats"]
            if s["counter"]
        ]
            == ["A5"] , late;
        assert _public(app, screening)["A5"]["counter_only"];
        assert code_of(_hold(app, screening, ["A5"])) == "counter_seats";
        desk = app.call(
            "agent",
            "counter_seat_availability",
            {"tenant": "nova", "screening_id": screening}
        );
        mine = {s["label"]: s for s in desk["seats"]};
        assert mine["A5"]["state"] == "available" and mine["A5"]["counter"];
        assert not mine["A4"]["counter"];
        # Who may, and what.
        for (who, name, body) in [
            (
                "agent",
                "set_screen_counter_seats",
                {"auditorium_id": nova.screen, "labels": ["A5"]}
            ),
            (
                "agent",
                "set_showtime_counter_seats",
                {"screening_id": screening, "labels": ["A5"]}
            ),
            ("agent", "set_counter_release_hours", {"hours": 5})
        ] {
            assert not app.call(who, name, {"tenant": "nova", ** body})["ok"] , name;
        }
        assert code_of(
            app.call(
                "owner",
                "set_screen_counter_seats",
                {"tenant": "nova", "auditorium_id": nova.screen, "labels": ["Z9"]}
            )
        )
            == "unknown_seats";
    } finally {
        app.close();
    }
}
