"""P6.3a: the ticket email, the private ticket link and resending (ADR-0010, ADR-0022).

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa and the
development outbox (no SMTP host, so nothing is really sent). Paying needs an email
address. Confirming the payment queues the ticket email, and the mail job sends it once:
one QR image per seat and the ticket link. The link shows the booking to whoever holds
it; a wrong token, or one at another cinema, shows nothing. Resending works up to three
times an hour per order, to the same or a corrected address.
"""

import os;
import tempfile;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of, open_cinema_for }
import from tests.support.payment_setup { ANNA, paying_setup, paid }

def _setup -> tuple[Served, str] {  # jac:ignore[W1037]
    os.environ["AFRICINEMAS_OUTBOX_DIR"] = tempfile.mkdtemp(
        prefix="africinemas-outbox-"
    );
    os.environ.pop("AFRICINEMAS_SMTP_HOST", None);
    (app, screening) = paying_setup();
    app.call("owner", "tm_clear_outbox");
    return (app, screening);
}

def _sent(app: Served) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Runs the mail job, then returns everything in the outbox.
    app.call("owner", "tm_send_mail");
    return app.call("owner", "tm_outbox");
}

def _mine(app: Served, screening: str) -> dict[str, any] {  # jac:ignore[W1037]
    return browse(
        app, "my_payment", {"slug": "nova", "screening_id": screening, "holder": ANNA}
    )["payment"];
}

def _token(app: Served, screening: str) -> str {
    return _mine(app, screening)["link"].rsplit("/", 1)[1];
}

def _resend(app: Served, token: str, email: str = "") -> any {  # jac:ignore[W1037]
    return browse(
        app, "resend_tickets", {"slug": "nova", "token": token, "email": email}
    );
}

test "a paid order's tickets are emailed once, with a QR image per seat and the link" {
    (app, screening) = _setup();
    try {
        paid(app, screening);
        mine = _mine(app, screening);
        assert mine["email"] == "a***@example.com" , mine;
        assert mine["link"].startswith("/c/nova/tickets/") , mine;
        mails = _sent(app);
        assert len(mails) == 1 , mails;
        assert mails[0]["to"] == "anna@example.com";
        assert mails[0]["images"] == 2;
        assert mine["link"] in mails[0]["text"];
        for t in mine["tickets"] {
            assert t["reference"] in mails[0]["text"];
        }
        # Sent once: the job finds nothing more to send.
        assert len(_sent(app)) == 1;
    } finally {
        app.close();
    }
}

test "the link shows the booking; a wrong token or another cinema shows nothing" {
    (app, screening) = _setup();
    try {
        paid(app, screening);
        token = _token(app, screening);
        seen = browse(app, "tickets_by_link", {"slug": "nova", "token": token});
        assert seen["ok"] , seen;
        booking = seen["booking"];
        assert booking["movie_title"] == "Rafiki" and booking["starts_at"];
        assert booking["email"] == "a***@example.com";
        assert [t["seat_label"] for t in booking["tickets"]] == ["A1", "A2"];
        assert all([t["qr"].startswith("TKT1.") for t in booking["tickets"]]);
        wrong = browse(
            app, "tickets_by_link", {"slug": "nova", "token": token[:-1] + "x"}
        );
        assert code_of(wrong) == "not_found";
        open_cinema_for(app, "owner", "rift", "Rift Cinemas");
        elsewhere = browse(app, "tickets_by_link", {"slug": "rift", "token": token});
        assert code_of(elsewhere) == "not_found";
        assert elsewhere == wrong;
    } finally {
        app.close();
    }
}

test "tickets can be resent three times an hour, to the same or a corrected address" {
    (app, screening) = _setup();
    try {
        paid(app, screening);
        token = _token(app, screening);
        _sent(app);
        assert code_of(_resend(app, token, "anna@")) == "invalid_email";
        moved = _resend(app, token, "anna.k@example.com");
        assert moved["ok"] and moved["email"] == "a*****@example.com" , moved;
        assert _resend(app, token)["ok"];
        assert _resend(app, token)["ok"];
        refused = _resend(app, token);
        assert code_of(refused) == "too_many_resends" , refused;
        assert 0 < refused["error"]["retry_after_s"] <= 3600;
        mails = _sent(app);
        assert [m["to"] for m in mails]
            == [
                "anna@example.com",
                "anna.k@example.com",
                "anna.k@example.com",
                "anna.k@example.com"
            ] , mails;
        assert _mine(app, screening)["email"] == "a*****@example.com";
        assert code_of(_resend(app, "nosuchtokenxxxxxxxxxxxxxxx")) == "not_found";
    } finally {
        app.close();
    }
}
