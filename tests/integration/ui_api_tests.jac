"""P2.7b: the server additions the web UI needs, through the production app (main.jac).

- my_access also returns the member's permissions (for role-aware navigation) and
  whether their shift is open (for the "Start shift" banner).
- check_slug tells the onboarding wizard, as the owner types, whether a cinema address
  is valid and free (slugs are public: they are subdomains).
"""

import from os { path }
import from core.authz.policy { PERMISSIONS, ROLE_PERMISSIONS }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     );

def _cinema(names: list[str]) -> Served {
    app = served(MAIN, ["owner"] + names);
    app.call("owner", "create_cinema", {"name": "Nova Cinemas", "slug": "nova"});
    return app;
}

test "my_access lists the member's permissions and shift status" {
    app = _cinema(["ann"]);
    try {
        before = app.call("owner", "my_access", {"tenant": "nova"});
        assert before["permissions"] == sorted(PERMISSIONS) , before["permissions"];
        assert before["shift_open"] == False;
        app.call("owner", "start_shift", {"tenant": "nova"});
        assert app.call("owner", "my_access", {"tenant": "nova"})["shift_open"] == True;
        token = app.call(
            "owner",
            "invite_staff",
            {"tenant": "nova", "role": "usher", "venue_id": "venue-1"}
        )["token"];
        app.call("ann", "accept_invite", {"token": token});
        usher = app.call("ann", "my_access", {"tenant": "nova"});
        assert usher["permissions"] == sorted(ROLE_PERMISSIONS["usher"]) , usher[
            "permissions"
        ];
    } finally {
        app.close();
    }
}

test "check_slug reports valid, taken and free addresses" {
    app = _cinema(["other"]);
    try {
        taken = app.call("other", "check_slug", {"slug": " Nova "});
        assert taken
            == {
                "slug": "nova",
                "valid": True,
                "available": False,
                "reason": "taken",
                "message": "'nova' is already taken."
            } , taken;
        bad = app.call("other", "check_slug", {"slug": "no--va"});
        assert bad["valid"] == False
            and bad["available"] == False
            and bad["reason"] == "hyphen" , bad;
        free = app.call("other", "check_slug", {"slug": "Westgate-Cinemas"});
        assert free
            == {
                "slug": "westgate-cinemas",
                "valid": True,
                "available": True,
                "reason": "",
                "message": ""
            } , free;
    } finally {
        app.close();
    }
}
