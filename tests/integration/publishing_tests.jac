"""P3.5b: publishing a screening, through the production app (main.jac).

Publishing (scheduled -> published) creates the screening's seat inventory, one SeatSlot
per seat of its pinned layout, once, and projects it into the cinema's public Storefront
on the shared guest graph (architecture §4; spike S7). public_screenings(slug) reads that
projection without a login: only published screenings, only public fields. Unpublishing
or cancelling takes the screening off the storefront; editing its movie refreshes it.
"""

import from os { path }
import from datetime { datetime, timedelta, timezone }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     NOVA: str = "nova",
     START: datetime = (datetime.now(timezone.utc) + timedelta(days=2)).replace(
         hour=18, minute=0, second=0, microsecond=0
     ),
     # What a storefront visitor may see about a screening, and nothing else.
     PUBLIC_KEYS: list[str] = [
         "ends_at",
         "movie",
         "screen",
         "screening_id",
         "seat_map",
         "starts_at",
         "state",
         "venue"
     ];

obj Setup {
    has app: Served,
        venue: str,
        screen: str,
        movie: str;
}

def _seats -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Three seats for sale, one blocked, one kept for the house.
    return [
        {"label": "A1", "row": 0, "col": 0},
        {"label": "A2", "row": 0, "col": 1},
        {"label": "A3", "row": 0, "col": 2, "seat_type": "VIP", "zone": "Gold"},
        {"label": "A4", "row": 0, "col": 3, "seat_type": "BLOCKED"},
        {"label": "A5", "row": 0, "col": 4, "seat_type": "HOUSE"}
    ];
}

def _cinema(names: list[str]) -> Setup {
    app = served(MAIN, ["owner"] + names);
    app.call("owner", "create_cinema", {"name": "Nova Cinemas", "slug": NOVA});
    app.call("owner", "start_shift", {"tenant": NOVA});
    venue = app.call(
        "owner",
        "create_venue",
        {
            "tenant": NOVA,
            "name": "Westgate",
            "city": "Nairobi",
            "address": "Mwanzi Road"
        }
    )["venue"]["venue_id"];
    screen = app.call(
        "owner",
        "create_auditorium",
        {"tenant": NOVA, "venue_id": venue, "name": "Screen 1"}
    )["auditorium"]["auditorium_id"];
    app.call(
        "owner",
        "save_layout",
        {
            "tenant": NOVA,
            "auditorium_id": screen,
            "rows": 1,
            "cols": 5,
            "seats": _seats()
        }
    );
    app.call("owner", "publish_layout", {"tenant": NOVA, "auditorium_id": screen});
    movie = app.call(
        "owner",
        "create_movie",
        {
            "tenant": NOVA,
            "title": "Rafiki",
            "synopsis": "Two young women in Nairobi fall in love.",
            "runtime_minutes": 83,
            "age_rating": "18",
            "genres": ["Drama"],
            "language": "English, Swahili"
        }
    )["movie"]["movie_id"];
    return Setup(app=app, venue=venue, screen=screen, movie=movie);
}

def _screening(s: Setup, hours: int = 0, schedule: bool = True) -> str {
    made = s.app.call(
        "owner",
        "create_screening",
        {
            "tenant": NOVA,
            "auditorium_id": s.screen,
            "movie_id": s.movie,
            "starts_at": (START + timedelta(hours=hours)).isoformat()
        }
    );
    assert made["ok"] , made;
    screening = made["screening"]["screening_id"];
    if schedule {
        s.app.call(
            "owner", "schedule_screening", {"tenant": NOVA, "screening_id": screening}
        );
    }
    return screening;
}

def _do(s: Setup, name: str, screening: str, who: str = "owner") -> any {  # jac:ignore[W1037]
    return s.app.call(who, name, {"tenant": NOVA, "screening_id": screening});
}

def _public(s: Setup, slug: str = NOVA) -> any {  # jac:ignore[W1037]
    # The storefront, as an anonymous visitor sees it.
    s.app.client.set_auth_token("");
    resp = s.app.client.post("/function/public_screenings", json={"slug": slug});
    assert resp.status_code == 200 , resp.text;
    return resp.data["result"];
}

def _code(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

test "publishing creates one seat slot per seat, and only once" {
    s = _cinema([]);
    try {
        screening = _screening(s);
        published = _do(s, "publish_screening", screening);
        assert published["ok"]
            and published["screening"]["state"] == "published" , published;
        slots = _do(s, "list_seat_slots", screening)["slots"];
        assert [(x["label"], x["seat_type"], x["state"]) for x in slots]
            == [
                ("A1", "STANDARD", "available"),
                ("A2", "STANDARD", "available"),
                ("A3", "VIP", "available"),
                ("A4", "BLOCKED", "not_for_sale"),
                ("A5", "HOUSE", "not_for_sale")
            ] , slots;
        # Unpublish and publish again: the inventory isn't made twice.
        assert _do(s, "unpublish_screening", screening)["screening"]["state"]
            == "scheduled";
        assert _do(s, "publish_screening", screening)["ok"];
        assert len(_do(s, "list_seat_slots", screening)["slots"]) == 5;
        s.app.restart();
        assert len(_do(s, "list_seat_slots", screening)["slots"]) == 5 , "persisted";
    } finally {
        s.app.close();
    }
}

test "only a scheduled screening can be published, and only a published one unpublished" {
    s = _cinema([]);
    try {
        draft = _screening(s, schedule=False);
        assert _code(_do(s, "publish_screening", draft)) == "invalid_transition";
        assert _code(_do(s, "unpublish_screening", draft)) == "invalid_transition";
        assert _code(_do(s, "list_seat_slots", draft)) == "" , "no slots yet is fine";
        assert _do(s, "list_seat_slots", draft)["slots"] == [];
    } finally {
        s.app.close();
    }
}

test "the storefront shows published screenings with public details only, without a login" {
    s = _cinema([]);
    try {
        shown = _screening(s);
        _screening(s, hours=4);  # scheduled, not published
        _screening(s, hours=8, schedule=False);  # a draft
        _do(s, "publish_screening", shown);
        public = _public(s);
        assert public["ok"]
            and public["cinema"] == {"name": "Nova Cinemas", "slug": NOVA} , public;
        assert len(public["screenings"]) == 1 , public;
        shown_one = public["screenings"][0];
        assert sorted(shown_one.keys()) == PUBLIC_KEYS , sorted(shown_one.keys());
        assert shown_one["screening_id"] == shown and shown_one["state"] == "published";
        # movie_key is the movie's public name, a random key (P4.1).
        assert len(shown_one["movie"]["movie_key"]) == 32;
        assert {
            k: v
            for (k, v) in shown_one["movie"].items()
            if k != "movie_key"
        }
            == {
                "title": "Rafiki",
                "synopsis": "Two young women in Nairobi fall in love.",
                "runtime_minutes": 83,
                "age_rating": "18",
                "genres": ["Drama"],
                "language": "English, Swahili",
                "has_poster": False
            } , shown_one["movie"];
        assert shown_one["venue"] == {"name": "Westgate", "city": "Nairobi"};
        assert shown_one["screen"] == {"name": "Screen 1"};
        assert shown_one["seat_map"]["rows"] == 1
            and shown_one["seat_map"]["cols"] == 5;
        assert [x["label"] for x in shown_one["seat_map"]["seats"]]
            == ["A1", "A2", "A3", "A4", "A5"];
        # No internal ids or staff data anywhere in the public answer.
        tenant_id = s.app.call("owner", "my_access", {"tenant": NOVA})["tenant_id"];
        text = str(public);
        for secret in [
            tenant_id,
            s.venue,
            s.screen,
            s.movie,
            s.app.actors["owner"].root_id
        ] {
            assert secret not in text , f"leaked {secret}";
        }
    } finally {
        s.app.close();
    }
}

test "unpublishing or cancelling takes a screening off the storefront" {
    s = _cinema([]);
    try {
        first = _screening(s);
        second = _screening(s, hours=4);
        for screening in [first, second] {
            _do(s, "publish_screening", screening);
        }
        assert len(_public(s)["screenings"]) == 2;
        _do(s, "unpublish_screening", first);
        assert [x["screening_id"] for x in _public(s)["screenings"]] == [second];
        cancelled = _do(s, "cancel_screening", second);
        assert cancelled["ok"] , cancelled;
        assert _public(s)["screenings"] == [];
    } finally {
        s.app.close();
    }
}

test "the storefront follows movie edits, and keeps each screening's own seat map" {
    s = _cinema([]);
    try {
        screening = _screening(s);
        _do(s, "publish_screening", screening);
        s.app.call(
            "owner",
            "update_movie",
            {
                "tenant": NOVA,
                "movie_id": s.movie,
                "title": "Rafiki (2018)",
                "synopsis": "Two young women in Nairobi fall in love.",
                "runtime_minutes": 83,
                "age_rating": "18",
                "genres": ["Drama", "Romance"],
                "language": "English, Swahili"
            }
        );
        shown_one = _public(s)["screenings"][0];
        assert shown_one["movie"]["title"] == "Rafiki (2018)"
            and shown_one["movie"]["genres"] == ["Drama", "Romance"] , shown_one[
            "movie"
        ];
        # A new layout version for the screen doesn't change this screening's seats.
        s.app.call(
            "owner",
            "save_layout",
            {
                "tenant": NOVA,
                "auditorium_id": s.screen,
                "rows": 1,
                "cols": 1,
                "seats": [{"label": "Z1", "row": 0, "col": 0}]
            }
        );
        s.app.call(
            "owner", "publish_layout", {"tenant": NOVA, "auditorium_id": s.screen}
        );
        assert [x["label"] for x in _public(s)["screenings"][0]["seat_map"]["seats"]]
            == ["A1", "A2", "A3", "A4", "A5"];
    } finally {
        s.app.close();
    }
}

test "each cinema's storefront shows only its own screenings" {
    s = _cinema(["rival"]);
    try {
        _do(s, "publish_screening", _screening(s));
        s.app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        rift = _public(s, "rift");
        assert rift["ok"]
            and rift["cinema"]["name"] == "Rift"
            and rift["screenings"] == [] , rift;
        assert _code(_public(s, "no-such-cinema")) == "not_found";
    } finally {
        s.app.close();
    }
}

test "publishing needs showtimes.update at the venue; other cinemas' ids are not found" {
    s = _cinema(["bo", "rival"]);
    try {
        screening = _screening(s);
        token = s.app.call(
            "owner",
            "invite_staff",
            {"tenant": NOVA, "role": "box_office_agent", "venue_id": s.venue}
        )["token"];
        s.app.call("bo", "accept_invite", {"token": token});
        s.app.call("bo", "start_shift", {"tenant": NOVA});
        assert _code(_do(s, "publish_screening", screening, who="bo")) == "forbidden";
        s.app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        s.app.call("rival", "start_shift", {"tenant": "rift"});
        for name in ["publish_screening", "unpublish_screening", "list_seat_slots"] {
            answer = s.app.call(
                "rival", name, {"tenant": "rift", "screening_id": screening}
            );
            assert _code(answer) == "not_found" , name;
        }
        assert _public(s)["screenings"] == [] , "nothing was published";
    } finally {
        s.app.close();
    }
}
