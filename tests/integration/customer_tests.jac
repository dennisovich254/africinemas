"""P2.6: customer accounts per cinema, through the production app (main.jac).

One platform login; a separate CustomerProfile per cinema the person uses (architecture
§12: a user can belong to many cinemas). Profiles belong to the cinema (its principal)
and are readable by that customer only; customers never reach staff endpoints.
"""

import json;
import from os { path }
import from tests.support.served { Served, served }
import from tests.isolation.registry { REGISTRY }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     );

def _two_cinemas(customers: list[str]) -> Served {
    app = served(MAIN, ["owner_a", "owner_b"] + customers);
    app.call("owner_a", "create_cinema", {"name": "Nova Cinemas", "slug": "nova"});
    app.call("owner_b", "create_cinema", {"name": "Imax Rift", "slug": "imax-rift"});
    return app;
}

def _join(app: Served, who: str, slug: str, name: str = "Wanjiru") -> any {  # jac:ignore[W1037]
    return app.call(who, "join_as_customer", {"tenant": slug, "display_name": name});
}

test "joining a cinema's storefront creates a profile at that cinema only" {
    app = _two_cinemas(["wanjiru"]);
    try {
        joined = _join(app, "wanjiru", "nova");
        assert joined["ok"] and joined["created"] and joined["slug"] == "nova" , joined;
        mine = app.call("wanjiru", "my_customer_profile", {"tenant": "nova"});
        assert mine["ok"] and mine["profile_id"] == joined["profile_id"] , mine;
        assert mine["display_name"] == "Wanjiru";
        elsewhere = app.call("wanjiru", "my_customer_profile", {"tenant": "imax-rift"});
        assert elsewhere["ok"] == False
            and elsewhere["error"]["code"] == "not_found" , elsewhere;
    } finally {
        app.close();
    }
}

test "the same person at another cinema gets a separate profile" {
    app = _two_cinemas(["wanjiru"]);
    try {
        at_a = _join(app, "wanjiru", "nova");
        at_b = _join(app, "wanjiru", "imax-rift", "Wanjiru K.");
        assert at_b["ok"] and at_b["profile_id"] != at_a["profile_id"] , (at_a, at_b);
        assert app.call("wanjiru", "my_customer_profile", {"tenant": "nova"})[
            "display_name"
        ]
            == "Wanjiru";
        assert app.call("wanjiru", "my_customer_profile", {"tenant": "imax-rift"})[
            "display_name"
        ]
            == "Wanjiru K.";
    } finally {
        app.close();
    }
}

test "joining again returns the same profile" {
    app = _two_cinemas(["wanjiru"]);
    try {
        first = _join(app, "wanjiru", "nova");
        again = _join(app, "wanjiru", "nova", "Someone Else");
        assert again["ok"] and again["created"] == False , again;
        assert again["profile_id"] == first["profile_id"];
        assert again["display_name"] == "Wanjiru" , "a repeat join doesn't rename the profile";
    } finally {
        app.close();
    }
}

test "customers see only their own profile" {
    app = _two_cinemas(["wanjiru", "otieno"]);
    try {
        w = _join(app, "wanjiru", "nova");
        o = _join(app, "otieno", "nova", "Otieno");
        assert app.call("otieno", "my_customer_profile", {"tenant": "nova"})[
            "profile_id"
        ]
            == o["profile_id"];
        assert w["profile_id"] != o["profile_id"];
    } finally {
        app.close();
    }
}

test "a customer can't call any staff endpoint" {
    app = _two_cinemas(["wanjiru"]);
    try {
        _join(app, "wanjiru", "nova");
        for (name, spec) in REGISTRY.items() {
            if spec["scope"] == "tenant" {
                body = json.loads(
                    json.dumps(spec["probe"]).replace("{tenant}", "nova")
                );
                answer = app.call("wanjiru", name, body);
                assert answer["ok"] == False
                    and answer["error"]["code"] == "not_found" , f"{name}: {answer}";
            }
        }
        assert app.call("wanjiru", "my_cinemas") == [] , "a customer is nobody's staff";
    } finally {
        app.close();
    }
}

test "unknown and malformed storefronts are refused" {
    app = _two_cinemas(["wanjiru"]);
    try {
        for slug in ["no-such-cinema", "Not A Slug!", ""] {
            answer = _join(app, "wanjiru", slug);
            assert answer["ok"] == False and answer["error"]["code"] == "not_found" , f"{slug!r}: {answer}";
        }
        bad_name = _join(app, "wanjiru", "nova", "   ");
        assert bad_name["error"]["code"] == "invalid_name" , bad_name;
    } finally {
        app.close();
    }
}
