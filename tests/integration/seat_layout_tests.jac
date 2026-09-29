"""P3.2: seat layouts with versioning (architecture §21, §22), through the production app.

Each screen (auditorium) has numbered layout versions. save_layout writes the screen's
draft; if the latest version is published, it starts a new draft version, so a
published layout is never changed. publish_layout freezes the draft. A layout id always
returns that exact version: screenings will pin one (3.5), and historical tickets keep
pointing at the seats they were sold on.
"""

import from os { path }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     NOVA: str = "nova";

def _cinema(names: list[str]) -> Served {
    app = served(MAIN, ["owner"] + names);
    app.call("owner", "create_cinema", {"name": "Nova Cinemas", "slug": NOVA});
    app.call("owner", "start_shift", {"tenant": NOVA});
    return app;
}

def _venue(app: Served, name: str) -> str {
    return app.call(
        "owner",
        "create_venue",
        {"tenant": NOVA, "name": name, "city": "", "address": ""}
    )["venue"]["venue_id"];
}

def _screen(app: Served, venue_id: str, name: str = "Screen 1") -> str {
    return app.call(
        "owner",
        "create_auditorium",
        {"tenant": NOVA, "venue_id": venue_id, "name": name}
    )["auditorium"]["auditorium_id"];
}

def _seats(labels: list[str], seat_type: str = "STANDARD") -> list[dict[str, any]] {  # jac:ignore[W1037]
    # One row of seats, left to right.
    return [
        {"label": label, "row": 0, "col": col, "seat_type": seat_type}
        for (col, label) in enumerate(labels)
    ];
}

def _save(
    app: Served,
    screen: str,
    seats: list[dict[str, any]],
    rows: int = 2,
    cols: int = 6,
    who: str = "owner"
) -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "save_layout",
        {
            "tenant": NOVA,
            "auditorium_id": screen,
            "rows": rows,
            "cols": cols,
            "seats": seats
        }
    );
}

def _publish(app: Served, screen: str, who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, "publish_layout", {"tenant": NOVA, "auditorium_id": screen});
}

def _get(app: Served, layout_id: str, who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, "get_layout", {"tenant": NOVA, "layout_id": layout_id});
}

def _list(app: Served, screen: str, who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, "list_layouts", {"tenant": NOVA, "auditorium_id": screen});
}

def _labels(layout: dict[str, any]) -> list[str] {  # jac:ignore[W1037]
    return [s["label"] for s in layout["seats"]];
}

def _code(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

test "an owner drafts and publishes a layout, and it persists" {
    app = _cinema([]);
    try {
        screen = _screen(app, _venue(app, "Westgate"));
        seats = _seats(["a1", "A2", "A4"]);
        seats[2]["col"] = 4;  # an aisle at column 3
        seats.append(
            {
                "label": "B1",
                "row": 1,
                "col": 0,
                "seat_type": "wheelchair",
                "zone": "Access"
            }
        );
        draft = _save(app, screen, seats);
        assert draft["ok"] , draft;
        layout = draft["layout"];
        assert (layout["version"], layout["status"], layout["rows"], layout["cols"])
            == (1, "draft", 2, 6) , layout;
        assert _labels(layout) == ["A1", "A2", "A4", "B1"];
        assert layout["seats"][3]
            == {
                "label": "B1",
                "row": 1,
                "col": 0,
                "seat_type": "WHEELCHAIR",
                "zone": "Access"
            };
        published = _publish(app, screen);
        assert published["ok"]
            and published["layout"]["status"] == "published" , published;
        assert published["layout"]["layout_id"] == layout["layout_id"];
        assert published["layout"]["published_at"];
        assert published["layout"]["sellable_seats"] == 4;
        app.restart();
        again = _get(app, layout["layout_id"]);
        assert again["ok"] and again["layout"] == published["layout"] , again;
    } finally {
        app.close();
    }
}

test "a published layout never changes; editing it makes the next version" {
    app = _cinema([]);
    try {
        screen = _screen(app, _venue(app, "Westgate"));
        _save(app, screen, _seats(["A1", "A2", "A3"]));
        v1 = _publish(app, screen)["layout"];
        v2 = _save(app, screen, _seats(["A1", "A2"]))["layout"];
        assert (v2["version"], v2["status"]) == (2, "draft") , v2;
        assert v2["layout_id"] != v1["layout_id"];
        assert _get(app, v1["layout_id"])["layout"] == v1 , "v1 is frozen";
        _publish(app, screen);
        listed = _list(app, screen);
        assert [(l["version"], l["status"]) for l in listed["layouts"]]
            == [(1, "published"), (2, "published")] , listed;
        assert (listed["published_version"], listed["draft_version"]) == (2, None);
        # A screening booked on v1 still finds v1's seats by its id.
        assert _labels(_get(app, v1["layout_id"])["layout"]) == ["A1", "A2", "A3"];
        v3 = _save(app, screen, _seats(["A1"]))["layout"];
        assert v3["version"] == 3;
        assert _list(app, screen)["draft_version"] == 3;
    } finally {
        app.close();
    }
}

test "saving a draft again replaces it" {
    app = _cinema([]);
    try {
        screen = _screen(app, _venue(app, "Westgate"));
        first = _save(app, screen, _seats(["A1"]))["layout"];
        second = _save(app, screen, _seats(["A1", "A2"]), rows=1, cols=2)["layout"];
        assert second["layout_id"] == first["layout_id"] and second["version"] == 1;
        assert (second["rows"], second["cols"], _labels(second))
            == (1, 2, ["A1", "A2"]);
        listed = _list(app, screen);
        assert [l["version"] for l in listed["layouts"]] == [1] , listed;
        assert (listed["published_version"], listed["draft_version"]) == (None, 1);
    } finally {
        app.close();
    }
}

test "an invalid layout is refused with every problem, and nothing is saved" {
    app = _cinema([]);
    try {
        screen = _screen(app, _venue(app, "Westgate"));
        seats = _seats(["A1", "a1", "A 3"])
            + [
                {"label": "A9", "row": 0, "col": 99},
                {"label": "A5", "row": 0, "col": 0},
                {"label": "A6", "row": 1, "col": 1, "seat_type": "GOLD"},
                {"label": "A7"}
            ];
        answer = _save(app, screen, seats);
        assert _code(answer) == "invalid_layout" , answer;
        codes = sorted([p["code"] for p in answer["error"]["problems"]]);
        assert codes
            == sorted(
                [
                    "duplicate_label",
                    "bad_label",
                    "outside_grid",
                    "cell_taken",
                    "bad_seat_type",
                    "bad_seat"
                ]
            ) , codes;
        assert _code(_save(app, screen, [], rows=0, cols=6)) == "invalid_layout";
        assert _list(app, screen)["layouts"] == [];
    } finally {
        app.close();
    }
}

test "publishing needs a valid draft with a seat to sell" {
    app = _cinema([]);
    try {
        screen = _screen(app, _venue(app, "Westgate"));
        assert _code(_publish(app, screen)) == "no_draft";
        _save(app, screen, _seats(["A1", "A2"], "BLOCKED"));
        refused = _publish(app, screen);
        assert _code(refused) == "invalid_layout"
            and [p["code"] for p in refused["error"]["problems"]]
                == ["nothing_to_sell"] , refused;
        assert _list(app, screen)["draft_version"] == 1 , "still a draft";
        _save(app, screen, _seats(["A1", "A2"]));
        assert _publish(app, screen)["ok"];
        assert _code(_publish(app, screen)) == "no_draft" , "nothing left to publish";
    } finally {
        app.close();
    }
}

test "layouts are read with seats.read at the screen's venue and changed by admins" {
    app = _cinema(["ann", "uma"]);
    try {
        westgate = _venue(app, "Westgate");
        garden = _venue(app, "Garden City");
        here = _screen(app, westgate);
        there = _screen(app, garden);
        for screen in [here, there] {
            _save(app, screen, _seats(["A1"]));
            _publish(app, screen);
        }
        layout_there = _list(app, there)["layouts"][0]["layout_id"];
        for (who, role, venue) in [
            ("ann", "box_office_agent", westgate),
            ("uma", "usher", "")
        ] {
            token = app.call(
                "owner",
                "invite_staff",
                {"tenant": NOVA, "role": role, "venue_id": venue}
            )["token"];
            app.call(who, "accept_invite", {"token": token});
            app.call(who, "start_shift", {"tenant": NOVA});
        }
        # Box office at Westgate reads Westgate's screens only.
        assert _list(app, here, who="ann")["ok"];
        assert _code(_list(app, there, who="ann")) == "forbidden";
        assert _code(_get(app, layout_there, who="ann")) == "forbidden";
        assert _code(_save(app, here, _seats(["A1"]), who="ann")) == "forbidden";
        assert _code(_publish(app, here, who="ann")) == "forbidden";
        # Ushers check tickets, not seat plans.
        assert _code(_list(app, here, who="uma")) == "forbidden";
    } finally {
        app.close();
    }
}

test "another cinema's screens and layouts are not found" {
    app = _cinema(["rival"]);
    try {
        screen = _screen(app, _venue(app, "Westgate"));
        layout = _save(app, screen, _seats(["A1"]))["layout"]["layout_id"];
        app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        app.call("rival", "start_shift", {"tenant": "rift"});
        aimed = [
            (
                "save_layout",
                {
                    "tenant": "rift",
                    "auditorium_id": screen,
                    "rows": 1,
                    "cols": 1,
                    "seats": _seats(["X1"])
                }
            ),
            ("publish_layout", {"tenant": "rift", "auditorium_id": screen}),
            ("list_layouts", {"tenant": "rift", "auditorium_id": screen}),
            ("get_layout", {"tenant": "rift", "layout_id": layout}),
            ("get_layout", {"tenant": "rift", "layout_id": "not-an-id"})
        ];
        for (name, body) in aimed {
            assert _code(app.call("rival", name, body)) == "not_found" , name;
        }
        assert _labels(_get(app, layout)["layout"]) == ["A1"] , "untouched";
    } finally {
        app.close();
    }
}

test "deleting a screen deletes its layouts" {
    app = _cinema([]);
    try {
        screen = _screen(app, _venue(app, "Westgate"));
        _save(app, screen, _seats(["A1"]));
        v1 = _publish(app, screen)["layout"]["layout_id"];
        v2 = _save(app, screen, _seats(["A1", "A2"]))["layout"]["layout_id"];
        assert app.call(
            "owner", "delete_auditorium", {"tenant": NOVA, "auditorium_id": screen}
        )["ok"];
        for layout in [v1, v2] {
            assert _code(_get(app, layout)) == "not_found";
        }
    } finally {
        app.close();
    }
}

test "layout changes need an open shift" {
    app = _cinema([]);
    try {
        screen = _screen(app, _venue(app, "Westgate"));
        app.call("owner", "end_shift", {"tenant": NOVA});
        assert _code(_save(app, screen, _seats(["A1"]))) == "no_shift";
        assert _code(_list(app, screen)) == "no_shift";
    } finally {
        app.close();
    }
}
