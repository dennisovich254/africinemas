"""P2.4: the tenant context is resolved on the server, from membership, on every call.

The client only names a cinema (its slug, ADR-0006). Who the caller is comes from the
token; what they may do there is read from the graph each time, so a removed or
changed role takes effect on the next call with the same token.
"""

import from os { path }
import from operator { itemgetter }
import from tests.support.served { Served, served }

glob APP: str = path.join(
         path.dirname(path.dirname(path.abspath(__file__))), "apps", "context_app.jac"
     );

def _two_cinemas -> tuple[Served, dict[str, any], dict[str, any]] {  # jac:ignore[W1037]
    app = served(APP, ["owner_a", "owner_b", "staff"]);
    a = app.call("owner_a", "create_cinema", {"name": "Nova Cinemas", "slug": "nova"});
    b = app.call(
        "owner_b", "create_cinema", {"name": "Imax Rift", "slug": "imax-rift"}
    );
    return (app, a, b);
}

def _join(app: Served, who: str, tenant_id: str, role: str, venue_id: str = "") -> str {
    return app.call(
        who, "t_join_as", {"tenant_id": tenant_id, "role": role, "venue_id": venue_id}
    );
}

test "the owner's context comes from their membership" {
    (app, a, _) = _two_cinemas();
    try {
        access = app.call("owner_a", "my_access", {"tenant": "nova"});
        assert access["ok"] and access["tenant_id"] == a["tenant_id"] , access;
        assert access["name"] == "Nova Cinemas" and access["state"] == "configuring";
        assert access["assignments"] == [{"role": "owner", "venue_ids": None}] , access;
    } finally {
        app.close();
    }
}

test "a forged cinema selector gets not_found and changes nothing" {
    (app, _, b) = _two_cinemas();
    try {
        for (endpoint, body) in [
            ("my_access", {"tenant": "imax-rift"}),
            ("rename_cinema", {"tenant": "imax-rift", "name": "Hijacked"})
        ] {
            refused = app.call("owner_a", endpoint, body);
            assert refused
                == {
                    "ok": False,
                    "error": {"code": "not_found", "message": "No such cinema."}
                } , refused;
        }
        assert app.call("owner_b", "my_access", {"tenant": "imax-rift"})["name"]
            == "Imax Rift";
    } finally {
        app.close();
    }
}

test "unknown, malformed and foreign cinemas are indistinguishable" {
    (app, _, _) = _two_cinemas();
    try {
        answers = [
            app.call("owner_a", "my_access", {"tenant": t})
            for t in ["imax-rift", "no-such-cinema", "Not A Slug!", ""]
        ];
        assert all(r == answers[0] for r in answers) , answers;
    } finally {
        app.close();
    }
}

test "authorize applies the member's roles inside their cinema" {
    (app, a, _) = _two_cinemas();
    try {
        _join(app, "staff", a["tenant_id"], "usher");
        denied = app.call(
            "staff", "rename_cinema", {"tenant": "nova", "name": "Usher's Choice"}
        );
        assert denied
            == {
                "ok": False,
                "error": {"code": "forbidden", "message": "You can't do that here."}
            } , denied;
        assert app.call(
            "owner_a",
            "rename_cinema",
            {"tenant": "nova", "name": "Nova Cinemas Westlands"}
        )["ok"];
        assert app.call("staff", "my_access", {"tenant": "nova"})["name"]
            == "Nova Cinemas Westlands";
    } finally {
        app.close();
    }
}

test "role changes and removal take effect on the next call, same token" {
    (app, a, _) = _two_cinemas();
    try {
        staff_root = _join(app, "staff", a["tenant_id"], "usher");
        assert not app.call("staff", "rename_cinema", {"tenant": "nova", "name": "X1"})[
            "ok"
        ];
        _join(app, "staff", a["tenant_id"], "tenant_admin");
        assert app.call(
            "staff", "rename_cinema", {"tenant": "nova", "name": "Nova Two"}
        )["ok"] , "promotion applies at once";
        removed = app.call(
            "owner_a",
            "t_remove",
            {"tenant_id": a["tenant_id"], "staff_root_id": staff_root}
        );
        assert removed == 2 , f"both memberships removed, got {removed}";
        gone = app.call("staff", "my_access", {"tenant": "nova"});
        assert gone["error"]["code"] == "not_found" , "removal applies at once";
    } finally {
        app.close();
    }
}

test "venue-scoped groups become venue-scoped assignments" {
    (app, a, _) = _two_cinemas();
    try {
        _join(app, "staff", a["tenant_id"], "usher", "venue-1");
        _join(app, "staff", a["tenant_id"], "usher", "venue-2");
        _join(app, "staff", a["tenant_id"], "auditor");
        access = app.call("staff", "my_access", {"tenant": "nova"});
        assert sorted(access["assignments"], key=itemgetter("role"))
            == [
                {"role": "auditor", "venue_ids": None},
                {"role": "usher", "venue_ids": ["venue-1", "venue-2"]}
            ] , access;
    } finally {
        app.close();
    }
}
