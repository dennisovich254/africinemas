"""P8.6c: storefront accounts, one per cinema, fully separate from the back office.

User decision (2026-10-10): a storefront is its own product. A customer signs up AT a
cinema; that account works at that cinema only, never in the back office, and never at
another cinema. The same email can have a separate account (and password) at each
cinema, and a staff account besides. Staff accounts are no one's customer.

In-process app (tests/apps/payment_app.jac): Nova and Rift.
"""

import from tests.support.served { Served }
import from tests.support.harness { TEST_PASSWORD }
import from tests.support.storefront_setup { browse, code_of, open_cinema_for }
import from tests.support.payment_setup { paying_cinema }

glob EMAIL: str = "wanjiru@example.com";

def _sign_up(
    app: Served, slug: str, email: str = EMAIL, password: str = TEST_PASSWORD
) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "customer_sign_up",
        {"slug": slug, "email": email, "password": password, "name": "Wanjiru"}
    );
}

def _sign_in(app: Served, slug: str, password: str = TEST_PASSWORD) -> str {
    # A storefront sign-in: the cinema's customer account for EMAIL, or "" if refused.
    resp = app.client.login(f"{slug}:{EMAIL}", password);
    data: dict[str, any] = resp.data if resp.ok and resp.data else {};  # jac:ignore[W1037]
    return str(data.get("token", ""));
}

def _as(app: Served, token: str, name: str, body: dict[str, any]) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token(token);
    resp = app.client.post(f"/function/{name}", json=body);
    app.client.set_auth_token("");
    assert resp.status_code == 200 , f"{name}: {resp.status_code} {resp.text[:200]}";
    return resp.data["result"];
}

test "a customer signs up at one cinema, and the same email can sign up at another apart" {
    (app, _, _) = paying_cinema(["staff_wanjiru"]);
    try {
        open_cinema_for(app, "staff_wanjiru", "rift", "Rift Cinemas");
        made = _sign_up(app, "nova");
        assert made["ok"] , made;
        assert _sign_in(app, "nova") , "the new account signs in at Nova";
        # Once per cinema.
        assert code_of(_sign_up(app, "nova")) == "taken";
        # Rift is a separate account, with its own password.
        assert _sign_up(app, "rift", EMAIL, "another-password-1")["ok"];
        assert _sign_in(app, "rift", "another-password-1");
        assert _sign_in(app, "rift") == "" , "Nova's password doesn't open Rift's account";
        # What a sign-up refuses.
        assert code_of(_sign_up(app, "nova", "not-an-email")) == "invalid_email";
        assert code_of(_sign_up(app, "nova", "other@example.com", "short"))
            == "weak_password";
        assert code_of(_sign_up(app, "no-such-cinema")) == "not_found";
    } finally {
        app.close();
    }
}

test "a customer account works at its own cinema only" {
    (app, _, _) = paying_cinema(["kim"]);
    try {
        open_cinema_for(app, "kim", "rift", "Rift Cinemas");
        assert _sign_up(app, "nova")["ok"];
        token = _sign_in(app, "nova");
        home = _as(app, token, "my_storefront_account", {"slug": "nova"});
        assert home["signed_in"] and home["customer"] and home["email"] == EMAIL , home;
        away = _as(app, token, "my_storefront_account", {"slug": "rift"});
        assert away["signed_in"] and away["customer"] == False , away;
        assert _as(
            app, token, "join_as_customer", {"tenant": "nova", "display_name": "W"}
        )["ok"];
        assert code_of(_as(app, token, "my_tickets", {"slug": "nova"})) == "";
        for (name, body) in [
            ("join_as_customer", {"tenant": "rift", "display_name": "W"}),
            ("my_tickets", {"slug": "rift"})
        ] {
            assert code_of(_as(app, token, name, body)) == "not_your_cinema" , name;
        }
    } finally {
        app.close();
    }
}

test "a customer account can't use the back office" {
    (app, _, _) = paying_cinema([]);
    try {
        assert _sign_up(app, "nova")["ok"];
        token = _sign_in(app, "nova");
        made = _as(app, token, "create_cinema", {"name": "Sneaky", "slug": "sneaky"});
        assert made.get("created", False) == False , made;
        invite = app.call(
            "owner", "invite_staff", {"tenant": "nova", "role": "usher", "venue_id": ""}
        )["token"];
        joined = _as(app, token, "accept_invite", {"token": invite});
        assert joined.get("ok", False) == False , joined;
    } finally {
        app.close();
    }
}

test "a staff account is no one's customer" {
    (app, _, _) = paying_cinema([]);
    try {
        token = app.actors["owner"].token;
        seen = _as(app, token, "my_storefront_account", {"slug": "nova"});
        assert seen["signed_in"] and seen["customer"] == False , seen;
        for (name, body) in [
            ("join_as_customer", {"tenant": "nova", "display_name": "Owner"}),
            ("my_tickets", {"slug": "nova"})
        ] {
            assert code_of(_as(app, token, name, body)) == "not_your_cinema" , name;
        }
        # Signed out, the storefront knows nobody.
        assert browse(app, "my_storefront_account", {"slug": "nova"})["signed_in"]
            == False;
    } finally {
        app.close();
    }
}
