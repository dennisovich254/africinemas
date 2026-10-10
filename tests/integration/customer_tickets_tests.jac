"""P6.3b: "My tickets", a signed-in customer's bookings at a cinema (ADR-0010, ADR-0023).

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa. Anna pays as a
guest; a signed-in customer who holds the ticket link saves the booking to their
account at that cinema (save_booking proves the link), and my_tickets lists what they
saved there. A customer sees only their own saved bookings: another customer, or the
same customer at another cinema, sees none of them. Saving twice is one booking; a
wrong link saves nothing; a caller who isn't signed in is refused. Customers are
accounts of their cinema (P8.6c, customer_at).
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup {
    browse,
    code_of,
    open_cinema_for,
    customer_at
}
import from tests.support.payment_setup { ANNA, paying_cinema, paid }

def _link(app: Served, screening: str) -> str {
    return browse(
        app, "my_payment", {"slug": "nova", "screening_id": screening, "holder": ANNA}
    )["payment"]["link"];
}

def _token(link: str) -> str {
    return link.rsplit("/", 1)[1];
}

def _save(app: Served, who: str, token: str, slug: str = "nova") -> any {  # jac:ignore[W1037]
    return app.call(
        who, "save_booking", {"slug": slug, "token": token, "display_name": "Kim"}
    );
}

def _mine(app: Served, who: str, slug: str = "nova") -> any {  # jac:ignore[W1037]
    return app.call(who, "my_tickets", {"slug": slug});
}

test "a signed-in customer saves a booking by its link and sees it in My tickets" {
    (app, _, screening) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        paid(app, screening);
        link = _link(app, screening);
        saved = _save(app, "kim", _token(link));
        assert saved["ok"] , saved;
        mine = _mine(app, "kim");
        assert mine["ok"] , mine;
        bookings = mine["bookings"];
        assert len(bookings) == 1 , bookings;
        assert bookings[0]["link"] == link;
        assert bookings[0]["movie_title"] == "Rafiki";
        assert bookings[0]["starts_at"] and bookings[0]["upcoming"];
        assert [t["seat_label"] for t in bookings[0]["tickets"]] == ["A1", "A2"];
        # Saving again changes nothing.
        assert _save(app, "kim", _token(link))["ok"];
        assert len(_mine(app, "kim")["bookings"]) == 1;
    } finally {
        app.close();
    }
}

test "a customer sees only their own bookings, and only at that cinema" {
    (app, _, screening) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        customer_at(app, "nova", "lee");
        paid(app, screening);
        token = _token(_link(app, screening));
        assert _save(app, "kim", token)["ok"];
        assert _mine(app, "lee")["bookings"] == [];
        assert code_of(_save(app, "lee", token[:-1] + "x")) == "not_found";
        assert _mine(app, "lee")["bookings"] == [];
        open_cinema_for(app, "owner", "rift", "Rift Cinemas");
        # Kim's account is Nova's: at Rift it's no customer at all (P8.6c).
        assert code_of(_mine(app, "kim", "rift")) == "not_your_cinema";
        assert code_of(_save(app, "kim", token, "rift"))
            in ["not_found", "not_your_cinema"];
    } finally {
        app.close();
    }
}

test "My tickets needs a signed-in customer" {
    (app, _, screening) = paying_cinema([]);
    try {
        app.client.set_auth_token("");
        resp = app.client.post("/function/my_tickets", json={"slug": "nova"});
        assert resp.status_code == 401 , resp.status_code;
    } finally {
        app.close();
    }
}
