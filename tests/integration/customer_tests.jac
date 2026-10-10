"""Customer accounts, one per cinema (P2.6, P8.6c), through the production app (main.jac).

Since P8.6c (user decision 2026-10-10) a customer account belongs to one cinema: it is
made by that cinema's storefront sign-up, and the same email can have a separate
account at another cinema. Each account's CustomerProfile belongs to the cinema (its
principal) and is readable by that customer only; customers never reach staff
endpoints, and a customer account is nobody's customer at another cinema.
"""

import json;
import from os { path }
import from tests.support.served { Served, served }
import from tests.support.storefront_setup { customer_at, code_of }
import from tests.isolation.registry { REGISTRY }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     EMAIL: str = "wanjiru@example.com";

def _two_cinemas -> Served {
    app = served(MAIN, ["owner_a", "owner_b"]);
    app.call("owner_a", "create_cinema", {"name": "Nova Cinemas", "slug": "nova"});
    app.call("owner_b", "create_cinema", {"name": "Imax Rift", "slug": "imax-rift"});
    return app;
}

def _join(app: Served, who: str, slug: str, name: str = "Wanjiru") -> any {  # jac:ignore[W1037]
    return app.call(who, "join_as_customer", {"tenant": slug, "display_name": name});
}

test "a customer of one cinema has a profile there, and is nobody elsewhere" {
    app = _two_cinemas();
    try {
        customer_at(app, "nova", "wanjiru", EMAIL);
        joined = _join(app, "wanjiru", "nova");
        assert joined["ok"] and joined["created"] and joined["slug"] == "nova" , joined;
        mine = app.call("wanjiru", "my_customer_profile", {"tenant": "nova"});
        assert mine["ok"] and mine["profile_id"] == joined["profile_id"] , mine;
        assert mine["display_name"] == "Wanjiru";
        for name in ["my_customer_profile", "join_as_customer"] {
            body = {"tenant": "imax-rift", "display_name": "Wanjiru"}
                if name == "join_as_customer"
                else {"tenant": "imax-rift"};
            assert code_of(app.call("wanjiru", name, body)) == "not_your_cinema" , name;
        }
    } finally {
        app.close();
    }
}

test "the same email has a separate account and profile at another cinema" {
    app = _two_cinemas();
    try {
        customer_at(app, "nova", "wanjiru", EMAIL);
        customer_at(app, "imax-rift", "wanjiru_rift", EMAIL);
        at_a = _join(app, "wanjiru", "nova");
        at_b = _join(app, "wanjiru_rift", "imax-rift", "Wanjiru K.");
        assert at_b["ok"] and at_b["profile_id"] != at_a["profile_id"] , (at_a, at_b);
        assert app.call("wanjiru", "my_customer_profile", {"tenant": "nova"})[
            "display_name"
        ]
            == "Wanjiru";
        assert app.call("wanjiru_rift", "my_customer_profile", {"tenant": "imax-rift"})[
            "display_name"
        ]
            == "Wanjiru K.";
    } finally {
        app.close();
    }
}

test "joining again returns the same profile" {
    app = _two_cinemas();
    try {
        customer_at(app, "nova", "wanjiru", EMAIL);
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
    app = _two_cinemas();
    try {
        customer_at(app, "nova", "wanjiru", EMAIL);
        customer_at(app, "nova", "otieno");
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
    app = _two_cinemas();
    try {
        customer_at(app, "nova", "wanjiru", EMAIL);
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
    app = _two_cinemas();
    try {
        customer_at(app, "nova", "wanjiru", EMAIL);
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
