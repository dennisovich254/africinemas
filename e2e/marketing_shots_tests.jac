"""Screenshots of the real storefront on a phone, for the landing page (P3.9).

The landing page shows the product as it really is, not a drawing of it. This sets up an
example cinema (its name, films and showtimes are invented examples), publishes a few
screenings and its brand, then photographs its storefront at a phone's size and pixel
density, in dark and light. The images land in e2e/artifacts/; the ones the landing page
uses are copied into the app when they change. Re-run after the storefront's look
changes (Phase 4 adds the seat map and checkout).
"""

import from datetime { datetime, timedelta }
import from e2e.support.web { shared_browser, close_contexts, BASE_URL, artifact }
import from e2e.support.api { call, owner_with_cinema, add_venue, add_screen }

glob FILMS: list[tuple[str, int, str, list[str]]] = [
         ("Nairobi Nights", 118, "16", ["Drama"]),
         ("The Long Rains", 96, "PG", ["Family"]),
         ("Matatu Run", 104, "16", ["Action", "Comedy"])
     ],
     # (film index, days ahead, local start time)
     SHOWS: list[tuple[int, int, str]] = [
         (0, 1, "18:15"),
         (1, 1, "15:00"),
         (2, 1, "21:00"),
         (0, 2, "20:30"),
         (1, 2, "12:30")
     ];

def _example_cinema -> dict[str, str] {
    owner = owner_with_cinema("Nova Cinemas");
    venue = add_venue(owner, "Westgate");
    call(
        owner["token"],
        "update_venue",
        {
            "tenant": owner["slug"],
            "venue_id": venue,
            "name": "Westgate",
            "city": "Nairobi",
            "address": ""
        }
    );
    screen = add_screen(owner, venue, "Screen 1");
    seats = [
        {"label": f"{chr(65 + r)}{c + 1}", "row": r, "col": c} for r in range(4)
        for c in range(6)
    ];
    assert call(
        owner["token"],
        "save_layout",
        {
            "tenant": owner["slug"],
            "auditorium_id": screen,
            "rows": 4,
            "cols": 6,
            "seats": seats
        }
    )["ok"];
    assert call(
        owner["token"],
        "publish_layout",
        {"tenant": owner["slug"], "auditorium_id": screen}
    )["ok"];
    movies: list[str] = [];
    for (title, minutes, rating, genres) in FILMS {
        movies.append(
            call(
                owner["token"],
                "create_movie",
                {
                    "tenant": owner["slug"],
                    "title": title,
                    "synopsis": "",
                    "runtime_minutes": minutes,
                    "age_rating": rating,
                    "genres": genres,
                    "language": "English, Swahili"
                }
            )["movie"]["movie_id"]
        );
    }
    for (film, days, clock) in SHOWS {
        day = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d");
        made = call(
            owner["token"],
            "create_screening",
            {
                "tenant": owner["slug"],
                "auditorium_id": screen,
                "movie_id": movies[film],
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
    }
    return owner;
}

test "marketing screenshots of the storefront on a phone" {
    owner = _example_cinema();
    (pw, browser) = shared_browser();
    try {
        for scheme in ["dark", "light"] {
            page = browser.new_context(
                viewport={"width": 390, "height": 844},
                device_scale_factor=3,
                is_mobile=True,
                has_touch=True,
                color_scheme=scheme,
                timezone_id="Africa/Nairobi",
                locale="en-KE"
            ).new_page();
            page.goto(f"{BASE_URL}/c/{owner['slug']}");
            page.wait_for_selector('[data-testid="storefront"] li');
            page.evaluate("document.fonts.ready");
            page.screenshot(path=artifact(f"marketing-storefront-{scheme}.png"));
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
