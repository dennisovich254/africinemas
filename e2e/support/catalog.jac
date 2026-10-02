"""Seed a cinema with movies and published showtimes for browser tests, through the
public API as staff would (P4.1).
"""

import io;
import base64;
import from datetime { datetime, timedelta }
import from PIL { Image }
import from e2e.support.api { call, owner_with_cinema, add_venue, add_screen }

def day_ahead(days_ahead: int) -> str {
    return (datetime.now() + timedelta(days=days_ahead)).strftime("%Y-%m-%d");
}

def poster_base64 -> str {
    out = io.BytesIO();
    Image.new("RGB", (400, 600), "#7A2E3B").save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def add_movie(owner: dict[str, str], title: str, synopsis: str) -> str {
    made = call(
        owner["token"],
        "create_movie",
        {
            "tenant": owner["slug"],
            "title": title,
            "synopsis": synopsis,
            "runtime_minutes": 83,
            "age_rating": "16",
            "genres": ["Drama"],
            "language": "English, Swahili"
        }
    );
    assert made["ok"] , made;
    return made["movie"]["movie_id"];
}

def publish_showing(owner: dict[str, str], movie: str, day: str, clock: str) -> str {
    made = call(
        owner["token"],
        "create_screening",
        {
            "tenant": owner["slug"],
            "auditorium_id": owner["screen"],
            "movie_id": movie,
            "starts_at": f"{day}T{clock}:00+03:00"
        }
    );
    assert made["ok"] , made;
    sid = made["screening"]["screening_id"];
    for step in ["schedule_screening", "publish_screening"] {
        assert call(
            owner["token"], step, {"tenant": owner["slug"], "screening_id": sid}
        )["ok"];
    }
    return sid;
}

def cinema_with_programme -> dict[str, str] {
    # A cinema showing Rafiki (with a poster) twice over two days and Supa Modo once,
    # with Kati Kati not yet showing.
    owner = owner_with_cinema();
    venue = add_venue(owner, "Westgate");
    owner["screen"] = add_screen(owner, venue, "Screen 1");
    assert call(
        owner["token"],
        "save_layout",
        {
            "tenant": owner["slug"],
            "auditorium_id": owner["screen"],
            "rows": 1,
            "cols": 3,
            "seats": [{"label": f"A{i + 1}", "row": 0, "col": i} for i in range(3)]
        }
    )["ok"];
    assert call(
        owner["token"],
        "publish_layout",
        {"tenant": owner["slug"], "auditorium_id": owner["screen"]}
    )["ok"];
    rafiki = add_movie(owner, "Rafiki", "Two young women in Nairobi fall in love.");
    supa = add_movie(owner, "Supa Modo", "A young girl dreams of being a superhero.");
    assert call(
        owner["token"],
        "upload_poster",
        {
            "tenant": owner["slug"],
            "movie_id": rafiki,
            "content_type": "image/png",
            "data_base64": poster_base64()
        }
    )["ok"];
    # Coming soon: no showtimes yet, so not on sale.
    owner["kati"] = add_movie(
        owner, "Kati Kati", "A young woman wakes in a strange lodge."
    );
    owner["rafiki"] = rafiki;
    owner["first"] = publish_showing(owner, rafiki, day_ahead(2), "18:15");
    publish_showing(owner, supa, day_ahead(2), "21:00");
    owner["second"] = publish_showing(owner, rafiki, day_ahead(3), "20:00");
    return owner;
}

def cinema_selling_tickets(cols: int = 6) -> dict[str, str] {
    # A cinema selling tickets for one showtime of Rafiki in two days: rows A and B of
    # `cols` seats (B's last seat blocked), Adult KES 800 and Child KES 500, a KES 30
    # booking fee and no extras. Returns the owner, with "show" the showtime's id.
    owner = owner_with_cinema();
    venue = add_venue(owner, "Westgate");
    owner["screen"] = add_screen(owner, venue, "Screen 1");
    seats: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for (r, row) in enumerate(["A", "B"]) {
        for c in range(cols) {
            seat: dict[str, any] = {"label": f"{row}{c + 1}", "row": r, "col": c};  # jac:ignore[W1037]
            if row == "B" and c == cols - 1 {
                seat["seat_type"] = "BLOCKED";
            }
            seats.append(seat);
        }
    }
    assert call(
        owner["token"],
        "save_layout",
        {
            "tenant": owner["slug"],
            "auditorium_id": owner["screen"],
            "rows": 2,
            "cols": cols,
            "seats": seats
        }
    )["ok"];
    assert call(
        owner["token"],
        "publish_layout",
        {"tenant": owner["slug"], "auditorium_id": owner["screen"]}
    )["ok"];
    prices = call(
        owner["token"],
        "save_price_list",
        {
            "tenant": owner["slug"],
            "timezone": "Africa/Nairobi",
            "ticket_types": [
                {"code": "ADULT", "name": "Adult"},
                {"code": "CHILD", "name": "Child"}
            ],
            "prices": [
                {"zone": "", "ticket_type": "ADULT", "price_cents": 80000},
                {"zone": "", "ticket_type": "CHILD", "price_cents": 50000}
            ],
            "surcharges": [],
            "service_fee_cents": 3000
        }
    );
    assert prices["ok"] , prices;
    rafiki = add_movie(owner, "Rafiki", "Two young women in Nairobi fall in love.");
    owner["show"] = publish_showing(owner, rafiki, day_ahead(2), "18:15");
    return owner;
}
