"""P8.4: the cards a chat reply carries (core/agent/cards.jac), built from tool results.

The model never writes a card: `cards_from` turns what the tools returned during a turn
into at most three cards, the programme first and then the movies, the latest answer
for each. A refused tool call makes no card.
"""

import from core.agent.cards { cards_from, programme_card, movie_card, CARDS_MAX }

glob SHOWTIMES: list[dict[str, str]] = [
         {
             "showtime_id": "s1",
             "starts": "2026-10-10 18:00",
             "movie": "Rafiki",
             "movie_key": "rafiki",
             "venue": "Westgate",
             "city": "Nairobi",
             "screen": "Screen 1"
         },
         {
             "showtime_id": "s2",
             "starts": "2026-10-10 21:00",
             "movie": "Kesho",
             "movie_key": "kesho",
             "venue": "Westgate",
             "city": "Nairobi",
             "screen": "Screen 1"
         },
         {
             "showtime_id": "s3",
             "starts": "2026-10-11 18:00",
             "movie": "Rafiki",
             "movie_key": "rafiki",
             "venue": "Westgate",
             "city": "Nairobi",
             "screen": "Screen 2"
         }
     ];

def _details(title: str, trailer: str = "") -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "title": title,
        "synopsis": f"About {title}.",
        "runtime_minutes": 90,
        "age_rating": "PG",
        "genres": ["Drama"],
        "language": "English",
        "trailer_url": trailer,
        "showtimes": []
    };
}

test "the programme groups showtimes by day and lists each movie once" {
    card = programme_card("Nova Cinemas", "nova", SHOWTIMES);
    assert card["type"] == "programme" and card["cinema"] == "Nova Cinemas";
    assert card["cinema_slug"] == "nova";
    assert [d["day"] for d in card["days"]] == ["2026-10-10", "2026-10-11"];
    assert [s["showtime_id"] for s in card["days"][0]["showtimes"]] == ["s1", "s2"];
    assert card["movies"]
        == [
            {"movie_key": "rafiki", "title": "Rafiki"},
            {"movie_key": "kesho", "title": "Kesho"}
        ];
}

test "a movie card carries its trailer's player, built from the link" {
    card = movie_card(
        "Nova Cinemas",
        "nova",
        "rafiki",
        _details("Rafiki", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    );
    assert card["type"] == "movie" and card["movie_key"] == "rafiki";
    assert card["trailer_embed"]
        == "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ";
    assert movie_card("Nova Cinemas", "nova", "kesho", _details("Kesho"))[
        "trailer_embed"
    ]
        == "";
}

test "cards come only from successful tool results, the programme first, at most three" {
    seen = [
        ("movie_details", {"cinema": "nova", "movie_key": "kesho"}, _details("Kesho")),
        (
            "whats_on",
            {"cinema": "nova", "day": ""},
            {"ok": True, "showtimes": SHOWTIMES}
        ),
        (
            "movie_details",
            {"cinema": "nova", "movie_key": "made-up"},
            {"ok": False, "error": "Not found."}
        ),
        ("seat_map", {"cinema": "nova", "showtime_id": "s1"}, {"ok": True}),
        ("movie_details", {"cinema": "nova", "movie_key": "a"}, _details("A")),
        ("movie_details", {"cinema": "nova", "movie_key": "b"}, _details("B")),
        ("movie_details", {"cinema": "nova", "movie_key": "kesho"}, _details("Kesho 2"))
    ];
    cards = cards_from(seen, "Nova Cinemas", "nova");
    assert len(cards) == CARDS_MAX == 3;
    assert [c["type"] for c in cards] == ["programme", "movie", "movie"];
    # The latest answer for a movie wins; a refused call makes no card.
    assert [c["title"] for c in cards[1:]] == ["Kesho 2", "A"];
    assert cards_from([], "Nova Cinemas", "nova") == [];
    assert cards_from(seen[2:4], "Nova Cinemas", "nova") == [];
}

test "a booking card and the customer's bookings come from their tools, and always fit" {
    showtime = {
        "showtime_id": "s1",
        "starts": "2026-10-10 18:00",
        "movie": "Rafiki",
        "movie_key": "rafiki",
        "venue": "Westgate",
        "screen": "Screen 1"
    };
    booked = {
        "ok": True,
        "bookings": [
            {
                "movie_title": "Rafiki",
                "starts_at": "2026-10-10T15:00:00+00:00",
                "timezone": "Africa/Nairobi",
                "venue": "Westgate",
                "screen": "Screen 1",
                "tickets": [{"seat_label": "A1"}, {"seat_label": "A2"}],
                "upcoming": True
            }
        ]
    };
    seen = [
        (
            "whats_on",
            {"cinema": "nova", "day": ""},
            {"ok": True, "showtimes": SHOWTIMES}
        ),
        ("movie_details", {"cinema": "nova", "movie_key": "a"}, _details("A")),
        ("movie_details", {"cinema": "nova", "movie_key": "b"}, _details("B")),
        (
            "book_showtime",
            {"cinema": "nova", "showtime_id": "s1"},
            {
                "ok": True,
                "showtime": showtime,
                "timezone": "Africa/Nairobi",
                "suggested": ["A3"]
            }
        ),
        ("my_bookings", {"cinema": "nova"}, booked)
    ];
    cards = cards_from(seen, "Nova Cinemas", "nova");
    # The booking and the bookings always make it; movies give way first.
    assert [c["type"] for c in cards] == ["programme", "booking", "bookings"];
    booking = cards[1];
    assert booking["showtime_id"] == "s1" and booking["suggested"] == ["A3"];
    assert booking["timezone"] == "Africa/Nairobi" and booking["movie"] == "Rafiki";
    mine = cards[2]["bookings"];
    # Shown in the cinema's time, with the seats; nothing else of the order.
    assert mine
        == [
            {
                "movie": "Rafiki",
                "starts": "2026-10-10 18:00",
                "venue": "Westgate",
                "screen": "Screen 1",
                "seats": ["A1", "A2"],
                "upcoming": True
            }
        ];
    # A refused booking or bookings call makes no card.
    refused = [
        (
            "book_showtime",
            {"cinema": "nova", "showtime_id": "x"},
            {"ok": False, "error": "No."}
        ),
        ("my_bookings", {"cinema": "nova"}, {"ok": False, "error": "Sign in."})
    ];
    assert cards_from(refused, "Nova Cinemas", "nova") == [];
}
