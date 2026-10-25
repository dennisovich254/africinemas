"""P12.13: 2D/3D catalogue data and the venue's tracked 3D-glasses offer."""

import from os { path }
import os;
import uuid;
import from tests.support.served { Served, served }
import from tests.support.storefront_setup {
    Cinema,
    open_cinema_for,
    add_screening,
    set_prices,
    browse
}
import from tests.support.payment_setup { fresh_phone, settle }

glob APP: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))),
         "payment_app.jac"
     );

def setup(format: str = "3D") -> tuple[Served, Cinema, str] {
    app = served(APP, ["owner"]);
    cinema = open_cinema_for(app, "owner", "nova", "Nova Cinemas");
    made = app.call(
        "owner",
        "create_movie",
        {
            "tenant": "nova",
            "title": "Rafiki",
            "synopsis": "",
            "runtime_minutes": 90,
            "age_rating": "PG",
            "genres": ["Drama"],
            "language": "English",
            "format": format
        }
    );
    assert made["ok"] , made;
    cinema.movies["Rafiki"] = made["movie"]["movie_id"];
    set_prices(app, "owner", cinema);
    screening = add_screening(app, "owner", cinema, "Rafiki", 0);
    return (app, cinema, screening);
}

def configure(app: Served, cinema: Cinema, price: int = 12000) -> dict[str, any] {  # jac:ignore[W1037]
    answer = app.call(
        "owner",
        "configure_3d_glasses",
        {"tenant": "nova", "venue_id": cinema.venue, "sold": True, "price_cents": price}
    );
    assert answer["ok"] , answer;
    return answer["glasses"];
}

test "a showtime inherits its movie format and can be changed independently" {
    (app, _, screening) = setup();
    try {
        got = app.call(
            "owner", "get_screening", {"tenant": "nova", "screening_id": screening}
        );
        assert got["screening"]["format"] == "3D" , got;
        changed = app.call(
            "owner",
            "set_screening_format",
            {"tenant": "nova", "screening_id": screening, "format": "2D"}
        );
        assert changed["ok"] and changed["screening"]["format"] == "2D" , changed;
        public = browse(
            app, "public_screening", {"slug": "nova", "screening_id": screening}
        );
        assert public["screening"]["format"] == "2D" , public;
    } finally {
        app.close();
    }
}

test "3D glasses use the venue price and tracked snack stock" {
    (app, cinema, screening) = setup();
    try {
        glasses = configure(app, cinema, 15000);
        assert glasses["sold"] and glasses["price_cents"] == 15000 , glasses;
        assert glasses["track_stock"] , glasses;
        empty = browse(
            app, "public_snacks", {"slug": "nova", "screening_id": screening}
        );
        assert empty["glasses"] is None , empty;
        received = app.call(
            "owner",
            "adjust_snack_stock",
            {
                "tenant": "nova",
                "product_id": glasses["product_id"],
                "variant_id": glasses["variant_id"],
                "venue_id": cinema.venue,
                "reason": "received",
                "quantity": 4,
                "note": ""
            }
        );
        assert received["ok"] , received;
        menu = browse(
            app, "public_snacks", {"slug": "nova", "screening_id": screening}
        );
        assert menu["glasses"]["price_cents"] == 15000 , menu;
        assert menu["glasses"]["available"] == 4 , menu;
    } finally {
        app.close();
    }
}

test "a 2D showtime never offers or accepts glasses" {
    (app, cinema, screening) = setup("2D");
    try {
        configure(app, cinema);
        menu = browse(
            app, "public_snacks", {"slug": "nova", "screening_id": screening}
        );
        assert menu["glasses"] is None , menu;
    } finally {
        app.close();
    }
}

test "bought glasses are snack sales and stay attached to their ticket" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, cinema, screening) = setup();
    try {
        glasses = configure(app, cinema, 15000);
        app.call(
            "owner",
            "adjust_snack_stock",
            {
                "tenant": "nova",
                "product_id": glasses["product_id"],
                "variant_id": glasses["variant_id"],
                "venue_id": cinema.venue,
                "reason": "received",
                "quantity": 4,
                "note": ""
            }
        );
        holder = f"holder-{uuid.uuid4().hex}";
        where = {"slug": "nova", "screening_id": screening, "holder": holder};
        assert browse(app, "hold_seats", {** where, "labels": ["A1", "A2"]})["ok"];
        order = browse(
            app,
            "place_order",
            {
                ** where,
                "idempotency_key": f"order-{uuid.uuid4().hex}",
                "items": [
                    {"seat_label": "A1", "ticket_type": "ADULT"},
                    {"seat_label": "A2", "ticket_type": "ADULT"}
                ],
                "glasses_seats": ["A2"]
            }
        );
        assert order["ok"] and order["order"]["glasses_seats"] == ["A2"] , order;
        assert order["order"]["snacks"][0]["purpose"] == "3d_glasses";
        assert order["order"]["snacks_cents"] == 15000;
        started = browse(
            app,
            "start_payment",
            {
                ** where,
                "phone": fresh_phone(),
                "email": "viewer@example.com",
                "idempotency_key": f"pay-{uuid.uuid4().hex}"
            }
        );
        assert started["ok"] , started;
        settle(app, screening, started["payment"]["reference"]);
        paid = browse(app, "my_payment", where)["payment"];
        tickets = {t["seat_label"]: t for t in paid["tickets"]};
        assert tickets["A1"]["format"] == "3D" and not tickets["A1"]["glasses_bought"];
        assert tickets["A2"]["format"] == "3D" and tickets["A2"]["glasses_bought"];
        sales = app.call(
            "owner",
            "sales_report",
            {"tenant": "nova", "date_from": "", "date_to": "", "venue_id": cinema.venue}
        );
        assert sales["report"]["snacks"]["units"] == 1 , sales;
        assert sales["report"]["snacks"]["sales_cents"] == 15000 , sales;
        app.call(
            "owner",
            "rd_freeze",
            {"slug": "nova", "screening_id": screening, "minutes": -30}
        );
        plain = app.call(
            "owner",
            "redeem_ticket",
            {"tenant": "nova", "screening_id": screening, "code": tickets["A1"]["qr"]}
        );
        handover = app.call(
            "owner",
            "redeem_ticket",
            {"tenant": "nova", "screening_id": screening, "code": tickets["A2"]["qr"]}
        );
        assert plain["ok"] and not plain["ticket"]["glasses_bought"] , plain;
        assert handover["ok"] and handover["ticket"]["glasses_bought"] , handover;
    } finally {
        app.call("owner", "rd_unfreeze");
        app.close();
        os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
    }
}
