"""P13.3: the AfriCinemas platform's own audit log.

In-process app (payment_app.jac). The settings' super admin (boss) joins, signs in and
invites a reviewer, who joins too; then a cinema owner and the reviewer each try to
invite someone and are refused. Every one of those is in the platform's log, newest
first, with who did it and the result; the refusals too. The log is searched by who
did it or who it was done to, narrowed by action and by cinema, and read in pages.
Only super admins read it. Reading it changes nothing.
"""

import os;
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of }
import from tests.support.payment_setup { paying_cinema }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

glob BOSS: str = "boss@example.com",
     REV: str = "rev@example.com";

def _app -> Served {
    (app, _, _) = paying_cinema([]);
    super_admin(app, "boss", BOSS);
    assert app.call("boss", "platform_signed_in")["ok"];
    invited = app.call(
        "boss", "invite_platform_member", {"email": REV, "role": "reviewer"}
    );
    join_platform(app, "rev", invited["token"]);
    # Refused: a cinema owner, and a reviewer who may not manage staff.
    for who in ["owner", "rev"] {
        tried = app.call(
            who,
            "invite_platform_member",
            {"email": "sneaky@example.com", "role": "super_admin"}
        );
        assert not tried["ok"] , tried;
    }
    return app;
}

def _close(app: Served) {
    os.environ.pop(ADMINS_ENV, None);
    app.close();
}

def _log(app: Served, body: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    asked = {"limit": 50};
    asked.update(body);
    found = app.call("boss", "platform_audit_log", asked);
    assert found["ok"] , found;
    return found;
}

def _seen(found: dict[str, any]) -> list[tuple[str, str, str, str]] {  # jac:ignore[W1037]
    return [
        (e["action"], e["actor"], e["resource_id"], e["result"])
        for e in found["events"]
    ];
}

test "every platform action is recorded, newest first, refused attempts too" {
    app = _app();
    try {
        found = _log(app, {});
        assert _seen(found)
            == [
                ("platform.staff_invited", REV, "sneaky@example.com", "not_allowed"),
                ("platform.staff_invited", "", "sneaky@example.com", "not_platform"),
                ("platform.joined", REV, REV, "ok"),
                ("platform.staff_invited", BOSS, REV, "ok"),
                ("platform.signed_in", BOSS, BOSS, "ok"),
                ("platform.joined", BOSS, BOSS, "ok")
            ] , _seen(found);
        assert found["total"] == 6 and found["next"] == "";
        assert all([e["at"] for e in found["events"]]);
        # Never a token or password.
        shown = str(found).lower();
        assert "passw0rd" not in shown and "token" not in shown;
    } finally {
        _close(app);
    }
}

test "the log is searched by who and to whom, narrowed by action and cinema, and paged" {
    app = _app();
    try {
        about_rev = _seen(_log(app, {"search": "REV@"}));
        assert [a for (a, _, _, _) in about_rev]
            == [
                "platform.staff_invited",
                "platform.joined",
                "platform.staff_invited"
            ] , about_rev;
        joins = _seen(_log(app, {"action": "platform.joined"}));
        assert [w for (_, w, _, _) in joins] == [REV, BOSS] , joins;
        # No platform action has been about a cinema yet (reviews come in Phase 14).
        assert _log(app, {"cinema": "nova"})["events"] == [];
        assert code_of(
            app.call("boss", "platform_audit_log", {"limit": 5, "cinema": "no-such"})
        )
            == "not_found";
        # In pages of two: three pages, the same six events in order.
        pages: list[list[str]] = [];
        before = "";
        for _ in range(4) {
            page = _log(app, {"limit": 2, "before": before});
            assert page["total"] == 6;
            pages.append([e["action"] for e in page["events"]]);
            before = page["next"];
            if not before {
                break;
            }
        }
        assert len(pages) == 3 and sum([len(p) for p in pages]) == 6 , pages;
        assert code_of(app.call("boss", "platform_audit_log", {"limit": 0}))
            == "bad_limit";
    } finally {
        _close(app);
    }
}

test "only super admins read the log, and reading it changes nothing" {
    app = _app();
    try {
        first = _log(app, {});
        assert code_of(app.call("rev", "platform_audit_log", {"limit": 5}))
            == "not_allowed";
        assert code_of(app.call("owner", "platform_audit_log", {"limit": 5}))
            == "not_platform";
        # A cinema account can't report a platform sign-in either.
        assert code_of(app.call("owner", "platform_signed_in")) == "not_platform";
        again = _log(app, {});
        assert again["events"] == first["events"] , "reading the log changed it";
    } finally {
        _close(app);
    }
}
