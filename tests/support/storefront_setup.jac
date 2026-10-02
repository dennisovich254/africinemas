"""A cinema with a venue, a five-seat screen and movies, for the storefront tests (P4.1).

Every call goes through the production app (main.jac), as staff would make it; browse()
calls a public endpoint as an anonymous visitor.
"""

import from datetime { datetime, timedelta, timezone }
import from tests.support.served { Served }

glob START: datetime = (datetime.now(timezone.utc) + timedelta(days=2)).replace(
         hour=18, minute=0, second=0, microsecond=0
     );

obj Cinema {
    has slug: str,
        venue: str,
        screen: str,
        movies: dict[str, str] = {};
}

def open_cinema_for(app: Served, who: str, slug: str, name: str) -> Cinema {
    # A cinema, its owner on shift, one venue and a published five-seat screen.
    app.call(who, "create_cinema", {"name": name, "slug": slug});
    app.call(who, "start_shift", {"tenant": slug});
    venue = app.call(
        who,
        "create_venue",
        {
            "tenant": slug,
            "name": "Westgate",
            "city": "Nairobi",
            "address": "Mwanzi Road"
        }
    )["venue"]["venue_id"];
    screen = app.call(
        who,
        "create_auditorium",
        {"tenant": slug, "venue_id": venue, "name": "Screen 1"}
    )["auditorium"]["auditorium_id"];
    app.call(
        who,
        "save_layout",
        {
            "tenant": slug,
            "auditorium_id": screen,
            "rows": 1,
            "cols": 5,
            "seats": [{"label": f"A{i + 1}", "row": 0, "col": i} for i in range(5)]
        }
    );
    app.call(who, "publish_layout", {"tenant": slug, "auditorium_id": screen});
    return Cinema(slug=slug, venue=venue, screen=screen);
}

def add_movie(app: Served, who: str, cinema: Cinema, title: str) -> str {
    made = app.call(
        who,
        "create_movie",
        {
            "tenant": cinema.slug,
            "title": title,
            "synopsis": f"About {title}.",
            "runtime_minutes": 90,
            "age_rating": "PG",
            "genres": ["Drama"],
            "language": "English"
        }
    );
    assert made["ok"] , made;
    cinema.movies[title] = made["movie"]["movie_id"];
    return made["movie"]["movie_id"];
}

def add_screening(
    app: Served,
    who: str,
    cinema: Cinema,
    title: str,
    hours: int,
    state: str = "published"
) -> str {
    # A screening of `title`, `hours` after START, taken as far as `state`:
    # "draft", "scheduled" or "published".
    made = app.call(
        who,
        "create_screening",
        {
            "tenant": cinema.slug,
            "auditorium_id": cinema.screen,
            "movie_id": cinema.movies[title],
            "starts_at": (START + timedelta(hours=hours)).isoformat()
        }
    );
    assert made["ok"] , made;
    screening = made["screening"]["screening_id"];
    body = {"tenant": cinema.slug, "screening_id": screening};
    if state in ["scheduled", "published"] {
        assert app.call(who, "schedule_screening", body)["ok"];
    }
    if state == "published" {
        assert app.call(who, "publish_screening", body)["ok"];
    }
    return screening;
}

def browse(app: Served, name: str, body: dict[str, any]) -> any {  # jac:ignore[W1037]
    # A public endpoint, called without a login.
    app.client.set_auth_token("");
    resp = app.client.post(f"/function/{name}", json=body);
    assert resp.status_code == 200 , resp.text;
    return resp.data["result"];
}

def code_of(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

def set_prices(app: Served, who: str, cinema: Cinema, adult: int = 80000) {
    # Adult and Child tickets (KES 800 and 500 by default), a KES 100 evening extra
    # (START is 21:00 in Nairobi) and a KES 30 service fee.
    saved = app.call(
        who,
        "save_price_list",
        {
            "tenant": cinema.slug,
            "timezone": "Africa/Nairobi",
            "ticket_types": [
                {"code": "ADULT", "name": "Adult"},
                {"code": "CHILD", "name": "Child"}
            ],
            "prices": [
                {"zone": "", "ticket_type": "ADULT", "price_cents": adult},
                {"zone": "", "ticket_type": "CHILD", "price_cents": 50000}
            ],
            "surcharges": [
                {
                    "name": "Evening",
                    "days": [0, 1, 2, 3, 4, 5, 6],
                    "start": "18:00",
                    "end": "24:00",
                    "amount_cents": 10000
                }
            ],
            "service_fee_cents": 3000
        }
    );
    assert saved["ok"] , saved;
}
