"""Platform staff for tests (P13.1b.a): a super admin from the server's settings, joined
from the setup link, as an actor of a served test app (payment_app.jac)."""

import os;
import from tests.support.served { Served }
import from tests.support.harness { Actor }

glob ADMINS_ENV: str = "AFRICINEMAS_PLATFORM_ADMINS",
     PLATFORM_PASSWORD: str = "Platform-Passw0rd!";

def anonymous(app: Served, name: str, body: dict[str, any]) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token("");
    resp = app.client.post(f"/function/{name}", json=body);
    assert resp.status_code == 200 , f"{name}: {resp.status_code} {resp.text}";
    return resp.data["result"];
}

def join_platform(app: Served, label: str, token: str) {
    # Sets the password from a join link and signs in as the actor `label`.
    joined = anonymous(
        app, "platform_join", {"token": token, "password": PLATFORM_PASSWORD}
    );
    assert joined["ok"] , joined;
    login = app.client.login(joined["sign_in_name"], PLATFORM_PASSWORD);
    assert login.ok , login.text;
    data: dict[str, any] = login.data or {};  # jac:ignore[W1037]
    app.actors[label] = Actor(
        username=joined["sign_in_name"],
        user_id=str(data.get("user_id", "")),
        root_id=str(data.get("root_id", "")),
        token=str(data["token"])
    );
}

def super_admin(app: Served, label: str, email: str) {
    # `email` as the settings' super admin, signed in as `label`.
    os.environ[ADMINS_ENV] = email;
    join_platform(
        app, label, anonymous(app, "t_platform_setup_link", {"email": email})
    );
}
