"""P15.0: a customer downloads their data, and deletes their account a week later.

In-process app (payment_app.jac), the clock moved on (AFRICINEMAS_CLOCK_CONTROL).

- Download: the account, their bookings (saved to it, or made with its email) with
  what they paid, the offers record and connected apps; another cinema's customer, and
  staff, are refused.
- Delete: the password first; then the account is locked (My tickets refused) except
  for downloading and cancelling; cancelling keeps it.
- Seven days on, the job deletes it: the sign-in, the profile and saved bookings go;
  offers are withdrawn with the record kept; the email comes off orders whose showtime
  has passed, not off upcoming ones, whose tickets still open; the same email can sign
  up again. Not before the seven days.
"""

import os;
import uuid;
import from tests.support.served { Served }
import from tests.support.harness { TEST_PASSWORD }
import from tests.support.storefront_setup {
    browse,
    code_of,
    customer_at,
    add_screening
}
import from tests.support.payment_setup { ANNA, ANNA_EMAIL, paying_cinema, paid }

def _token(app: Served, screening: str) -> str {
    link = browse(
        app, "my_payment", {"slug": "nova", "screening_id": screening, "holder": ANNA}
    )["payment"]["link"];
    return link.rsplit("/", 1)[1];
}

def _order(app: Served, screening: str) {
    # Anna holds A1 and A2 at `screening` and orders them, as paying_cinema does.
    where = {"slug": "nova", "screening_id": screening, "holder": ANNA};
    assert browse(app, "hold_seats", {** where, "labels": ["A1", "A2"]})["ok"];
    assert browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [
                {"seat_label": "A1", "ticket_type": "ADULT"},
                {"seat_label": "A2", "ticket_type": "ADULT"}
            ]
        }
    )["ok"];
}

def _ticket_email(app: Served, token: str) -> str {
    # The (masked) email on the order behind ticket link `token`: "" once blanked.
    seen = browse(app, "tickets_by_link", {"slug": "nova", "token": token});
    assert seen["ok"] , seen;
    return seen["booking"]["email"];
}

test "a customer downloads their data, and their account is deleted a week after asking" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, screening) = paying_cinema(["staffer"]);
    try {
        # Kim's account has Anna's email; two bookings, in 2 and 40 days.
        customer_at(app, "nova", "kim", ANNA_EMAIL);
        later = add_screening(app, "owner", nova, "Rafiki", 24 * 40);
        paid(app, screening);
        soon = _token(app, screening);
        assert app.call(
            "kim",
            "save_booking",
            {"slug": "nova", "token": soon, "display_name": "Kim"}
        )["ok"];
        _order(app, later);
        paid(app, later);
        far = _token(app, later);
        # Offers asked for, at a cinema that sends them.
        assert app.call(
            "owner",
            "save_site_info",
            {
                "tenant": "nova",
                "info": {"business_name": "Nova Ltd", "sends_offers": True}
            }
        )["ok"];
        assert app.call(
            "kim",
            "set_my_offers",
            {"slug": "nova", "subscribed": True, "source": "account"}
        )["ok"];
        # Download: everything held about them here.
        got = app.call("kim", "my_data", {"slug": "nova"});
        assert got["ok"] , got;
        data = got["data"];
        assert data["account"]["email"] == ANNA_EMAIL and data["cinema"];
        # The saved booking and the one made with the account's email.
        assert len(data["bookings"]) == 2 , data["bookings"];
        first = data["bookings"][0];
        assert first["film"] == "Rafiki" and first["rating"] == "PG";
        assert first["email"] == ANNA_EMAIL and first["total_cents"] > 0;
        assert len(first["tickets"]) == 2 and first["tickets"][0]["reference"];
        assert first["payments"] and first["payments"][0]["method"] == "mpesa";
        assert "qr" not in str(first["tickets"]);
        assert data["offers"]["given_at"] and not data["offers"]["withdrawn_at"];
        assert data["connected_apps"] == [] and data["deleting"] is None;
        assert len(data["kept_after_deletion"]) > 0;
        # Staff, and the signed out, can't.
        assert not app.call("staffer", "my_data", {"slug": "nova"})["ok"];
        # Deleting: the password first.
        ask = {"slug": "nova", "password": "not-my-password"};
        assert code_of(app.call("kim", "request_account_deletion", ask))
            == "wrong_password";
        asked = app.call(
            "kim", "request_account_deletion", {** ask, "password": TEST_PASSWORD}
        );
        assert asked["ok"] and asked["deleting"]["due"] > asked["deleting"]["asked_at"];
        assert len(asked["kept"]) > 0;
        # Locked: My tickets refused; downloading and the account page still work.
        assert code_of(app.call("kim", "my_tickets", {"slug": "nova"}))
            == "being_deleted";
        assert app.call("kim", "my_data", {"slug": "nova"})["data"]["deleting"];
        # The account page knows when, and what's kept, however often it's opened.
        pending = app.call("kim", "my_storefront_account", {"slug": "nova"})[
            "deleting"
        ];
        assert pending["due"] and len(pending["kept"]) > 0 , pending;
        # Cancelled: it's theirs again.
        assert app.call("kim", "cancel_account_deletion", {"slug": "nova"})["ok"];
        assert app.call("kim", "my_tickets", {"slug": "nova"})["ok"];
        assert app.call("kim", "my_storefront_account", {"slug": "nova"})["deleting"]
            is None;
        # Asked again; nothing happens before the seven days.
        assert app.call(
            "kim", "request_account_deletion", {** ask, "password": TEST_PASSWORD}
        )["ok"];
        assert app.call("owner", "t_delete_due") == 0;
        assert app.call("owner", "t_clock_ahead", {"hours": 24 * 6});
        assert app.call("owner", "t_delete_due") == 0;
        # Eight days on: the first showtime has passed, the later one hasn't.
        assert app.call("owner", "t_clock_ahead", {"hours": 24 * 2});
        assert app.call("owner", "t_delete_due") == 1;
        assert app.call("owner", "t_delete_due") == 0;
        # The sign-in is gone.
        login = app.client.login(app.actors["kim"].username, TEST_PASSWORD);
        assert not login.ok;
        # The email is off the past order, not the upcoming one, whose tickets still open.
        assert _ticket_email(app, soon) == "";
        assert _ticket_email(app, far) == "a***@example.com";
        # Offers withdrawn, the record kept as proof.
        kept = app.call(
            "owner", "pay_offer_consent", {"slug": "nova", "email": ANNA_EMAIL}
        );
        assert kept["given_at"] and kept["withdrawn_at"] , kept;
        # The same email can make a new account, with no bookings saved.
        customer_at(app, "nova", "kim2", ANNA_EMAIL);
        again = app.call("kim2", "my_tickets", {"slug": "nova"});
        assert again["ok"] and again["bookings"] == [] , again;
    } finally {
        app.call("owner", "t_clock_reset");
        os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
        app.close();
    }
}
