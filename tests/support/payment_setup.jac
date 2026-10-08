"""Payments for the integration tests (P5.3, P5.4): a cinema whose visitor has an order
waiting for payment, served by tests/apps/payment_app.jac with the simulated M-Pesa.
"""

import os;
import uuid;
import from os { path }
import from tests.support.served { Served, served }
import from tests.support.storefront_setup {
    Cinema,
    open_cinema_for,
    add_movie,
    add_screening,
    set_prices,
    browse
}

glob APP: str = path.join(
         path.dirname(path.dirname(path.abspath(__file__))), "apps", "payment_app.jac"
     ),
     PAYMENTS: str = "AFRICINEMAS_PAYMENTS",
     TICKET_KEY: str = "AFRICINEMAS_TICKET_KEY",
     FAULTS: str = "AFRICINEMAS_FAULTS",
     ANNA: str = "holder-anna-0123456789abcdef",
     ANNA_EMAIL: str = "anna@example.com";

def paying_setup -> tuple[Served, str] {  # jac:ignore[W1037]
    # A priced showtime where Anna holds A1 and A2 and has ordered them (KES 1,860: 800 + 100 evening extra + 30 fee each).
    (app, _, screening) = paying_cinema([]);
    return (app, screening);
}

def paying_cinema(staff: list[str]) -> tuple[Served, Cinema, str] {  # jac:ignore[W1037]
    # As paying_setup, with more actors (staff to hire, P6.2) and the cinema itself.
    os.environ[PAYMENTS] = "simulator";
    # Tickets are signed (P6.1); without a key payments are refused.
    os.environ.setdefault(TICKET_KEY, "test" * 10);
    app = served(APP, ["owner"] + staff);
    nova = open_cinema_for(app, "owner", "nova", "Nova Cinemas");
    add_movie(app, "owner", nova, "Rafiki");
    set_prices(app, "owner", nova);
    screening = add_screening(app, "owner", nova, "Rafiki", 0);
    held = browse(
        app,
        "hold_seats",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "labels": ["A1", "A2"]
        }
    );
    assert held["ok"] , held;
    ordered = browse(
        app,
        "place_order",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [
                {"seat_label": "A1", "ticket_type": "ADULT"},
                {"seat_label": "A2", "ticket_type": "ADULT"}
            ]
        }
    );
    assert ordered["ok"] , ordered;
    return (app, nova, screening);
}

def pay(
    app: Served, screening: str, phone: str, key: str = "", email: str = ANNA_EMAIL
) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "start_payment",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "phone": phone,
            "email": email,
            "idempotency_key": key or f"pay-{uuid.uuid4().hex}"
        }
    );
}

def pushes(app: Served, reference: str) -> int {
    return app.call("owner", "pay_push_count", {"reference": reference});
}

def stored_payments(app: Served, screening: str) -> list[list[str]] {
    return app.call("owner", "pay_stored", {"slug": "nova", "screening_id": screening});
}

def fresh_phone -> str {
    # A fresh number per test: the simulator scripts outcomes by number.
    return f"2547{uuid.uuid4().int % 100000000:08d}";
}

def paid(app: Served, screening: str) -> str {
    # Anna pays, Safaricom's callback arrives and the job settles it: the order is
    # confirmed with its tickets. Returns the payment's reference.
    started = pay(app, screening, fresh_phone());
    assert started["ok"] and started["payment"]["state"] == "stk_requested" , started;
    reference = started["payment"]["reference"];
    sent = app.call(
        "owner",
        "pay_callback",
        {"slug": "nova", "screening_id": screening, "reference": reference}
    );
    assert sent["body"] is not None , sent;
    app.client.set_auth_token("");
    resp = app.client.post(f"/hooks/mpesa/{sent['token']}", json=sent["body"]);
    assert resp.status_code == 200 , resp.text;
    assert app.call("owner", "pay_process") == 1;
    return reference;
}

def hire(app: Served, who: str, role: str, venue_id: str) -> str {
    # `who` joins Nova as `role` at `venue_id` ("" for every venue) and starts a shift;
    # returns their member id.
    invited = app.call(
        "owner", "invite_staff", {"tenant": "nova", "role": role, "venue_id": venue_id}
    );
    assert invited["ok"] , invited;
    joined = app.call(who, "accept_invite", {"token": invited["token"]});
    assert joined["ok"] , joined;
    assert app.call(who, "start_shift", {"tenant": "nova"})["ok"];
    return joined["member_id"];
}
