"""P13.1: AfriCinemas platform staff and their roles.

In-process app (payment_app.jac). "boss" is in AFRICINEMAS_PLATFORM_ADMINS, so a super
admin; "owner" runs a cinema and isn't platform staff; "rev" and "helper" are added by
the boss. Platform access follows the role, looked up fresh on every request: a cinema
owner is refused everything as not_platform, a reviewer can't manage staff, a removed
member loses access at once, and the allowlist can't be changed through the app. Only a
super admin from the server's settings makes, changes or removes super admins. A
customer account can never be added. Every staff change is in the platform's own log.
"""

import os;
import from tests.support.served { Served, served }
import from tests.support.storefront_setup { code_of }
import from tests.support.payment_setup { APP }

glob ADMINS: str = "AFRICINEMAS_PLATFORM_ADMINS";

def _app -> Served {
    os.environ[ADMINS] = "boss";
    app = served(APP, ["boss", "owner", "rev", "helper"]);
    # Each links their sign-in to their root, as the console does when it opens.
    for who in ["boss", "owner", "rev", "helper"] {
        app.call(who, "platform_whoami", {"email": who});
    }
    return app;
}

def _close(app: Served) {
    os.environ.pop(ADMINS, None);
    app.close();
}

test "the allowlisted email is a super admin, and a cinema owner isn't platform staff" {
    app = _app();
    try {
        boss = app.call("boss", "platform_whoami", {"email": "boss"});
        assert boss["platform"] and boss["role"] == "super_admin" , boss;
        assert "platform.staff" in boss["permissions"];
        owner = app.call("owner", "platform_whoami", {"email": "owner"});
        assert owner == {"ok": True, "platform": False} , owner;
        # Claiming someone else's sign-in gets nothing.
        pretend = app.call("owner", "platform_whoami", {"email": "boss"});
        assert pretend == {"ok": True, "platform": False} , pretend;
        for (name, body) in [
            ("platform_staff", {}),
            ("set_platform_role", {"email": "owner", "role": "super_admin"}),
            ("remove_platform_staff", {"email": "boss"})
        ] {
            assert code_of(app.call("owner", name, body)) == "not_platform" , name;
        }
        listed = app.call("boss", "platform_staff");
        assert listed["staff"]
            == [
                {
                    "email": "boss",
                    "role": "super_admin",
                    "role_label": "Super admin",
                    "fixed": True
                }
            ] , listed;
    } finally {
        _close(app);
    }
}

test "a super admin adds and removes staff; each role reaches only its own actions" {
    app = _app();
    try {
        added = app.call(
            "boss", "set_platform_role", {"email": "rev", "role": "reviewer"}
        );
        assert added["ok"] , added;
        app.call("boss", "set_platform_role", {"email": "helper", "role": "support"});
        rev = app.call("rev", "platform_whoami", {"email": "rev"});
        assert rev["role"] == "reviewer" and "platform.review" in rev["permissions"];
        assert "platform.staff" not in rev["permissions"];
        assert code_of(app.call("rev", "platform_staff")) == "not_allowed";
        helper = app.call("helper", "platform_whoami", {"email": "helper"});
        assert helper["role"] == "support"
            and "platform.review" not in helper["permissions"];
        # A change of role applies at once.
        app.call("boss", "set_platform_role", {"email": "rev", "role": "super_admin"});
        assert app.call("rev", "platform_staff")["ok"];
        # Removed: refused on the very next request.
        assert app.call("boss", "remove_platform_staff", {"email": "rev"})["ok"];
        assert code_of(app.call("rev", "platform_staff")) == "not_platform";
        assert app.call("rev", "platform_whoami", {"email": "rev"})["platform"]
            == False;
        assert [s["email"] for s in app.call("boss", "platform_staff")["staff"]]
            == ["boss", "helper"];
    } finally {
        _close(app);
    }
}

test "only a super admin from the server's settings manages super admins" {
    app = _app();
    try {
        assert app.call("boss", "platform_whoami", {"email": "boss"})["settings_admin"];
        app.call("boss", "set_platform_role", {"email": "rev", "role": "super_admin"});
        app.call("boss", "set_platform_role", {"email": "helper", "role": "support"});
        rev = app.call("rev", "platform_whoami", {"email": "rev"});
        assert rev["role"] == "super_admin" and not rev["settings_admin"] , rev;
        # A super admin made here manages reviewers and support...
        assert app.call(
            "rev", "set_platform_role", {"email": "helper", "role": "reviewer"}
        )["ok"];
        # ...but makes no super admins, and changes or removes none.
        assert code_of(
            app.call(
                "rev", "set_platform_role", {"email": "helper", "role": "super_admin"}
            )
        )
            == "only_settings_admins";
        app.call(
            "boss", "set_platform_role", {"email": "helper", "role": "super_admin"}
        );
        assert code_of(
            app.call("rev", "set_platform_role", {"email": "helper", "role": "support"})
        )
            == "only_settings_admins";
        assert code_of(app.call("rev", "remove_platform_staff", {"email": "helper"}))
            == "only_settings_admins";
        # The settings' super admin can.
        assert app.call("boss", "remove_platform_staff", {"email": "helper"})["ok"];
    } finally {
        _close(app);
    }
}

test "the allowlist can't be changed in the app, and a customer can't be added" {
    app = _app();
    try {
        assert code_of(
            app.call("boss", "set_platform_role", {"email": "boss", "role": "support"})
        )
            == "fixed_admin";
        assert code_of(app.call("boss", "remove_platform_staff", {"email": "boss"}))
            == "fixed_admin";
        assert code_of(
            app.call(
                "boss",
                "set_platform_role",
                {"email": "nova:kim:example.com", "role": "support"}
            )
        )
            == "invalid_email";
        assert code_of(
            app.call("boss", "set_platform_role", {"email": "helper", "role": "owner"})
        )
            == "invalid_role";
        assert code_of(app.call("boss", "remove_platform_staff", {"email": "nobody"}))
            == "not_staff";
        # Taken off the allowlist in the server's settings, the boss loses access.
        os.environ[ADMINS] = "someone-else";
        assert code_of(app.call("boss", "platform_staff")) == "not_platform";
    } finally {
        _close(app);
    }
}

test "staff changes are recorded in the platform's own log" {
    app = _app();
    try {
        app.call("boss", "set_platform_role", {"email": "rev", "role": "reviewer"});
        app.call("boss", "remove_platform_staff", {"email": "rev"});
        logged = app.call("boss", "t_platform_events");
        actions = [(e["action"], e["resource_id"], e["result"]) for e in logged];
        assert ("platform.staff_role_set", "rev", "ok") in actions , actions;
        assert ("platform.staff_removed", "rev", "ok") in actions , actions;
        assert all(e["actor"] == "boss" for e in logged) , logged;
    } finally {
        _close(app);
    }
}
