"""P3.1: staff roles limited to a venue must name a real venue of the same cinema.

Venue ids reach staff roles through invite_staff, change_staff_roles and accept_invite.
Each checks the venue exists at this cinema (not another cinema's, not made up), and a
venue can't be deleted while staff hold a role there, so a stored role never points at
nothing.
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

def _venue(app: Served, who: str, tenant: str, name: str) -> str {
    answer = app.call(
        who, "create_venue", {"tenant": tenant, "name": name, "city": "", "address": ""}
    );
    assert answer["ok"] , answer;
    return answer["venue"]["venue_id"];
}

def _rival_venue(app: Served) -> str {
    # A venue of another cinema, "rift", run by the actor "rival".
    app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
    app.call("rival", "start_shift", {"tenant": "rift"});
    return _venue(app, "rival", "rift", "Rift Mall");
}

def _invite(app: Served, role: str, venue_id: str) -> any {  # jac:ignore[W1037]
    return app.call(
        "owner", "invite_staff", {"tenant": NOVA, "role": role, "venue_id": venue_id}
    );
}

def _hire(app: Served, who: str, role: str, venue_id: str) -> str {
    # `who` joins Nova with `role` (at `venue_id`); returns their member id.
    token = _invite(app, role, venue_id)["token"];
    return app.call(who, "accept_invite", {"token": token})["member_id"];
}

def _roles(app: Served, member_id: str) -> list[str] {
    staff = app.call("owner", "list_staff", {"tenant": NOVA})["staff"];
    return [
        s["roles"]
        for s in staff
        if s["member_id"] == member_id
    ][0];
}

def _code(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

test "an invitation can only limit a role to one of this cinema's venues" {
    app = _cinema(["ann", "rival"]);
    try {
        westgate = _venue(app, "owner", NOVA, "Westgate");
        _venue(app, "owner", NOVA, "Garden City");
        for bad in ["venue-1", "not-a-uuid", _rival_venue(app), "  "] {
            answer = _invite(app, "usher", bad);
            assert _code(answer) == "unknown_venue" , f"{bad!r}: {answer}";
            assert "token" not in answer , "no invitation is made";
        }
        # A cinema-wide role given a venue is still a role error, whatever the venue.
        assert _code(_invite(app, "finance_manager", westgate)) == "invalid_role";
        member = _hire(app, "ann", "usher", westgate);
        assert _roles(app, member) == [f"usher@{westgate}"];
        app.call("ann", "start_shift", {"tenant": NOVA});
        seen = app.call("ann", "list_venues", {"tenant": NOVA})["venues"];
        assert [v["venue_id"] for v in seen] == [westgate] , seen;
    } finally {
        app.close();
    }
}

test "a role change can only limit roles to this cinema's venues" {
    app = _cinema(["ann", "rival"]);
    try {
        westgate = _venue(app, "owner", NOVA, "Westgate");
        member = _hire(app, "ann", "usher", "");
        for bad_roles in [
            ["usher@venue-1"],
            [f"usher@{_rival_venue(app)}"],
            [f"usher@{westgate}", "box_office_agent@venue-9"]
        ] {
            answer = app.call(
                "owner",
                "change_staff_roles",
                {"tenant": NOVA, "member_id": member, "roles": bad_roles}
            );
            assert _code(answer) == "unknown_venue" , f"{bad_roles}: {answer}";
            assert _roles(app, member) == ["usher"] , "roles are unchanged";
        }
        ok = app.call(
            "owner",
            "change_staff_roles",
            {
                "tenant": NOVA,
                "member_id": member,
                "roles": [f"usher@{westgate}", f"box_office_agent@{westgate}"]
            }
        );
        assert ok["ok"] , ok;
        assert _roles(app, member)
            == sorted([f"box_office_agent@{westgate}", f"usher@{westgate}"]);
    } finally {
        app.close();
    }
}

test "an invitation to a venue deleted since it was sent is refused" {
    app = _cinema(["ann"]);
    try {
        westgate = _venue(app, "owner", NOVA, "Westgate");
        token = _invite(app, "usher", westgate)["token"];
        assert app.call("owner", "delete_venue", {"tenant": NOVA, "venue_id": westgate})[
            "ok"
        ] , "nobody works there yet";
        answer = app.call("ann", "accept_invite", {"token": token});
        assert _code(answer) == "invalid_invite" , answer;
        assert app.call("ann", "my_cinemas", {}) == [] , "ann didn't join";
        again = app.call("ann", "accept_invite", {"token": token});
        assert _code(again) == "invalid_invite" , again;
    } finally {
        app.close();
    }
}

test "a venue can't be deleted while staff hold a role there" {
    app = _cinema(["ann", "bob"]);
    try {
        westgate = _venue(app, "owner", NOVA, "Westgate");
        garden = _venue(app, "owner", NOVA, "Garden City");
        ann = _hire(app, "ann", "usher", westgate);
        bob = _hire(app, "bob", "box_office_agent", garden);
        delete = lambda (venue: str) -> any { return app.call(
            "owner", "delete_venue", {"tenant": NOVA, "venue_id": venue}
        ); };
        assert _code(delete(westgate)) == "venue_has_staff";
        # A disabled member still holds the role, and could be re-enabled.
        app.call(
            "owner",
            "set_staff_status",
            {"tenant": NOVA, "member_id": ann, "status": "disabled"}
        );
        assert _code(delete(westgate)) == "venue_has_staff";
        app.call(
            "owner",
            "change_staff_roles",
            {"tenant": NOVA, "member_id": ann, "roles": ["usher"]}
        );
        assert delete(westgate)["ok"] , "ann's role no longer names it";
        app.call("owner", "remove_staff", {"tenant": NOVA, "member_id": bob});
        assert delete(garden)["ok"] , "bob was removed";
        assert app.call("owner", "list_venues", {"tenant": NOVA})["venues"] == [];
    } finally {
        app.close();
    }
}
