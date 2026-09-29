"""P3.1: venues and auditoriums (screens), through the production app (main.jac).

A cinema has venues (its locations) and each venue has auditoriums. Reading needs
venues.read; changing needs venues.configure (at that venue; creating or deleting a
whole venue needs it cinema-wide). Names are unique per cinema (venues) and per venue
(auditoriums), ignoring case and extra spaces, and a name frees up when it's renamed
away or deleted. Another cinema's ids answer not_found.
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

def _venue(app: Served, name: str, who: str = "owner") -> dict[str, any] {  # jac:ignore[W1037]
    answer = app.call(
        who,
        "create_venue",
        {"tenant": NOVA, "name": name, "city": "Nairobi", "address": "Waiyaki Way"}
    );
    assert answer["ok"] , answer;
    return answer["venue"];
}

def _screen(app: Served, venue_id: str, name: str) -> any {  # jac:ignore[W1037]
    return app.call(
        "owner",
        "create_auditorium",
        {"tenant": NOVA, "venue_id": venue_id, "name": name}
    );
}

def _code(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

def _staff(app: Served, who: str, role: str, venue_id: str) {
    token = app.call(
        "owner", "invite_staff", {"tenant": NOVA, "role": role, "venue_id": venue_id}
    )["token"];
    app.call(who, "accept_invite", {"token": token});
    app.call(who, "start_shift", {"tenant": NOVA});
}

test "an owner sets up venues and screens, and they persist" {
    app = _cinema([]);
    try {
        westgate = _venue(app, "Westgate");
        assert westgate["name"] == "Westgate"
            and westgate["city"] == "Nairobi"
            and westgate["auditoriums"] == [] , westgate;
        two = _screen(app, westgate["venue_id"], "Screen 2");
        one = _screen(app, westgate["venue_id"], "  Screen   1 ");
        assert one["ok"] and one["auditorium"]["name"] == "Screen 1" , one;
        updated = app.call(
            "owner",
            "update_venue",
            {
                "tenant": NOVA,
                "venue_id": westgate["venue_id"],
                "name": "Westgate Mall",
                "city": "Nairobi",
                "address": "Mwanzi Road"
            }
        );
        assert updated["ok"] and updated["venue"]["address"] == "Mwanzi Road" , updated;
        renamed = app.call(
            "owner",
            "rename_auditorium",
            {
                "tenant": NOVA,
                "auditorium_id": two["auditorium"]["auditorium_id"],
                "name": "IMAX"
            }
        );
        assert renamed["ok"] and renamed["auditorium"]["name"] == "IMAX" , renamed;
        app.restart();
        venues = app.call("owner", "list_venues", {"tenant": NOVA})["venues"];
        assert [(v["name"], [a["name"] for a in v["auditoriums"]]) for v in venues]
            == [("Westgate Mall", ["IMAX", "Screen 1"])] , venues;
    } finally {
        app.close();
    }
}

test "screen names are unique per venue, ignoring case and spaces" {
    app = _cinema([]);
    try {
        westgate = _venue(app, "Westgate")["venue_id"];
        garden = _venue(app, "Garden City")["venue_id"];
        first = _screen(app, westgate, "Screen 1");
        assert _code(_screen(app, westgate, " screen  1")) == "name_taken";
        assert _screen(app, garden, "Screen 1")["ok"] , "another venue may reuse it";
        other = _screen(app, westgate, "Screen 2")["auditorium"]["auditorium_id"];
        taken = app.call(
            "owner",
            "rename_auditorium",
            {"tenant": NOVA, "auditorium_id": other, "name": "SCREEN 1"}
        );
        assert _code(taken) == "name_taken" , taken;
        # Renaming away frees the old name; a case-only change of one's own name is fine.
        first_id = first["auditorium"]["auditorium_id"];
        for new_name in ["screen 1", "Gold Class"] {
            answer = app.call(
                "owner",
                "rename_auditorium",
                {"tenant": NOVA, "auditorium_id": first_id, "name": new_name}
            );
            assert answer["ok"] , answer;
        }
        assert _screen(app, westgate, "Screen 1")["ok"] , "the renamed-away name is free";
        app.call(
            "owner", "delete_auditorium", {"tenant": NOVA, "auditorium_id": other}
        );
        assert _screen(app, westgate, "Screen 2")["ok"] , "a deleted name is free";
    } finally {
        app.close();
    }
}

test "venue names are unique per cinema" {
    app = _cinema([]);
    try {
        _venue(app, "Westgate");
        again = app.call(
            "owner",
            "create_venue",
            {"tenant": NOVA, "name": "WESTGATE ", "city": "", "address": ""}
        );
        assert _code(again) == "name_taken" , again;
    } finally {
        app.close();
    }
}

test "names and addresses are checked, and nothing is saved on a refusal" {
    app = _cinema([]);
    try {
        for (name, address, code) in [
            ("", "", "invalid_name"),
            ("x" * 81, "", "invalid_name"),
            ("Westgate", "y" * 201, "invalid_address")
        ] {
            answer = app.call(
                "owner",
                "create_venue",
                {"tenant": NOVA, "name": name, "city": "", "address": address}
            );
            assert _code(answer) == code , answer;
        }
        venue = _venue(app, "Westgate")["venue_id"];
        assert _code(_screen(app, venue, "   ")) == "invalid_name";
        venues = app.call("owner", "list_venues", {"tenant": NOVA})["venues"];
        assert [(v["name"], v["auditoriums"]) for v in venues] == [("Westgate", [])];
    } finally {
        app.close();
    }
}

test "a venue with screens can't be deleted until they are" {
    app = _cinema([]);
    try {
        venue = _venue(app, "Westgate")["venue_id"];
        screen = _screen(app, venue, "Screen 1")["auditorium"]["auditorium_id"];
        refused = app.call(
            "owner", "delete_venue", {"tenant": NOVA, "venue_id": venue}
        );
        assert _code(refused) == "venue_not_empty" , refused;
        app.call(
            "owner", "delete_auditorium", {"tenant": NOVA, "auditorium_id": screen}
        );
        assert app.call("owner", "delete_venue", {"tenant": NOVA, "venue_id": venue})[
            "ok"
        ];
        assert app.call("owner", "list_venues", {"tenant": NOVA})["venues"] == [];
        assert _venue(app, "Westgate")["name"] == "Westgate" , "a deleted venue's name is free";
    } finally {
        app.close();
    }
}

test "staff can read venues but only admins change them; venue staff see their venue" {
    app = _cinema(["ann", "sam"]);
    try {
        westgate = _venue(app, "Westgate")["venue_id"];
        _venue(app, "Garden City");
        _staff(app, "ann", "usher", westgate);
        _staff(app, "sam", "tenant_admin", "");
        seen = app.call("ann", "list_venues", {"tenant": NOVA})["venues"];
        assert [v["name"] for v in seen] == ["Westgate"] , seen;
        attempts = [
            (
                "create_venue",
                {"tenant": NOVA, "name": "Rift", "city": "", "address": ""}
            ),
            (
                "update_venue",
                {
                    "tenant": NOVA,
                    "venue_id": westgate,
                    "name": "X",
                    "city": "",
                    "address": ""
                }
            ),
            ("delete_venue", {"tenant": NOVA, "venue_id": westgate}),
            (
                "create_auditorium",
                {"tenant": NOVA, "venue_id": westgate, "name": "Screen 9"}
            )
        ];
        for (name, body) in attempts {
            assert _code(app.call("ann", name, body)) == "forbidden" , name;
        }
        assert app.call(
            "sam",
            "create_auditorium",
            {"tenant": NOVA, "venue_id": westgate, "name": "Screen 9"}
        )["ok"] , "a tenant admin configures venues";
        everything = app.call("sam", "list_venues", {"tenant": NOVA})["venues"];
        assert [v["name"] for v in everything] == ["Garden City", "Westgate"];
    } finally {
        app.close();
    }
}

test "another cinema's venues and screens are not found" {
    app = _cinema(["rival"]);
    try {
        venue = _venue(app, "Westgate")["venue_id"];
        screen = _screen(app, venue, "Screen 1")["auditorium"]["auditorium_id"];
        app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        app.call("rival", "start_shift", {"tenant": "rift"});
        # The rival names their own cinema but aims at Nova's ids.
        attempts = [
            (
                "update_venue",
                {
                    "tenant": "rift",
                    "venue_id": venue,
                    "name": "Mine",
                    "city": "",
                    "address": ""
                }
            ),
            ("delete_venue", {"tenant": "rift", "venue_id": venue}),
            (
                "create_auditorium",
                {"tenant": "rift", "venue_id": venue, "name": "Mine"}
            ),
            (
                "rename_auditorium",
                {"tenant": "rift", "auditorium_id": screen, "name": "Mine"}
            ),
            ("delete_auditorium", {"tenant": "rift", "auditorium_id": screen})
        ];
        for (name, body) in attempts {
            assert _code(app.call("rival", name, body)) == "not_found" , name;
        }
        venues = app.call("owner", "list_venues", {"tenant": NOVA})["venues"];
        assert [(v["name"], [a["name"] for a in v["auditoriums"]]) for v in venues]
            == [("Westgate", ["Screen 1"])] , venues;
    } finally {
        app.close();
    }
}

test "venue changes need an open shift" {
    app = _cinema([]);
    try {
        app.call("owner", "end_shift", {"tenant": NOVA});
        answer = app.call(
            "owner",
            "create_venue",
            {"tenant": NOVA, "name": "Westgate", "city": "", "address": ""}
        );
        assert _code(answer) == "no_shift" , answer;
        assert _code(app.call("owner", "list_venues", {"tenant": NOVA})) == "no_shift";
    } finally {
        app.close();
    }
}
