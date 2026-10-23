"""P14.3b: a cinema's policies, written in the back office and shown on its storefront.

In-process app (payment_app.jac). Nova's owner starts the terms from our template,
saves a draft, then publishes it once they've ticked they've read it. Only published
policies reach the storefront and its footer's links; the required ones still missing
are named for the review (14.4). Only staff who change settings may save; another
cinema's staff find nothing. Each save is in the cinema's audit log.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, browse }
import from tests.support.payment_setup { paying_cinema, hire }

def _app -> Served {
    (app, nova, _) = paying_cinema(["usher", "rival"]);
    hire(app, "usher", "usher", nova.venue);
    app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
    return app;
}

def _save(
    app: Served, who: str, kind: str, text: str, published: bool, reviewed: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    return app.call(
        who,
        "save_policy",
        {
            "tenant": "nova",
            "kind": kind,
            "text": text,
            "published": published,
            "reviewed": reviewed
        }
    );
}

test "a draft stays private; published once reviewed, it's on the storefront" {
    app = _app();
    try {
        listed = app.call("owner", "policies", {"tenant": "nova"})["policies"];
        assert [p["kind"] for p in listed]
            == [
                "terms",
                "privacy",
                "refunds",
                "house_rules",
                "accessibility",
                "age_ratings"
            ];
        terms = listed[0];
        assert terms["required"] and not terms["published"] and terms["text"] == "";
        assert "Nova" in terms["template"];
        draft = _save(app, "owner", "terms", terms["template"], False, False);
        assert draft["ok"] , draft;
        assert code_of(browse(app, "public_policy", {"slug": "nova", "kind": "terms"}))
            == "not_found";
        assert browse(app, "public_branding", {"slug": "nova"})["policies"] == [];
        # Publishing needs the tick, and some text.
        assert code_of(_save(app, "owner", "terms", "Ours.", True, False))
            == "not_reviewed";
        assert code_of(_save(app, "owner", "privacy", "  ", True, True))
            == "empty_policy";
        assert _save(app, "owner", "terms", "## Ours\r\n\r\n- One", True, True)["ok"];
        shown = browse(app, "public_policy", {"slug": "nova", "kind": "terms"});
        assert shown["title"] == "Terms of ticket sale" , shown;
        assert shown["text"] == "## Ours\n\n- One";
        assert browse(app, "public_branding", {"slug": "nova"})["policies"]
            == [{"kind": "terms", "title": "Terms of ticket sale"}];
        logged = app.call("owner", "audit_log", {"tenant": "nova", "limit": 10});
        assert "policy.saved" in [e["action"] for e in logged["events"]];
        # Unpublished again, it's gone from the storefront.
        assert _save(app, "owner", "terms", "## Ours", False, False)["ok"];
        assert code_of(browse(app, "public_policy", {"slug": "nova", "kind": "terms"}))
            == "not_found";
    } finally {
        app.close();
    }
}

test "only staff who change settings may save, and only the six policies" {
    app = _app();
    try {
        assert code_of(_save(app, "owner", "nope", "Ours.", False, False))
            == "unknown_policy";
        assert code_of(_save(app, "usher", "terms", "Ours.", False, False))
            == "forbidden";
        assert code_of(_save(app, "rival", "terms", "Ours.", False, False))
            == "not_found";
        assert code_of(app.call("rival", "policies", {"tenant": "nova"}))
            == "not_found";
    } finally {
        app.close();
    }
}
