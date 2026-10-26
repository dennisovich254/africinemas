"""P12.15: the signed-in person's own name and password.

In-process app (payment_app.jac). Kim, a cinema owner who signs in with an email, names
themself and changes their password: the current one is asked first, Jac's password
rules apply, and afterwards the new password signs in and the old one doesn't. Nobody
can change another account's password. Anna, a customer of Nova's storefront, names
herself on her account there.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, open_cinema_for, customer_at }
import from tests.support.verification_setup { verifying_app, close_app, KIM }

glob OLD: str = "Kim-Passw0rd!",
     NEW: str = "Kim-Another-Passw0rd!";

def _login(app: Served, email: str, password: str) -> int {
    app.client.set_auth_token("");
    resp = app.client.post(
        "/user/login",
        json={
            "identity": {"type": "email", "value": email},
            "credential": {"type": "password", "password": password}
        }
    );
    return resp.status_code;
}

def _change(app: Served, who: str, sign_in: str, current: str, new: str) -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "change_my_password",
        {"sign_in": sign_in, "current_password": current, "new_password": new}
    );
}

test "staff name themselves and change their password, their own only" {
    app = verifying_app();
    try {
        mine = app.call("kim", "my_profile", {"sign_in": KIM});
        assert mine == {"ok": True, "kind": "staff", "name": "", "sign_in": KIM} , mine;
        assert code_of(app.call("kim", "save_my_name", {"name": " "}))
            == "invalid_name";
        assert app.call("kim", "save_my_name", {"name": "  Kimani   Wanjiru "})["name"]
            == "Kimani Wanjiru";
        assert app.call("kim", "my_profile", {"sign_in": KIM})["name"]
            == "Kimani Wanjiru";
        # The current password first; Jac's rules for the new one.
        assert code_of(_change(app, "kim", KIM, "not-it", NEW)) == "wrong_password";
        assert code_of(_change(app, "kim", KIM, OLD, "short")) == "weak_password";
        # Someone else's account is never theirs to change.
        assert code_of(_change(app, "rival", KIM, OLD, NEW)) == "not_you";
        assert app.call("rival", "my_profile", {"sign_in": KIM})["sign_in"] == "";
        assert _change(app, "kim", KIM, OLD, NEW)["ok"];
        assert _login(app, KIM, NEW) == 200;
        assert _login(app, KIM, OLD) != 200;
    } finally {
        close_app(app);
    }
}

test "a customer names themself on their storefront account" {
    app = verifying_app();
    try {
        open_cinema_for(app, "owner", "nova", "Nova Cinemas");
        customer_at(app, "nova", "anna", "anna@example.com");
        sign_in = app.actors["anna"].username;
        mine = app.call("anna", "my_profile", {"sign_in": sign_in});
        assert mine["kind"] == "customer" and mine["name"] == "anna" , mine;
        assert app.call("anna", "save_my_name", {"name": "Anna Njeri"})["ok"];
        assert app.call("anna", "my_profile", {"sign_in": sign_in})["name"]
            == "Anna Njeri";
        assert app.call("anna", "my_storefront_account", {"slug": "nova"})["name"]
            == "Anna Njeri";
        # A customer's sign-in name comes from their account.
        assert code_of(_change(app, "anna", "", "not-it", "Anna-Passw0rd-2!"))
            == "wrong_password";
    } finally {
        close_app(app);
    }
}
