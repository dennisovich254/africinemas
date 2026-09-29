"""P2.5: staff invitations and lifecycle, through the production app (main.jac).

An owner invites someone with a role; the invitee accepts in their own request (the
membership edge must come from their own root, ADR-0004). Roles live on the tenant's
Membership record, so owners and admins can change, disable or remove them, and the
change applies on the member's next call, whatever their token says (ADR-0008).
"""

import os;
import time;
import from os { path }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     TTL_ENV: str = "AFRICINEMAS_INVITE_TTL_S";

def _cinema(names: list[str]) -> Served {
    app = served(MAIN, ["owner"] + names);
    app.call("owner", "create_cinema", {"name": "Nova Cinemas", "slug": "nova"});
    app.call("owner", "start_shift", {"tenant": "nova"});
    return app;
}

def _invite(app: Served, who: str, role: str, venue: str = "") -> any {  # jac:ignore[W1037]
    return app.call(
        who, "invite_staff", {"tenant": "nova", "role": role, "venue_id": venue}
    );
}

def _hire(app: Served, who: str, role: str, venue: str = "") -> str {
    # Owner invites `who` as `role`; `who` accepts. Returns their member id.
    token = _invite(app, "owner", role, venue)["token"];
    accepted = app.call(who, "accept_invite", {"token": token});
    assert accepted["ok"] , accepted;
    app.call(who, "start_shift", {"tenant": "nova"});
    return accepted["member_id"];
}

def _roles_of(app: Served, member_id: str) -> list[str] {
    for s in app.call("owner", "list_staff", {"tenant": "nova"})["staff"] {
        if s["member_id"] == member_id {
            return s["roles"];
        }
    }
    return [];
}

test "accepting an invite assigns exactly the invited role" {
    app = _cinema(["ann"]);
    try {
        invite = _invite(app, "owner", "usher");
        assert invite["ok"] and invite["token"] and invite["expires_at"] , invite;
        accepted = app.call("ann", "accept_invite", {"token": invite["token"]});
        assert accepted["ok"]
            and accepted["slug"] == "nova"
            and accepted["roles"] == ["usher"] , accepted;
        access = app.call("ann", "my_access", {"tenant": "nova"});
        assert access["assignments"] == [{"role": "usher", "venue_ids": None}] , access;
        assert _roles_of(app, accepted["member_id"]) == ["usher"];
    } finally {
        app.close();
    }
}

test "a venue invite gives a venue-scoped role" {
    app = _cinema(["ann"]);
    try {
        venue = app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Westgate", "city": "", "address": ""}
        )["venue"]["venue_id"];
        _hire(app, "ann", "usher", venue);
        access = app.call("ann", "my_access", {"tenant": "nova"});
        assert access["assignments"]
            == [{"role": "usher", "venue_ids": [venue]}] , access;
    } finally {
        app.close();
    }
}

test "an invite works once" {
    app = _cinema(["ann", "bob"]);
    try {
        token = _invite(app, "owner", "usher")["token"];
        assert app.call("ann", "accept_invite", {"token": token})["ok"];
        again = app.call("bob", "accept_invite", {"token": token});
        assert again["ok"] == False
            and again["error"]["code"] == "invalid_invite" , again;
        assert app.call("bob", "my_access", {"tenant": "nova"})["ok"] == False;
    } finally {
        app.close();
    }
}

test "an expired invite is refused and joins nobody" {
    os.environ[TTL_ENV] = "1";
    app = _cinema(["ann"]);
    try {
        token = _invite(app, "owner", "usher")["token"];
        time.sleep(1.5);
        late = app.call("ann", "accept_invite", {"token": token});
        assert late["ok"] == False and late["error"]["code"] == "invalid_invite" , late;
        assert app.call("ann", "my_access", {"tenant": "nova"})["ok"] == False;
    } finally {
        os.environ.pop(TTL_ENV, None);
        app.close();
    }
}

test "role changes, disabling and removal apply on the next call, same token" {
    app = _cinema(["ann"]);
    try {
        ann = _hire(app, "ann", "usher");
        assert not app.call("ann", "rename_cinema", {"tenant": "nova", "name": "X"})[
            "ok"
        ];
        changed = app.call(
            "owner",
            "change_staff_roles",
            {"tenant": "nova", "member_id": ann, "roles": ["tenant_admin"]}
        );
        assert changed["ok"] , changed;
        assert app.call("ann", "rename_cinema", {"tenant": "nova", "name": "Nova Two"})[
            "ok"
        ] , "promotion applies at once";
        app.call(
            "owner",
            "set_staff_status",
            {"tenant": "nova", "member_id": ann, "status": "disabled"}
        );
        assert app.call("ann", "my_access", {"tenant": "nova"})["error"]["code"]
            == "not_found" , "disabled at once";
        app.call(
            "owner",
            "set_staff_status",
            {"tenant": "nova", "member_id": ann, "status": "active"}
        );
        assert app.call("ann", "my_access", {"tenant": "nova"})["ok"] , "re-enabled at once";
        assert app.call("owner", "remove_staff", {"tenant": "nova", "member_id": ann})[
            "ok"
        ];
        assert app.call("ann", "my_access", {"tenant": "nova"})["error"]["code"]
            == "not_found";
        assert _roles_of(app, ann) == [] , "gone from the staff list";
    } finally {
        app.close();
    }
}

test "nobody can grant a role with permissions they don't hold" {
    app = _cinema(["manager", "agent", "cat"]);
    try {
        admin = _hire(app, "manager", "tenant_admin");
        _hire(app, "agent", "box_office_agent");
        for role in ["owner", "finance_manager"] {
            refused = _invite(app, "manager", role);
            assert refused["error"]["code"] == "forbidden" , f"admin invited {role}: {refused}";
        }
        assert _invite(app, "manager", "usher")["ok"] , "admin can invite roles within their own powers";
        assert _invite(app, "agent", "usher")["error"]["code"] == "forbidden" , "agents can't invite";
        cat = _hire(app, "cat", "usher");
        up = app.call(
            "manager",
            "change_staff_roles",
            {"tenant": "nova", "member_id": cat, "roles": ["owner"]}
        );
        assert up["error"]["code"] == "forbidden" , up;
        assert _roles_of(app, cat) == ["usher"];
        assert admin;
    } finally {
        app.close();
    }
}

test "nobody can change or remove their own membership" {
    app = _cinema(["manager"]);
    try {
        admin = _hire(app, "manager", "tenant_admin");
        owner_id = [
            s
            for s in app.call("owner", "list_staff", {"tenant": "nova"})["staff"]
            if "owner" in s["roles"]
        ][0]["member_id"];
        for (who, member) in [("owner", owner_id), ("manager", admin)] {
            for (endpoint, extra) in [
                ("change_staff_roles", {"roles": ["usher"]}),
                ("set_staff_status", {"status": "disabled"}),
                ("remove_staff", {})
            ] {
                body = {"tenant": "nova", "member_id": member} | extra;
                refused = app.call(who, endpoint, body);
                assert refused["error"]["code"] == "self_change" , f"{who} {endpoint}: {refused}";
            }
        }
        assert "owner" in _roles_of(app, owner_id);
    } finally {
        app.close();
    }
}

test "invalid roles and venue scopes are refused" {
    app = _cinema(["ann"]);
    try {
        for (role, venue, code) in [
            ("projectionist", "", "invalid_role"),
            ("finance_manager", "venue-1", "invalid_role")
        ] {
            refused = _invite(app, "owner", role, venue);
            assert refused["error"]["code"] == code , f"{role}@{venue}: {refused}";
        }
    } finally {
        app.close();
    }
}
