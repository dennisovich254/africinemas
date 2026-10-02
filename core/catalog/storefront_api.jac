"""The public storefront reads (P4.1, architecture §41): a cinema's home page, a movie's
page, a showtime's page and a movie's poster, for anyone, without a login.

They read only the cinema's Storefront projection (core/catalog/storefront.jac), so they
show only published screenings, and only those that haven't started. A movie is on the
storefront while it has one, named by its public key, never its id. A cinema is found by
its slug and everything else through it, so one cinema's address never shows another's
data: anything not on this cinema's storefront is "not_found".

public_home also carries the cinema's published home page (P4.1b, core/homepage/), its
sections filled from the programme; hidden sections and sections with nothing to show
are left out. Movies the page shows as coming soon are public too, with their posters; a
featured movie is shown only if it's on sale or coming soon, else the next one on sale.
"""

import base64;
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.responses { NOT_FOUND, refused }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.pricing { DEFAULT_TIMEZONE }
import from core.clock { now }
import from core.catalog.models { Movie, PriceList, StorefrontScreening }
import from core.catalog.storefront {
    upcoming,
    showtime,
    public_view,
    by_cinema_day,
    venues_with_screens,
    home_of,
    movies_by_key
}
import from core.homepage.page { default_page }
import from core.catalog.venues { find_screening, find_movie }
import from core.catalog.poster { media_store, media_key }

# How many of a movie's next showtimes the home page lists.
glob NEXT_SHOWTIMES: int = 6,
     # How many days ahead the home page's showtimes-by-day section looks (P4.1c).
     DAYS_AHEAD: int = 7,
     # How many days ahead quick book offers showtimes (P4.1d).
     SHOWTIME_DAYS: int = 14;

def _timezone(tenant: Tenant) -> str {
    # The cinema's time zone, from its price list (P3.6), for showing showtimes in the
    # cinema's local time wherever the visitor is.
    if not tenant.price_list_id {
        return DEFAULT_TIMEZONE;
    }
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found: any = jobj(tenant.price_list_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    if not isinstance(found, PriceList) {
        return DEFAULT_TIMEZONE;
    }
    return (found as PriceList).data.get("timezone") or DEFAULT_TIMEZONE;
}

def _cinema(tenant: Tenant) -> dict[str, str] {
    return {"name": tenant.name, "slug": tenant.slug, "timezone": _timezone(tenant)};
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
        "has_backdrop": movie.get("has_backdrop", False),
        "release_date": movie.get("release_date", ""),
        "next": [showtime(e) for e in entries[:NEXT_SHOWTIMES]],
        # The venues it's showing at, by name, for the venue picker (P4.1d).
        "venues": sorted(
            set(e.venue.get("name", "") for e in entries), key=str.casefold
        )
    };
}

def programme(
    cinema: Tenant
) -> tuple[list[StorefrontScreening], list[dict[str, any]], list[dict[str, str]]] {  # jac:ignore[W1037]
    # The upcoming showtimes, each movie on sale once (the soonest first, with its next
    # showtimes) and the venues showing them.
    entries = upcoming(cinema);
    by_movie: dict[str, list[StorefrontScreening]] = {};
    venues: list[dict[str, str]] = [];
    for e in entries {
        by_movie.setdefault(e.movie.get("movie_key", ""), []).append(e);
        if e.venue not in venues {
            venues.append(e.venue);
        }
    }
    return (entries, [_movie_card(group) for group in by_movie.values()], venues);
}

def cinema_info(cinema: Tenant) -> dict[str, str] {
    # The cinema's name, slug and time zone, as its storefront pages show them.
    return _cinema(cinema);
}

def:pub public_home(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The cinema's home page: its published page with its sections filled in, plus
    # each movie on sale once and the venues showing them.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    (entries, cards, venues) = programme(cinema);
    shown = _cinema(cinema);
    page = _published(cinema);
    known = movies_by_key(cinema) if _soon_keys(page) else {};
    return {
        "ok": True,
        "cinema": shown,
        "movies": cards,
        "venues": venues,
        "page": fill_page(page, entries, cards, shown["timezone"], known),
        # Every showtime of the next SHOWTIME_DAYS days, for quick book (P4.1d).
        "showtimes": [
            _day_showtime(e)
            for (_, group) in by_cinema_day(
                entries, now(), shown["timezone"], SHOWTIME_DAYS
            ) for e in group
        ]
    };
}

def _published(cinema: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    # The published page, or the default page in the same shape (movies by key).
    page = home_of(cinema);
    if page {
        return page;
    }
    fallback = default_page();
    for s in fallback["sections"] {
        if s["type"] == "hero" {
            s["fields"] = {"headline": "", "text": "", "movie_key": ""};
        } elif s["type"] == "coming_soon" {
            s["fields"] = {"title": "", "movie_keys": []};
        }
    }
    return fallback;
}

def _soon_keys(page: dict[str, any]) -> list[str] {  # jac:ignore[W1037]
    # The movie keys a published page shows as coming soon. With the movies on sale,
    # these are the only movies the storefront shows.
    for s in page.get("sections", []) {
        if s["type"] == "coming_soon" and s["visible"] {
            return list(s["fields"].get("movie_keys", []));
        }
    }
    return [];
}

def _soon_card(movie: Movie) -> dict[str, any] {  # jac:ignore[W1037]
    # A movie listed as coming soon, which may have no showtimes yet.
    return {
        "movie_key": movie.public_key,
        "title": movie.title,
        "synopsis": movie.synopsis,
        "age_rating": movie.age_rating,
        "runtime_minutes": movie.runtime_minutes,
        "genres": list(movie.genres),
        "language": movie.language,
        "has_poster": movie.poster_key != "",
        "has_backdrop": movie.backdrop_key != "",
        "release_date": movie.release_date
    };
}

def _has_content(fields: dict[str, any]) -> bool {  # jac:ignore[W1037]
    # Whether a text section has anything besides its title.
    return any(
        bool(v)
        for (k, v) in fields.items()
        if k != "title"
    );
}

def _day_showtime(e: StorefrontScreening) -> dict[str, any] {  # jac:ignore[W1037]
    # A showtime in the by-day list, with what the storefront needs to group it by movie.
    return dict(
        showtime(e),
        movie_key=e.movie.get("movie_key", ""),
        title=e.movie.get("title", ""),
        has_poster=e.movie.get("has_poster", False)
    );
}

def fill_page(
    page: dict[str, any],  # jac:ignore[W1037]
    entries: list[StorefrontScreening],
    cards: list[dict[str, any]],  # jac:ignore[W1037]
    tz: str,
    known: dict[str, Movie]
) -> dict[str, any] {  # jac:ignore[W1037]
    # A page (movies named by key) with its sections filled in from the programme,
    # leaving out hidden ones and those with nothing to show. `known` holds the movies
    # coming soon can show, by key.
    soon_keys = _soon_keys(page);
    on_sale = {c["movie_key"]: c for c in cards};
    sections: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in page["sections"] {
        if not s["visible"] {
            continue;
        }
        kind = s["type"];
        fields = dict(s["fields"]);
        if kind == "hero" {
            key = fields.pop("movie_key", "");
            featured = on_sale.get(key);
            if featured is None and key in soon_keys and key in known {
                featured = _soon_card(known[key]);
            }
            if featured is None and cards {
                featured = cards[0];
            }
            if featured is not None or fields["headline"] or fields["text"] {
                sections.append({"type": kind, "fields": fields, "movie": featured});
            }
        } elif kind == "today" {
            # Showtimes by day (P4.1c): the next DAYS_AHEAD cinema days with showtimes.
            days = [
                {"date": day, "showtimes": [_day_showtime(e) for e in group]}
                for (day, group) in by_cinema_day(entries, now(), tz, DAYS_AHEAD)
            ];
            if days {
                sections.append({"type": kind, "fields": fields, "days": days});
            }
        } elif kind == "now_showing" {
            if cards {
                sections.append({"type": kind, "fields": fields, "movies": cards});
            }
        } elif kind == "coming_soon" {
            soon = [
                _soon_card(known[k])
                for k in fields.pop("movie_keys", [])
                if k in known
            ];
            if soon {
                sections.append({"type": kind, "fields": fields, "movies": soon});
            }
        } elif _has_content(fields) {
            sections.append({"type": kind, "fields": fields});
        }
    }
    return {"template": page["template"], "sections": sections};
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

def _public_movie(cinema: Tenant, movie_key: str) -> tuple[bool, Movie | None] {
    # (on the storefront?, the movie) for a public key: a movie is public while it's on
    # sale or coming soon on the published home page.
    entries = _showing(cinema, movie_key);
    if entries {
        screening = find_screening(cinema, entries[0].screening_id);
        if screening is None {
            return (True, None);
        }
        return (True, find_movie(cinema, screening.movie_id));
    }
    if movie_key and movie_key in _soon_keys(home_of(cinema)) {
        return (True, movies_by_key(cinema).get(movie_key));
    }
    return (False, None);
}

def _image(cinema: Tenant, movie_key: str, kind: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A public movie's poster or backdrop as a WebP data URL.
    (public, movie) = _public_movie(cinema, movie_key);
    if not public {
        return NOT_FOUND;
    }
    key = "";
    if movie is not None {
        key = movie.poster_key if kind == "poster" else movie.backdrop_key;
    }
    data = media_store().download(key) if key else None;
    if not data {
        return refused(f"no_{kind}", f"This movie has no {kind} yet.");
    }
    return {
        "ok": True,
        kind: f"data:image/webp;base64,{base64.b64encode(data).decode()}"
    };
}

def:pub public_poster(slug: str, movie_key: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A movie's poster as a WebP data URL, while the movie is on the storefront: on sale,
    # or coming soon on the published home page.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    return _image(cinema, movie_key, "poster");
}

def:pub public_backdrop(slug: str, movie_key: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A movie's landscape backdrop (P4.1c), on the same terms as its poster.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    return _image(cinema, movie_key, "backdrop");
}

def _shown_photos(page: dict[str, any]) -> list[str] {  # jac:ignore[W1037]
    # The photos a published page shows: those of a visible About section.
    for s in page.get("sections", []) {
        if s["type"] == "about" and s["visible"] {
            return list(s["fields"].get("photos", []));
        }
    }
    return [];
}

def photo_data_url(cinema: Tenant, photo: str) -> str {
    # One of the cinema's home-page photos as a WebP data URL, or "" if it's gone.
    data = media_store().download(media_key(node_id(cinema), photo)) if photo else None;
    return f"data:image/webp;base64,{base64.b64encode(data).decode()}" if data else "";
}

def:pub public_home_photo(slug: str, photo: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A photo the cinema's published home page shows, as a WebP data URL.
    cinema = open_cinema(slug);
    if cinema is None or not photo or photo not in _shown_photos(home_of(cinema)) {
        return NOT_FOUND;
    }
    shown = photo_data_url(cinema, photo);
    return {"ok": True, "photo": shown} if shown else NOT_FOUND;
}

def:pub public_venues(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The cinema's venues for Find a cinema (P4.1d): name, city, address, how many
    # screens and how many upcoming showtimes, by name. Names are unique per cinema,
    # so the storefront filters by them; no ids leave the server.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    counts: dict[str, int] = {};
    for e in upcoming(cinema) {
        name = e.venue.get("name", "");
        counts[name] = counts.get(name, 0) + 1;
    }
    venues = [
        {
            "name": v.name,
            "city": v.city,
            "address": v.address,
            "screens": screens,
            "showtimes": counts.get(v.name, 0)
        } for (v, screens) in venues_with_screens(cinema)
    ];
    def by_name(v: dict[str, any]) -> str {  # jac:ignore[W1037]
        return v["name"].casefold();
    }
    return {
        "ok": True,
        "cinema": _cinema(cinema),
        "venues": sorted(venues, key=by_name)
    };
}
