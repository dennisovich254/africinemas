"""P14.2: a staff account confirms its email with a one-time link.

In-process app (payment_app.jac) with the development outbox. Kim signs up with an email.
Until Kim follows the emailed link, Kim can't create a cinema. The link works once:
reused, altered or replaced by a newer one, it's refused. Sending is limited per hour,
and only for one's own email. An account without an email (a username, as the tests'
other actors) has nothing to confirm.
"""

import os;
import tempfile;
import from tests.support.served { Served, served }
import from tests.support.harness { Actor }
import from tests.support.storefront_setup { code_of, browse }
import from tests.support.payment_setup { APP }

glob PASSWORD: str = "Kim-Passw0rd!",
     KIM: str = "kim@example.com";

def _app -> Served {
    os.environ["AFRICINEMAS_OUTBOX_DIR"] = tempfile.mkdtemp(
        prefix="africinemas-outbox-"
    );
    os.environ.pop("AFRICINEMAS_SMTP_HOST", None);
    app = served(APP, ["owner"]);
    _sign_up(app, "kim", KIM);
    app.call("owner", "tm_clear_outbox");
    return app;
}

def _close(app: Served) {
    os.environ.pop("AFRICINEMAS_OUTBOX_DIR", None);
    app.close();
}

def _sign_up(app: Served, label: str, email: str) {
    # Signs up with an email identity, as the web form does (jacSignup), then signs in.
    app.client.set_auth_token("");
    made = app.client.post(
        "/user/register",
        json={
            "identities": [{"type": "email", "value": email}],
            "credential": {"type": "password", "password": PASSWORD}
        }
    );
    assert made.status_code in (200, 201) , made.text;
    login = app.client.post(
        "/user/login",
        json={
            "identity": {"type": "email", "value": email},
            "credential": {"type": "password", "password": PASSWORD}
        }
    );
    assert login.status_code == 200 , login.text;
    data: dict[str, any] = login.data or {};  # jac:ignore[W1037]
    app.actors[label] = Actor(
        username=email,
        user_id=str(data.get("user_id", "")),
        root_id=str(data.get("root_id", "")),
        token=str(data["token"])
    );
}

def _link(app: Served, to: str) -> str {
    # Sends the queued link emails; the token of the last one to `to`.
    app.call("owner", "t_send_email_checks");
    mails = [
        m
        for m in app.call("owner", "tm_outbox")
        if m["to"] == to
    ];
    assert mails , "no email to " + to;
    text: str = mails[-1]["text"];
    return text.split("/verify-email#", 1)[1].split()[0];
}

test "an unconfirmed email can't create a cinema; the emailed link confirms it, once" {
    app = _app();
    try {
        assert app.call("kim", "email_status", {"email": KIM})
            == {"ok": True, "email": KIM, "confirmed": False};
        made = app.call(
            "kim", "create_cinema", {"name": "Kim's", "slug": "kims", "email": KIM}
        );
        assert made["error"]["code"] == "email_unverified" , made;
        sent = app.call("kim", "send_email_check", {"email": KIM});
        assert sent["ok"] and sent["sent"] , sent;
        token = _link(app, KIM);
        mails = app.call("owner", "tm_outbox");
        assert mails[-1]["subject"] == "Confirm your email for AfriCinemas";
        # An altered link, then the real one, then the real one again.
        assert code_of(browse(app, "confirm_email", {"token": token[:-2] + "xy"}))
            == "invalid_link";
        confirmed = browse(app, "confirm_email", {"token": token});
        assert confirmed["ok"] and confirmed["email"] == KIM , confirmed;
        assert code_of(browse(app, "confirm_email", {"token": token}))
            == "invalid_link";
        assert app.call("kim", "email_status", {"email": KIM})["confirmed"];
        made = app.call(
            "kim", "create_cinema", {"name": "Kim's", "slug": "kims", "email": KIM}
        );
        assert made["created"] , made;
        # Already confirmed: nothing more to send.
        again = app.call("kim", "send_email_check", {"email": KIM});
        assert again["confirmed"] and not again["sent"] , again;
    } finally {
        _close(app);
    }
}

test "a newer link replaces the last, sends are limited, and only for one's own email" {
    app = _app();
    try {
        app.call("kim", "send_email_check", {"email": KIM});
        first = _link(app, KIM);
        app.call("kim", "send_email_check", {"email": KIM});
        second = _link(app, KIM);
        assert first != second;
        assert code_of(browse(app, "confirm_email", {"token": first}))
            == "invalid_link";
        # Three more make five this hour; the sixth waits.
        for _ in range(3) {
            assert app.call("kim", "send_email_check", {"email": KIM})["ok"];
        }
        assert code_of(app.call("kim", "send_email_check", {"email": KIM}))
            == "too_many";
        # Someone else's email isn't yours to confirm.
        _sign_up(app, "lee", "lee@example.com");
        assert code_of(app.call("lee", "send_email_check", {"email": KIM}))
            == "not_your_email";
        # A username account has no email here, and nothing to confirm.
        assert app.call("owner", "email_status", {"email": "owner"})
            == {"ok": True, "email": "", "confirmed": False};
        # The newest link sent still works (the three queued since haven't gone yet).
        assert browse(app, "confirm_email", {"token": second})["ok"];
    } finally {
        _close(app);
    }
}
