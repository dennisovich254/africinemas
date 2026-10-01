"""The public storefront reads (P4.1, architecture §41): a cinema's home page, a movie's
page, a showtime's page and a movie's poster, for anyone, without a login.

They read only the cinema's Storefront projection (core/catalog/storefront.jac), so they
show only published screenings, and only those that haven't started. A movie is on the
storefront while it has one, named by its public key, never its id. A cinema is found by
its slug and everything else through it, so one cinema's address never shows another's
data: anything not on this cinema's storefront is "not_found".
"""

import base64;
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.responses { NOT_FOUND, refused }
import from core.catalog.models { StorefrontScreening }
import from core.catalog.storefront { upcoming, showtime, public_view }
import from core.catalog.venues { find_screening, find_movie }
import from core.catalog.poster { media_store }

# How many of a movie's next showtimes the home page lists.
glob NEXT_SHOWTIMES: int = 6;

def _cinema(tenant: Tenant) -> dict[str, str] {
    return {"name": tenant.name, "slug": tenant.slug};
}

def _showing(tenant: Tenant, movie_key: str) -> list[StorefrontScreening] {
    # The upcoming showtimes of the movie with this public key.
    if not movie_key {
        return [];
    }
    return [
        e
        for e in upcoming(tenant)
        if e.movie.get("movie_key") == movie_key
    ];
}

def _movie_card(entries: list[StorefrontScreening]) -> dict[str, any] {  # jac:ignore[W1037]
    # A movie on the home page, from its upcoming showtimes (earliest first).
    movie = entries[0].movie;
    return {
        "movie_key": movie["movie_key"],
        "title": movie["title"],
        "age_rating": movie["age_rating"],
        "runtime_minutes": movie["runtime_minutes"],
        "genres": movie["genres"],
        "language": movie["language"],
        "has_poster": movie["has_poster"],
        "next": [showtime(e) for e in entries[:NEXT_SHOWTIMES]]
    };
}

def:pub public_home(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The cinema's home page: each movie on sale once, the soonest first, with its next
    # showtimes, and the venues showing them.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    by_movie: dict[str, list[StorefrontScreening]] = {};
    venues: list[dict[str, str]] = [];
    for e in upcoming(cinema) {
        by_movie.setdefault(e.movie.get("movie_key", ""), []).append(e);
        if e.venue not in venues {
            venues.append(e.venue);
        }
    }
    return {
        "ok": True,
        "cinema": _cinema(cinema),
        "movies": [_movie_card(entries) for entries in by_movie.values()],
        "venues": venues
    };
}

def:pub public_movie(slug: str, movie_key: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A movie's page: its details and every upcoming showtime.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    entries = _showing(cinema, movie_key);
    if not entries {
        return NOT_FOUND;
    }
    return {
        "ok": True,
        "cinema": _cinema(cinema),
        "movie": entries[0].movie,
        "screenings": [public_view(e) for e in entries]
    };
}

def:pub public_screening(slug: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A showtime's page: the movie, when and where, and the seat map.
    cinema = open_cinema(slug);
    if cinema is None or not screening_id {
        return NOT_FOUND;
    }
    for e in upcoming(cinema) {
        if e.screening_id == screening_id {
            return {"ok": True, "cinema": _cinema(cinema), "screening": public_view(e)};
        }
    }
    return NOT_FOUND;
}

def:pub public_poster(slug: str, movie_key: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A movie's poster as a WebP data URL, while the movie is on the storefront.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    entries = _showing(cinema, movie_key);
    if not entries {
        return NOT_FOUND;
    }
    screening = find_screening(cinema, entries[0].screening_id);
    movie = find_movie(cinema, screening.movie_id) if screening is not None else None;
    data = media_store().download(movie.poster_key)
        if movie is not None and movie.poster_key
        else None;
    if not data {
        return refused("no_poster", "This movie has no poster yet.");
    }
    return {
        "ok": True,
        "poster": f"data:image/webp;base64,{base64.b64encode(data).decode()}"
    };
}
