"""P13.1 and P13.1b.a: AfriCinemas platform staff, their roles and their own accounts.

In-process app (payment_app.jac). boss@example.com is in AFRICINEMAS_PLATFORM_ADMINS,
so a super admin, and joins from the link scripts/platform_setup.jac prints; everyone
else joins from a super admin's invitation. A platform account is apart from any cinema
account with the same email: "owner" runs a cinema and is never platform staff, and
nor is a cinema account signed up as boss@example.com. Platform access follows the
role, looked up fresh on every request: a reviewer can't manage staff, a removed member
loses access at once and their unused link stops working, and the allowlist can't be
changed through the app. Only a super admin from the server's settings makes, changes
or removes super admins. Every staff change is in the platform's own log.
"""

import os;
import from tests.support.served { Served, served }
import from tests.support.harness { Actor }
import from tests.support.storefront_setup { code_of }
import from tests.support.payment_setup { APP }

glob ADMINS: str = "AFRICINEMAS_PLATFORM_ADMINS",
     BOSS: str = "boss@example.com",
     PASSWORD: str = "Platform-Passw0rd!";

def _app -> Served {
    os.environ[ADMINS] = BOSS;
    app = served(APP, ["owner"]);
    _join(app, "boss", app_link(app, BOSS));
    return app;
}

def _close(app: Served) {
    os.environ.pop(ADMINS, None);
    app.close();
}

def _anonymous(app: Served, name: str, body: dict[str, any]) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token("");
    resp = app.client.post(f"/function/{name}", json=body);
    assert resp.status_code == 200 , f"{name}: {resp.status_code} {resp.text}";
    return resp.data["result"];
}

def app_link(app: Served, email: str) -> str {
    # The setup link's token, as scripts/platform_setup.jac prints it.
    return _anonymous(app, "t_platform_setup_link", {"email": email});
}

def _join(app: Served, label: str, token: str) -> any {  # jac:ignore[W1037]
    # Sets the password from a join link and signs in as `label`.
    joined = _anonymous(app, "platform_join", {"token": token, "password": PASSWORD});
    assert joined["ok"] , joined;
    login = app.client.login(joined["sign_in_name"], PASSWORD);
    assert login.ok , login.text;
    data: dict[str, any] = login.data or {};  # jac:ignore[W1037]
    app.actors[label] = Actor(
        username=joined["sign_in_name"],
        user_id=str(data.get("user_id", "")),
        root_id=str(data.get("root_id", "")),
        token=str(data["token"])
    );
    return joined;
}

def _invite(app: Served, label: str, email: str, role: str) -> str {
    # boss invites `email`; the invitation's token.
    invited = app.call(label, "invite_platform_member", {"email": email, "role": role});
    assert invited["ok"] , invited;
    assert invited["expires_in_hours"] == 72;
    return invited["token"];
}

test "a settings super admin joins from the setup link; a cinema account is never staff" {
    app = _app();
    try {
        boss = app.call("boss", "platform_whoami");
        assert boss["platform"] and boss["role"] == "super_admin" , boss;
        assert boss["email"] == BOSS and boss["settings_admin"];
        assert app.call("owner", "platform_whoami") == {"ok": True, "platform": False};
        # A cinema account with the super admin's email is still only a cinema account.
        same = app.client.register_user(BOSS, PASSWORD);
        if same.ok {
            app.actors["lookalike"] = Actor(
                username=BOSS,
                user_id=str(same.data["user_id"]),
                root_id=str(same.data["root_id"]),
                token=str(same.data["token"])
            );
            assert app.call("lookalike", "platform_whoami")["platform"] == False;
        }
        for (name, body) in [
            ("platform_staff", {}),
            ("invite_platform_member", {"email": "x@example.com", "role": "support"}),
            ("set_platform_role", {"email": BOSS, "role": "support"}),
            ("remove_platform_staff", {"email": BOSS})
        ] {
            assert code_of(app.call("owner", name, body)) == "not_platform" , name;
        }
        listed = app.call("boss", "platform_staff");
        assert listed["staff"]
            == [
                {
                    "email": BOSS,
                    "role": "super_admin",
                    "role_label": "Super admin",
                    "fixed": True,
                    "joined": True
                }
            ] , listed;
        # A platform account can't run a cinema or join one's staff.
        made = app.call(
            "boss", "create_cinema", {"name": "Boss Cinema", "slug": "boss-cin"}
        );
        assert made["error"]["code"] == "platform_account" , made;
    } finally {
        _close(app);
    }
}

test "a join link works once, keeps working after a weak password, and expires on removal" {
    app = _app();
    try {
        token = _invite(app, "boss", "rev@example.com", "reviewer");
        weak = _anonymous(app, "platform_join", {"token": token, "password": "short"});
        assert code_of(weak) == "weak_password" , weak;
        _join(app, "rev", token);
        again = _anonymous(
            app, "platform_join", {"token": token, "password": PASSWORD}
        );
        assert code_of(again) == "invalid_link" , again;
        made_up = _anonymous(
            app, "platform_join", {"token": "made-up-token", "password": PASSWORD}
        );
        assert code_of(made_up) == "invalid_link";
        # Someone who has joined can't be invited again: the link would reset their
        # password.
        assert code_of(
            app.call(
                "boss",
                "invite_platform_member",
                {"email": "rev@example.com", "role": "support"}
            )
        )
            == "already_staff";
        # Removed before joining: the invitation stops working.
        pending = _invite(app, "boss", "helper@example.com", "support");
        rows = {r["email"]: r for r in app.call("boss", "platform_staff")["staff"]};
        assert rows["helper@example.com"]["joined"] == False;
        assert rows["rev@example.com"]["joined"] == True;
        app.call("boss", "remove_platform_staff", {"email": "helper@example.com"});
        late = _anonymous(
            app, "platform_join", {"token": pending, "password": PASSWORD}
        );
        assert code_of(late) == "invalid_link" , late;
        # A new invitation replaces the last one.
        first = _invite(app, "boss", "late@example.com", "support");
        second = _invite(app, "boss", "late@example.com", "support");
        assert code_of(
            _anonymous(app, "platform_join", {"token": first, "password": PASSWORD})
        )
            == "invalid_link";
        _join(app, "late", second);
    } finally {
        _close(app);
    }
}

test "each role reaches only its own actions, and removal applies at once" {
    app = _app();
    try {
        _join(app, "rev", _invite(app, "boss", "rev@example.com", "reviewer"));
        _join(app, "helper", _invite(app, "boss", "helper@example.com", "support"));
        rev = app.call("rev", "platform_whoami");
        assert rev["role"] == "reviewer" and "platform.review" in rev["permissions"];
        assert "platform.staff" not in rev["permissions"];
        assert code_of(app.call("rev", "platform_staff")) == "not_allowed";
        assert code_of(
            app.call(
                "rev",
                "invite_platform_member",
                {"email": "x@example.com", "role": "support"}
            )
        )
            == "not_allowed";
        helper = app.call("helper", "platform_whoami");
        assert helper["role"] == "support"
            and "platform.review" not in helper["permissions"];
        # A change of role applies at once.
        app.call(
            "boss",
            "set_platform_role",
            {"email": "rev@example.com", "role": "super_admin"}
        );
        assert app.call("rev", "platform_staff")["ok"];
        # Removed: refused on the very next request.
        assert app.call("boss", "remove_platform_staff", {"email": "rev@example.com"})[
            "ok"
        ];
        assert code_of(app.call("rev", "platform_staff")) == "not_platform";
        assert app.call("rev", "platform_whoami")["platform"] == False;
        assert [s["email"] for s in app.call("boss", "platform_staff")["staff"]]
            == [BOSS, "helper@example.com"];
    } finally {
        _close(app);
    }
}

test "only a super admin from the server's settings manages super admins" {
    app = _app();
    try {
        _join(app, "rev", _invite(app, "boss", "rev@example.com", "super_admin"));
        _invite(app, "boss", "helper@example.com", "support");
        rev = app.call("rev", "platform_whoami");
        assert rev["role"] == "super_admin" and not rev["settings_admin"] , rev;
        # A super admin made here manages reviewers and support...
        assert app.call(
            "rev",
            "set_platform_role",
            {"email": "helper@example.com", "role": "reviewer"}
        )["ok"];
        # ...but makes no super admins, and changes or removes none.
        for (name, body) in [
            (
                "invite_platform_member",
                {"email": "sa@example.com", "role": "super_admin"}
            ),
            (
                "set_platform_role",
                {"email": "helper@example.com", "role": "super_admin"}
            )
        ] {
            assert code_of(app.call("rev", name, body)) == "not_allowed" , name;
        }
        app.call(
            "boss",
            "set_platform_role",
            {"email": "helper@example.com", "role": "super_admin"}
        );
        assert code_of(
            app.call(
                "rev",
                "set_platform_role",
                {"email": "helper@example.com", "role": "support"}
            )
        )
            == "not_allowed";
        assert code_of(
            app.call("rev", "remove_platform_staff", {"email": "helper@example.com"})
        )
            == "not_allowed";
        # The refusal never says why, and the list doesn't say which super admins are
        # the settings' to anyone but them.
        refused = app.call(
            "rev", "set_platform_role", {"email": BOSS, "role": "support"}
        );
        assert refused["error"]
            == {
                "code": "not_allowed",
                "message": "Your platform role can't do this."
            } , refused;
        assert not any(r["fixed"] for r in app.call("rev", "platform_staff")["staff"]);
        assert any(r["fixed"] for r in app.call("boss", "platform_staff")["staff"]);
        # The settings' super admin can.
        assert app.call(
            "boss", "remove_platform_staff", {"email": "helper@example.com"}
        )["ok"];
    } finally {
        _close(app);
    }
}

test "the allowlist can't be changed in the app, and Jac's own sign-up can't make staff" {
    app = _app();
    try {
        for (name, body) in [
            ("set_platform_role", {"email": BOSS, "role": "support"}),
            ("remove_platform_staff", {"email": BOSS}),
            ("invite_platform_member", {"email": BOSS, "role": "support"})
        ] {
            assert code_of(app.call("boss", name, body)) == "not_allowed" , name;
        }
        assert code_of(
            app.call(
                "boss",
                "invite_platform_member",
                {"email": "nova:kim:example.com", "role": "support"}
            )
        )
            == "invalid_email";
        assert code_of(
            app.call(
                "boss",
                "invite_platform_member",
                {"email": "x@example.com", "role": "owner"}
            )
        )
            == "invalid_role";
        assert code_of(
            app.call("boss", "remove_platform_staff", {"email": "nobody@example.com"})
        )
            == "not_staff";
        # Someone takes the platform name through Jac's own sign-up before the invitee
        # joins: it's no one's platform account, and joining replaces it.
        squat = app.client.register_user("platform:sam:example.com", PASSWORD);
        token = _invite(app, "boss", "sam@example.com", "support");
        if squat.ok {
            app.actors["squatter"] = Actor(
                username="platform:sam:example.com",
                user_id=str(squat.data["user_id"]),
                root_id=str(squat.data["root_id"]),
                token=str(squat.data["token"])
            );
            assert app.call("squatter", "platform_whoami")["platform"] == False;
        }
        _join(app, "sam", token);
        assert app.call("sam", "platform_whoami")["role"] == "support";
        if squat.ok {
            # The squatter's session is refused outright, or still no one's staff.
            after = app.post("squatter", "platform_whoami");
            assert after.status_code != 200
                or after.data["result"]["platform"] == False;
        }
        # Taken off the allowlist in the server's settings, the boss loses access.
        os.environ[ADMINS] = "someone-else@example.com";
        assert code_of(app.call("boss", "platform_staff")) == "not_platform";
    } finally {
        _close(app);
    }
}

test "staff changes are recorded in the platform's own log" {
    app = _app();
    try {
        _join(app, "rev", _invite(app, "boss", "rev@example.com", "reviewer"));
        app.call("boss", "remove_platform_staff", {"email": "rev@example.com"});
        logged = app.call("boss", "t_platform_events");
        actions = [(e["action"], e["resource_id"], e["result"]) for e in logged];
        for wanted in [
            ("platform.joined", BOSS, "ok"),
            ("platform.staff_invited", "rev@example.com", "ok"),
            ("platform.joined", "rev@example.com", "ok"),
            ("platform.staff_removed", "rev@example.com", "ok")
        ] {
            assert wanted in actions , actions;
        }
    } finally {
        _close(app);
    }
}
