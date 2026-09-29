"""P3.5a: screenings, through the production app (main.jac).

A screening puts a movie on a screen at a time. It pins the screen's published seat
layout version when it's created, and keeps it when the layout is changed later (P3.2).
Screenings on one screen may not overlap, counting the movie's running time plus a
15-minute cleaning buffer. The lifecycle is core/catalog/screening_rules.jac.
Permissions (showtimes.*) apply at the screen's venue; another cinema's ids answer
not_found; a screen or movie with screenings can't be deleted.
"""

import from os { path }
import from datetime { datetime, timedelta, timezone }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     NOVA: str = "nova",
     # Two days ahead at 18:00 UTC, whatever today is.
     BASE: datetime = (datetime.now(timezone.utc) + timedelta(days=2)).replace(
         hour=18, minute=0, second=0, microsecond=0
     );

def _at(minutes: int) -> str {
    # BASE + minutes, in East Africa Time as a client would send it.
    return (BASE + timedelta(minutes=minutes)).astimezone(
        timezone(timedelta(hours=3))
    ).isoformat();
}

def _utc(minutes: int) -> str {
    return (BASE + timedelta(minutes=minutes)).isoformat();
}

obj Setup {
    has app: Served,
        venue: str,
        screen: str,
        movie: str;
}

def _cinema(names: list[str]) -> Setup {
    # Nova, a venue with one screen (published 1-row layout) and a 100-minute movie.
    app = served(MAIN, ["owner"] + names);
    app.call("owner", "create_cinema", {"name": "Nova Cinemas", "slug": NOVA});
    app.call("owner", "start_shift", {"tenant": NOVA});
    venue = _venue(app, "Westgate");
    screen = _screen(app, venue, "Screen 1");
    movie = app.call(
        "owner",
        "create_movie",
        {
            "tenant": NOVA,
            "title": "Rafiki",
            "synopsis": "",
            "runtime_minutes": 100,
            "age_rating": "18",
            "genres": [],
            "language": ""
        }
    )["movie"]["movie_id"];
    return Setup(app=app, venue=venue, screen=screen, movie=movie);
}

def _venue(app: Served, name: str) -> str {
    return app.call(
        "owner",
        "create_venue",
        {"tenant": NOVA, "name": name, "city": "", "address": ""}
    )["venue"]["venue_id"];
}

def _screen(app: Served, venue: str, name: str, publish: bool = True) -> str {
    screen = app.call(
        "owner", "create_auditorium", {"tenant": NOVA, "venue_id": venue, "name": name}
    )["auditorium"]["auditorium_id"];
    app.call(
        "owner",
        "save_layout",
        {
            "tenant": NOVA,
            "auditorium_id": screen,
            "rows": 1,
            "cols": 2,
            "seats": [
                {"label": "A1", "row": 0, "col": 0},
                {"label": "A2", "row": 0, "col": 1}
            ]
        }
    );
    if publish {
        app.call("owner", "publish_layout", {"tenant": NOVA, "auditorium_id": screen});
    }
    return screen;
}

def _create(s: Setup, minutes: int, screen: str = "", who: str = "owner") -> any {  # jac:ignore[W1037]
    return s.app.call(
        who,
        "create_screening",
        {
            "tenant": NOVA,
            "auditorium_id": screen or s.screen,
            "movie_id": s.movie,
            "starts_at": _at(minutes)
        }
    );
}

def _code(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

test "a screening is created as a draft, pinned to the screen's published layout, and persists" {
    s = _cinema([]);
    try {
        answer = _create(s, 0);
        assert answer["ok"] , answer;
        got = answer["screening"];
        layouts = s.app.call(
            "owner", "list_layouts", {"tenant": NOVA, "auditorium_id": s.screen}
        )["layouts"];
        assert got
            == {
                "screening_id": got["screening_id"],
                "auditorium_id": s.screen,
                "venue_id": s.venue,
                "movie_id": s.movie,
                "movie_title": "Rafiki",
                "layout_id": layouts[0]["layout_id"],
                "layout_version": 1,
                "starts_at": _utc(0),
                "ends_at": _utc(115),
                "state": "draft"
            } , got;
        _create(s, 300);
        s.app.restart();
        listed = s.app.call(
            "owner", "list_screenings", {"tenant": NOVA, "auditorium_id": s.screen}
        )["screenings"];
        assert [x["starts_at"] for x in listed] == [_utc(0), _utc(300)] , listed;
        again = s.app.call(
            "owner",
            "get_screening",
            {"tenant": NOVA, "screening_id": got["screening_id"]}
        );
        assert again["ok"] and again["screening"] == got;
    } finally {
        s.app.close();
    }
}

test "a screen needs a published layout before anything is scheduled on it" {
    s = _cinema([]);
    try {
        draft_only = _screen(s.app, s.venue, "Screen 2", publish=False);
        assert _code(_create(s, 0, draft_only)) == "no_layout";
        bare = s.app.call(
            "owner",
            "create_auditorium",
            {"tenant": NOVA, "venue_id": s.venue, "name": "Screen 3"}
        )["auditorium"]["auditorium_id"];
        assert _code(_create(s, 0, bare)) == "no_layout";
    } finally {
        s.app.close();
    }
}

test "screenings on one screen can't overlap, counting the cleaning buffer" {
    s = _cinema([]);
    try {
        assert _create(s, 0)["ok"];  # busy until +115 (100 min + 15 cleaning)
        for start in [0, -60, 60, 114, -114] {
            answer = _create(s, start);
            assert _code(answer) == "overlap" , f"+{start}: {answer}";
            assert "Rafiki" in answer["error"]["message"];
        }
        assert _create(s, 115)["ok"] , "back to back, after cleaning";
        assert _create(s, -115)["ok"] , "ends exactly as the first starts";
        other = _screen(s.app, s.venue, "Screen 2");
        assert _create(s, 0, other)["ok"] , "another screen at the same time";
    } finally {
        s.app.close();
    }
}

test "a cancelled screening frees its time" {
    s = _cinema([]);
    try {
        first = _create(s, 0)["screening"]["screening_id"];
        cancelled = s.app.call(
            "owner", "cancel_screening", {"tenant": NOVA, "screening_id": first}
        );
        assert cancelled["ok"] and cancelled["screening"]["state"] == "cancelled";
        assert _create(s, 0)["ok"];
    } finally {
        s.app.close();
    }
}

test "a screening keeps its layout version when the screen's layout changes" {
    s = _cinema([]);
    try {
        before = _create(s, 0)["screening"];
        s.app.call(
            "owner",
            "save_layout",
            {
                "tenant": NOVA,
                "auditorium_id": s.screen,
                "rows": 1,
                "cols": 3,
                "seats": [
                    {"label": "A1", "row": 0, "col": 0},
                    {"label": "A2", "row": 0, "col": 1},
                    {"label": "A3", "row": 0, "col": 2}
                ]
            }
        );
        # A draft v2 doesn't count: new screenings still get v1 until it's published.
        assert _create(s, 300)["screening"]["layout_version"] == 1;
        s.app.call(
            "owner", "publish_layout", {"tenant": NOVA, "auditorium_id": s.screen}
        );
        after = _create(s, 600)["screening"];
        assert after["layout_version"] == 2
            and after["layout_id"] != before["layout_id"];
        kept = s.app.call(
            "owner",
            "get_screening",
            {"tenant": NOVA, "screening_id": before["screening_id"]}
        )["screening"];
        assert (kept["layout_id"], kept["layout_version"])
            == (before["layout_id"], 1) , kept;
    } finally {
        s.app.close();
    }
}

test "rescheduling and scheduling follow the lifecycle" {
    s = _cinema([]);
    try {
        first = _create(s, 0)["screening"]["screening_id"];
        second = _create(s, 300)["screening"]["screening_id"];
        call = lambda (name: str, body: dict[str, any]) -> any {  # jac:ignore[W1037]
            body["tenant"] = NOVA;
            return s.app.call("owner", name, body);
        };
        moved = call(
            "reschedule_screening", {"screening_id": first, "starts_at": _at(30)}
        );
        assert moved["ok"]
            and moved["screening"]["starts_at"] == _utc(30)
            and moved["screening"]["ends_at"] == _utc(145) , moved;
        assert call(
            "reschedule_screening", {"screening_id": first, "starts_at": _at(40)}
        )["ok"] , "overlapping only itself is fine";
        clash = call(
            "reschedule_screening", {"screening_id": first, "starts_at": _at(250)}
        );
        assert _code(clash) == "overlap" , clash;
        scheduled = call("schedule_screening", {"screening_id": first});
        assert scheduled["ok"] and scheduled["screening"]["state"] == "scheduled";
        assert _code(call("schedule_screening", {"screening_id": first}))
            == "invalid_transition";
        assert call(
            "reschedule_screening", {"screening_id": first, "starts_at": _at(20)}
        )["ok"] , "a scheduled screening can still move";
        call("cancel_screening", {"screening_id": second});
        for (name, body) in [
            ("schedule_screening", {"screening_id": second}),
            ("cancel_screening", {"screening_id": second}),
            ("reschedule_screening", {"screening_id": second, "starts_at": _at(900)})
        ] {
            assert _code(call(name, body)) == "invalid_transition" , name;
        }
    } finally {
        s.app.close();
    }
}

test "start times need a time zone, and must be ahead but within a year" {
    s = _cinema([]);
    try {
        bad = [
            ((BASE.replace(tzinfo=None)).isoformat(), "invalid_time"),
            ("next friday", "invalid_time"),
            ((datetime.now(timezone.utc) - timedelta(hours=1)).isoformat(), "in_past"),
            (
                (datetime.now(timezone.utc) + timedelta(days=400)).isoformat(),
                "invalid_time"
            )
        ];
        for (text, code) in bad {
            answer = s.app.call(
                "owner",
                "create_screening",
                {
                    "tenant": NOVA,
                    "auditorium_id": s.screen,
                    "movie_id": s.movie,
                    "starts_at": text
                }
            );
            assert _code(answer) == code , f"{text!r}: {answer}";
        }
    } finally {
        s.app.close();
    }
}

test "showtime permissions apply at the screen's venue" {
    s = _cinema(["gm", "bo"]);
    try {
        garden = _venue(s.app, "Garden City");
        garden_screen = _screen(s.app, garden, "G1");
        for (who, role) in [("gm", "general_manager"), ("bo", "box_office_agent")] {
            token = s.app.call(
                "owner",
                "invite_staff",
                {"tenant": NOVA, "role": role, "venue_id": s.venue}
            )["token"];
            s.app.call(who, "accept_invite", {"token": token});
            s.app.call(who, "start_shift", {"tenant": NOVA});
        }
        mine = _create(s, 0, who="gm");
        assert mine["ok"] , "a manager schedules at their venue";
        assert _code(_create(s, 0, garden_screen, who="gm")) == "forbidden";
        assert _code(
            s.app.call(
                "gm",
                "list_screenings",
                {"tenant": NOVA, "auditorium_id": garden_screen}
            )
        )
            == "forbidden";
        screening = mine["screening"]["screening_id"];
        assert s.app.call(
            "bo", "list_screenings", {"tenant": NOVA, "auditorium_id": s.screen}
        )["ok"] , "box office reads the programme";
        assert _code(_create(s, 300, who="bo")) == "forbidden";
        assert _code(
            s.app.call(
                "bo", "cancel_screening", {"tenant": NOVA, "screening_id": screening}
            )
        )
            == "forbidden";
    } finally {
        s.app.close();
    }
}

test "another cinema's screens, movies and screenings are not found" {
    s = _cinema(["rival"]);
    try {
        screening = _create(s, 0)["screening"]["screening_id"];
        s.app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        s.app.call("rival", "start_shift", {"tenant": "rift"});
        aimed = [
            (
                "create_screening",
                {
                    "tenant": "rift",
                    "auditorium_id": s.screen,
                    "movie_id": s.movie,
                    "starts_at": _at(0)
                }
            ),
            ("list_screenings", {"tenant": "rift", "auditorium_id": s.screen}),
            ("get_screening", {"tenant": "rift", "screening_id": screening}),
            (
                "reschedule_screening",
                {"tenant": "rift", "screening_id": screening, "starts_at": _at(500)}
            ),
            ("schedule_screening", {"tenant": "rift", "screening_id": screening}),
            ("cancel_screening", {"tenant": "rift", "screening_id": screening})
        ];
        for (name, body) in aimed {
            assert _code(s.app.call("rival", name, body)) == "not_found" , name;
        }
        # Their own screen with our movie: the movie isn't found at their cinema.
        s.app.call(
            "rival",
            "create_venue",
            {"tenant": "rift", "name": "Rift Mall", "city": "", "address": ""}
        );
        got = s.app.call(
            "owner", "get_screening", {"tenant": NOVA, "screening_id": screening}
        )["screening"];
        assert got["state"] == "draft" and got["starts_at"] == _utc(0) , "untouched";
    } finally {
        s.app.close();
    }
}

test "a screen or a movie with screenings can't be deleted" {
    s = _cinema([]);
    try {
        screening = _create(s, 0)["screening"]["screening_id"];
        s.app.call(
            "owner", "cancel_screening", {"tenant": NOVA, "screening_id": screening}
        );
        # Even cancelled screenings are history that tickets and reports point at.
        screen_answer = s.app.call(
            "owner", "delete_auditorium", {"tenant": NOVA, "auditorium_id": s.screen}
        );
        assert _code(screen_answer) == "screen_has_screenings" , screen_answer;
        movie_answer = s.app.call(
            "owner", "delete_movie", {"tenant": NOVA, "movie_id": s.movie}
        );
        assert _code(movie_answer) == "movie_has_screenings" , movie_answer;
    } finally {
        s.app.close();
    }
}

test "screening changes need an open shift" {
    s = _cinema([]);
    try {
        s.app.call("owner", "end_shift", {"tenant": NOVA});
        assert _code(_create(s, 0)) == "no_shift";
    } finally {
        s.app.close();
    }
}
