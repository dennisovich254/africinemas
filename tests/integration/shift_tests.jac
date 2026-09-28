"""P2.7a: staff shift sessions (ADR-0006), through the production app (main.jac).

Jac tokens last at least a day and can't be revoked, so staff actions also need a live
shift on the server: opened with start_shift, ended by end_shift (and by logout in the
UI), expiring on its own after the shift length. `my_access` works without a shift so
the UI can show someone their cinemas and roles before they start.
"""

import os;
import time;
import from os { path }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     TTL_ENV: str = "AFRICINEMAS_SHIFT_TTL_S";

def _cinemas(names: list[str]) -> Served {
    app = served(MAIN, ["owner_a", "owner_b"] + names);
    app.call("owner_a", "create_cinema", {"name": "Nova Cinemas", "slug": "nova"});
    app.call("owner_b", "create_cinema", {"name": "Imax Rift", "slug": "imax-rift"});
    return app;
}

def _rename(app: Served, who: str, slug: str, name: str) -> any {  # jac:ignore[W1037]
    return app.call(who, "rename_cinema", {"tenant": slug, "name": name});
}

test "staff actions need an open shift, even for the owner" {
    app = _cinemas([]);
    try {
        refused = _rename(app, "owner_a", "nova", "Nova Two");
        assert refused
            == {
                "ok": False,
                "error": {
                    "code": "no_shift",
                    "message": "Start your shift to continue."
                }
            } , refused;
        assert app.call("owner_a", "my_access", {"tenant": "nova"})["ok"] , "roles are visible before a shift";
        opened = app.call("owner_a", "start_shift", {"tenant": "nova"});
        assert opened["ok"] and opened["expires_at"] , opened;
        assert _rename(app, "owner_a", "nova", "Nova Two")["ok"];
    } finally {
        app.close();
    }
}

test "ending the shift closes access at once" {
    app = _cinemas([]);
    try {
        app.call("owner_a", "start_shift", {"tenant": "nova"});
        assert app.call("owner_a", "end_shift", {"tenant": "nova"}) == {"ok": True};
        assert _rename(app, "owner_a", "nova", "X")["error"]["code"] == "no_shift";
    } finally {
        app.close();
    }
}

test "a shift expires on its own" {
    os.environ[TTL_ENV] = "1";
    app = _cinemas([]);
    try {
        app.call("owner_a", "start_shift", {"tenant": "nova"});
        assert _rename(app, "owner_a", "nova", "Nova Two")["ok"];
        time.sleep(1.5);
        assert _rename(app, "owner_a", "nova", "Nova Three")["error"]["code"]
            == "no_shift";
        app.call("owner_a", "start_shift", {"tenant": "nova"});
        assert _rename(app, "owner_a", "nova", "Nova Three")["ok"] , "a new shift works again";
    } finally {
        os.environ.pop(TTL_ENV, None);
        app.close();
    }
}

test "a shift opens one cinema only" {
    app = _cinemas(["sam"]);
    try {
        for (owner, slug) in [("owner_a", "nova"), ("owner_b", "imax-rift")] {
            app.call(owner, "start_shift", {"tenant": slug});
            token = app.call(
                owner,
                "invite_staff",
                {"tenant": slug, "role": "tenant_admin", "venue_id": ""}
            )["token"];
            app.call("sam", "accept_invite", {"token": token});
        }
        app.call("sam", "start_shift", {"tenant": "nova"});
        assert _rename(app, "sam", "nova", "Nova Two")["ok"];
        assert _rename(app, "sam", "imax-rift", "Rift Two")["error"]["code"]
            == "no_shift";
    } finally {
        app.close();
    }
}

test "removal wins over an open shift" {
    app = _cinemas(["sam"]);
    try {
        app.call("owner_a", "start_shift", {"tenant": "nova"});
        token = app.call(
            "owner_a",
            "invite_staff",
            {"tenant": "nova", "role": "tenant_admin", "venue_id": ""}
        )["token"];
        sam = app.call("sam", "accept_invite", {"token": token})["member_id"];
        app.call("sam", "start_shift", {"tenant": "nova"});
        app.call("owner_a", "remove_staff", {"tenant": "nova", "member_id": sam});
        assert _rename(app, "sam", "nova", "X")["error"]["code"] == "not_found";
    } finally {
        app.close();
    }
}

test "only staff can open a shift" {
    app = _cinemas(["stranger"]);
    try {
        for who in ["stranger", "owner_b"] {
            answer = app.call(who, "start_shift", {"tenant": "nova"});
            assert answer["error"]["code"] == "not_found" , f"{who}: {answer}";
        }
    } finally {
        app.close();
    }
}
