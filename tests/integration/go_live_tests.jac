"""P14.1: only an active cinema is public.

In-process app (payment_app.jac). Lumi Cinema is set up like any cinema (a venue, a
published screen, a priced showtime) but nobody has approved it, so to the public it
doesn't exist: no home page, no showtime, no holds, not in the directory, and its
address is no cinema's. Its team previews it with a pass from the back office: then it
shows, but takes no orders. The pass is for Lumi alone. A reviewer approves it, and it's
public to everyone; support staff may not approve, and a live cinema needs no pass.
"""

import os;
import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup {
    code_of,
    browse,
    open_cinema_for,
    add_movie,
    set_prices,
    add_screening
}
import from tests.support.payment_setup { ANNA, paying_cinema }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

glob HEADER: str = "x-africinemas-preview";

def _app -> tuple[Served, str] {  # jac:ignore[W1037]
    # Nova is live (the usual test cinema); Lumi, the rival's, is not.
    (app, _, _) = paying_cinema(["rival"]);
    lumi = open_cinema_for(app, "rival", "lumi", "Lumi Cinema", live=False);
    add_movie(app, "rival", lumi, "Rafiki");
    set_prices(app, "rival", lumi);
    show = add_screening(app, "rival", lumi, "Rafiki", 0);
    super_admin(app, "boss", "boss@example.com");
    return (app, show);
}

def _close(app: Served) {
    os.environ.pop(ADMINS_ENV, None);
    os.environ.pop("AFRICINEMAS_SITE_DOMAIN", None);
    app.close();
}

def _public(app: Served, name: str, body: dict[str, any], pass_token: str) -> any {  # jac:ignore[W1037]
    # A public endpoint, as a visitor whose page carries `pass_token` ("" for none).
    app.client.set_auth_token("");
    headers = {HEADER: pass_token} if pass_token else None;
    resp = app.client.post(f"/function/{name}", json=body, headers=headers);
    assert resp.status_code == 200 , f"{name}: {resp.status_code} {resp.text}";
    return resp.data["result"];
}

def _order_body(slug: str, show: str) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "slug": slug,
        "screening_id": show,
        "holder": ANNA,
        "idempotency_key": f"order-{uuid.uuid4().hex}",
        "items": [{"seat_label": "A1", "ticket_type": "ADULT"}]
    };
}

test "a cinema nobody has approved doesn't exist to the public" {
    (app, show) = _app();
    try {
        os.environ["AFRICINEMAS_SITE_DOMAIN"] = "localhost:8000";
        for (name, body) in [
            ("public_home", {"slug": "lumi"}),
            ("public_screening", {"slug": "lumi", "screening_id": show}),
            (
                "hold_seats",
                {"slug": "lumi", "screening_id": show, "holder": ANNA, "labels": ["A1"]}
            )
        ] {
            assert code_of(_public(app, name, body, "")) == "not_found" , name;
        }
        listed = browse(app, "public_cinemas", {"city": ""});
        assert "lumi" not in [c["slug"] for c in listed["cinemas"]] , listed;
        assert browse(app, "site_for_host", {"host": "lumi.localhost:8000"})["site"]
            == "none";
        # A live cinema is public, as before.
        assert browse(app, "public_home", {"slug": "nova"})["ok"];
        assert browse(app, "site_for_host", {"host": "nova.localhost:8000"})["site"]
            == "storefront";
    } finally {
        _close(app);
    }
}

test "its team previews it with a pass, which takes no orders and opens no other cinema" {
    (app, show) = _app();
    try {
        os.environ["AFRICINEMAS_SITE_DOMAIN"] = "localhost:8000";
        got = app.call("rival", "storefront_preview", {"tenant": "lumi"});
        assert got["ok"] and got["token"] and got["state"] == "configuring" , got;
        token = got["token"];
        assert _public(app, "public_home", {"slug": "lumi"}, token)["ok"];
        assert _public(
            app, "public_screening", {"slug": "lumi", "screening_id": show}, token
        )["ok"];
        assert _public(app, "site_for_host", {"host": "lumi.localhost:8000"}, token)[
            "site"
        ]
            == "storefront";
        held = _public(
            app,
            "hold_seats",
            {"slug": "lumi", "screening_id": show, "holder": ANNA, "labels": ["A1"]},
            token
        );
        assert held["ok"] , held;
        assert code_of(_public(app, "place_order", _order_body("lumi", show), token))
            == "not_live";
        # The pass is Lumi's alone, and a made-up one opens nothing.
        vela = open_cinema_for(app, "rival", "vela", "Vela Cinema", live=False);
        assert code_of(_public(app, "public_home", {"slug": vela.slug}, token))
            == "not_found";
        assert code_of(_public(app, "public_home", {"slug": "lumi"}, "made-up"))
            == "not_found";
        # Someone outside Lumi gets no pass for it.
        assert code_of(app.call("owner", "storefront_preview", {"tenant": "lumi"}))
            == "not_found";
        # A live cinema needs none.
        assert app.call("owner", "storefront_preview", {"tenant": "nova"})["token"]
            == "";
    } finally {
        _close(app);
    }
}

test "a reviewer approves it, and it's public to everyone" {
    (app, show) = _app();
    try {
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": "help@example.com", "role": "support"}
        );
        join_platform(app, "helper", invited["token"]);
        assert code_of(app.call("helper", "platform_approve_cinema", {"slug": "lumi"}))
            == "not_allowed";
        assert code_of(app.call("rival", "platform_approve_cinema", {"slug": "lumi"}))
            == "not_platform";
        approved = app.call("boss", "platform_approve_cinema", {"slug": "lumi"});
        assert approved["ok"] and approved["cinema"]["state"] == "active" , approved;
        # In its history, once the approval is on record.
        page = app.call("boss", "platform_cinema", {"slug": "lumi"})["cinema"];
        assert [h["what"] for h in page["history"]][0]
            == "platform.cinema_approved" , page;
        assert browse(app, "public_home", {"slug": "lumi"})["ok"];
        assert app.call("rival", "storefront_preview", {"tenant": "lumi"})["token"]
            == "";
        assert code_of(app.call("boss", "platform_approve_cinema", {"slug": "lumi"}))
            == "not_waiting";
        # Now it takes orders, from anyone.
        held = browse(
            app,
            "hold_seats",
            {"slug": "lumi", "screening_id": show, "holder": ANNA, "labels": ["A1"]}
        );
        assert held["ok"] , held;
        ordered = browse(app, "place_order", _order_body("lumi", show));
        assert ordered["ok"] , ordered;
    } finally {
        _close(app);
    }
}
