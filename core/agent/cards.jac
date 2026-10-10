"""The cards a chat shows beside the agent's words (P8.4), built only from tool results.

The model never writes a card. While the agent works on a message, the tools record
what they returned (tools.SEEN); `cards_from` turns that into at most CARDS_MAX cards:
the cinema's programme (from whats_on) first, then one card per movie (from
movie_details), the latest answer for each, in the order first seen; then (P8.5) the
booking card (from book_showtime) and the signed-in customer's bookings (from
my_bookings), which always fit, movies giving way. A refused tool call makes no card. So a reply that names a showtime no tool returned shows no card.

The storefront chat draws these cards with the storefront's own components; the MCP
programme card (core/mcp/server.jac) is built by the same programme_card.
"""

import from datetime { datetime }
import from zoneinfo { ZoneInfo }
import from core.catalog.trailer { trailer_embed }

glob CARDS_MAX: int = 3;

def programme_card(
    cinema: str,
    slug: str,
    showtimes: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # The showtimes by day (they come earliest first) and each movie once.
    days: list[dict[str, any]] = [];  # jac:ignore[W1037]
    movies: list[dict[str, str]] = [];
    for s in showtimes {
        when = str(s["starts"])[:10];
        if not days or days[-1]["day"] != when {
            days.append({"day": when, "showtimes": []});
        }
        days[-1]["showtimes"].append(s);
        if s["movie_key"] not in [m["movie_key"] for m in movies] {
            movies.append({"movie_key": s["movie_key"], "title": s["movie"]});
        }
    }
    return {
        "type": "programme",
        "cinema": cinema,
        "cinema_slug": slug,
        "movies": movies,
        "days": days
    };
}

def movie_card(
    cinema: str,
    slug: str,
    movie_key: str,
    details: dict[str, any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # A movie's details (movie_details' answer) and the player for its trailer.
    link = str(details.get("trailer_url", ""));
    return {
        "type": "movie",
        "cinema": cinema,
        "cinema_slug": slug,
        "movie_key": movie_key,
        "title": details.get("title", ""),
        "synopsis": details.get("synopsis", ""),
        "runtime_minutes": details.get("runtime_minutes", 0),
        "age_rating": details.get("age_rating", ""),
        "genres": details.get("genres", []),
        "language": details.get("language", ""),
        "trailer_url": link,
        "trailer_embed": trailer_embed(link),
        "showtimes": details.get("showtimes", [])
    };
}

def booking_card(
    cinema: str,
    slug: str,
    result: dict[str, any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # The booking card (P8.5): the showtime, and seats to suggest; the customer's own
    # checkout does the rest.
    shown = result.get("showtime", {});
    return {
        "type": "booking",
        "cinema": cinema,
        "cinema_slug": slug,
        "showtime_id": shown.get("showtime_id", ""),
        "starts": shown.get("starts", ""),
        "movie": shown.get("movie", ""),
        "movie_key": shown.get("movie_key", ""),
        "venue": shown.get("venue", ""),
        "screen": shown.get("screen", ""),
        "timezone": result.get("timezone", ""),
        "suggested": result.get("suggested", [])
    };
}

def _local(starts_at: str, tz: str) -> str {
    if not starts_at {
        return "";
    }
    return datetime.fromisoformat(starts_at).astimezone(
        ZoneInfo(tz or "Africa/Nairobi")
    ).strftime(
        "%Y-%m-%d %H:%M"
    );
}

def bookings_card(
    cinema: str,
    slug: str,
    result: dict[str, any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # The signed-in customer's bookings (P8.5): what, when, where and which seats only;
    # their tickets and codes stay on My tickets.
    return {
        "type": "bookings",
        "cinema": cinema,
        "cinema_slug": slug,
        "bookings": [
            {
                "movie": b.get("movie_title", ""),
                "starts": _local(
                    str(b.get("starts_at", "")), str(b.get("timezone", ""))
                ),
                "venue": b.get("venue", ""),
                "screen": b.get("screen", ""),
                "seats": [str(t.get("seat_label", "")) for t in b.get("tickets", [])],
                "upcoming": bool(b.get("upcoming", False))
            } for b in result.get("bookings", [])[:10]
        ]
    };
}

def cards_from(
    seen: list[tuple[str, dict[str, any], dict[str, any]]],  # jac:ignore[W1037]
    cinema: str,
    slug: str
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The cards for one turn's tool results, (tool, arguments, result) in call order.
    programme: dict[str, any] | None = None;  # jac:ignore[W1037]
    movies: dict[str, dict[str, any]] = {};  # jac:ignore[W1037]
    booking: dict[str, any] | None = None;  # jac:ignore[W1037]
    mine: dict[str, any] | None = None;  # jac:ignore[W1037]
    for (name, args, result) in seen {
        if not isinstance(result, dict) or not result.get("ok", False) {
            continue;
        }
        if name == "whats_on" {
            programme = programme_card(cinema, slug, result.get("showtimes", []));
        } elif name == "movie_details" {
            key = str(args.get("movie_key", ""));
            movies[key] = movie_card(cinema, slug, key, result);
        } elif name == "book_showtime" {
            booking = booking_card(cinema, slug, result);
        } elif name == "my_bookings" {
            mine = bookings_card(cinema, slug, result);
        }
    }
    # The booking and the customer's bookings always fit; movies give way first.
    actions = [
        c
        for c in [booking, mine]
        if c is not None
    ];
    shown = ([programme] if programme is not None else []) + list(movies.values());
    return shown[:CARDS_MAX - len(actions)] + actions;
}
