"""P13.2: the cinemas directory, for AfriCinemas platform staff.

In-process app (payment_app.jac). Nova Cinemas has a paid booking: Anna's two seats,
KES 1,860. The rival then signs up Imax Rift with their sign-in as its owner's email.
The platform's super admin lists every cinema, newest first, finds them by name, slug
and owner email, filters by state and pages through. A support member reads them too.
A cinema's page has its venues, screens, staff, tickets sold and takings, but nothing
about its customers. A cinema owner is refused it all.
"""

import os;
import json;
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of }
import from tests.support.payment_setup { ANNA, paying_cinema, paid }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

glob BOSS: str = "boss@example.com";

def _app -> Served {
    (app, _, screening) = paying_cinema(["rival"]);
    paid(app, screening);
    made = app.call(
        "rival",
        "create_cinema",
        {"name": "Imax Rift", "slug": "imax-rift", "email": "rival"}
    );
    assert made["created"] , made;
    super_admin(app, "boss", BOSS);
    return app;
}

def _close(app: Served) {
    os.environ.pop(ADMINS_ENV, None);
    app.close();
}

def _slugs(answer: dict[str, any]) -> list[str] {  # jac:ignore[W1037]
    assert answer["ok"] , answer;
    return [c["slug"] for c in answer["cinemas"]];
}

test "the directory lists every cinema newest first, and finds them by name, slug and owner" {
    app = _app();
    try {
        listed = app.call("boss", "platform_cinemas", {});
        assert _slugs(listed) == ["imax-rift", "nova"] , listed;
        assert listed["total"] == 2 and listed["page"] == 1 and listed["pages"] == 1;
        rift = listed["cinemas"][0];
        assert rift["name"] == "Imax Rift" and rift["owners"] == ["rival"] , rift;
        assert rift["state"] == "configuring" and rift["state_label"] == "Setting up";
        assert rift["signed_up_at"];
        assert _slugs(app.call("boss", "platform_cinemas", {"search": "NOVA"}))
            == ["nova"];
        assert _slugs(app.call("boss", "platform_cinemas", {"search": "imax-r"}))
            == ["imax-rift"];
        assert _slugs(app.call("boss", "platform_cinemas", {"search": "rival"}))
            == ["imax-rift"];
        assert _slugs(app.call("boss", "platform_cinemas", {"search": "nobody-here"}))
            == [];
        assert _slugs(app.call("boss", "platform_cinemas", {"state": "configuring"}))
            == ["imax-rift", "nova"];
        assert _slugs(app.call("boss", "platform_cinemas", {"state": "active"})) == [];
        assert code_of(app.call("boss", "platform_cinemas", {"state": "bogus"}))
            == "invalid_state";
        # In pages: one a page, the last page for a page past the end.
        first = app.call("boss", "platform_cinemas", {"per_page": 1});
        assert _slugs(first) == ["imax-rift"] and first["pages"] == 2 , first;
        second = app.call("boss", "platform_cinemas", {"per_page": 1, "page": 2});
        assert _slugs(second) == ["nova"] and second["page"] == 2;
        assert _slugs(app.call("boss", "platform_cinemas", {"per_page": 1, "page": 9}))
            == ["nova"];
    } finally {
        _close(app);
    }
}

test "a cinema's page has its venues, staff and takings, and nothing about its customers" {
    app = _app();
    try {
        seen = app.call("boss", "platform_cinema", {"slug": "nova"});
        assert seen["ok"] , seen;
        nova = seen["cinema"];
        assert nova["name"] == "Nova Cinemas" and nova["staff"] == 1 , nova;
        assert [v["name"] for v in nova["venues"]] == ["Westgate"] , nova["venues"];
        assert nova["venues"][0]["screens"] == ["Screen 1"] , nova["venues"];
        assert nova["tickets_sold"] == 2 , nova;
        assert nova["takings_net_cents"] == 186000 , nova;
        assert nova["currency"] == "KES";
        assert [h["what"] for h in nova["history"]] == ["signed_up"] , nova["history"];
        # No customer's name, phone or email: only counts.
        shown = json.dumps(seen).lower();
        for private in [ANNA.lower(), "0712", "254712", "@example.com"] {
            assert private not in shown , private;
        }
        assert code_of(app.call("boss", "platform_cinema", {"slug": "no-such"}))
            == "not_found";
    } finally {
        _close(app);
    }
}

test "every platform role reads the directory; a cinema owner is refused it" {
    app = _app();
    try {
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": "help@example.com", "role": "support"}
        );
        join_platform(app, "helper", invited["token"]);
        assert _slugs(app.call("helper", "platform_cinemas", {}))
            == ["imax-rift", "nova"];
        assert app.call("helper", "platform_cinema", {"slug": "imax-rift"})["ok"];
        for (name, body) in [
            ("platform_cinemas", {}),
            ("platform_cinema", {"slug": "nova"})
        ] {
            assert code_of(app.call("owner", name, body)) == "not_platform" , name;
        }
    } finally {
        _close(app);
    }
}
