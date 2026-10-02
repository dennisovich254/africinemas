"""A cinema's public storefront projection (P3.5b, architecture §4; spike S7).

Published screenings are copied, public fields only, into StorefrontScreening nodes under
the cinema's Storefront on the shared guest graph. The cinema's principal owns them and
grants READ to everyone, so anonymous visitors can read them and nobody else can change
them. The Storefront is recorded on the Tenant (storefront_id) and reached only through
it: anyone may attach nodes to root.shared, so searching there could find impostors.

Writes run as the cinema's principal; call them from a staff request that has already
been authorized.
"""

import from uuid { uuid4 }
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from jaclang { JacRuntime as Jac }
import from core.clock { now }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.catalog.models {
    Movie,
    Venue,
    Auditorium,
    Storefront,
    StorefrontScreening,
    Screening,
    SeatLayout
}
import from core.catalog.venues { find_auditorium, find_layout, find_movie, find_venue }

# Screening states the storefront shows.
glob PUBLIC_STATES: list[str] = ["published", "on_sale", "sales_closed"];

def _read(node_ref: str) -> any {  # jac:ignore[W1037]
    if not node_ref {
        return None;
    }
    try {
        found: any = jobj(node_ref);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    }
    return found;
}

def _storefront(tenant: Tenant) -> Storefront {
    # The cinema's Storefront, made on first use. Call as the cinema's principal.
    found = _read(tenant.storefront_id);
    if isinstance(found, Storefront) {
        return found as Storefront;
    }
    made = Storefront(slug=tenant.slug, name=tenant.name);
    root.shared ++> made;
    grant(made, level=AccessLevel.READ);
    tenant.storefront_id = node_id(made);
    return made;
}

def _entries(storefront: Storefront) -> list[StorefrontScreening] {
    return [storefront-->[?:StorefrontScreening]];
}

def _public_fields(tenant: Tenant, screening: Screening) -> dict[str, any] {  # jac:ignore[W1037]
    # What the storefront may show about a screening: nothing internal.
    movie = find_movie(tenant, screening.movie_id);
    venue = find_venue(tenant, screening.venue_id);
    screen = find_auditorium(tenant, screening.auditorium_id);
    layout = find_layout(tenant, screening.layout_id);
    return {
        "movie": {
            "movie_key": movie.public_key,
            "title": movie.title,
            "synopsis": movie.synopsis,
            "runtime_minutes": movie.runtime_minutes,
            "age_rating": movie.age_rating,
            "genres": list(movie.genres),
            "language": movie.language,
            "has_poster": movie.poster_key != "",
            "has_backdrop": movie.backdrop_key != "",
            "release_date": movie.release_date
        }
            if movie is not None
            else {},
        "venue": {"name": venue.name, "city": venue.city} if venue is not None else {},
        "screen": {"name": screen.name} if screen is not None else {},
        "seat_map": _seat_map(layout)
    };
}

def _seat_map(layout: SeatLayout | None) -> dict[str, any] {  # jac:ignore[W1037]
    if layout is None {
        return {};
    }
    return {
        "rows": layout.rows,
        "cols": layout.cols,
        "seats": [
            {
                "label": s.label,
                "row": s.row,
                "col": s.col,
                "seat_type": s.seat_type,
                "zone": s.zone
            } for s in layout.seats
        ]
    };
}

def give_public_key(movie: Movie | None) {
    # Names the movie on the storefront. Call as the cinema's principal.
    if movie is not None and not movie.public_key {
        movie.public_key = uuid4().hex;
    }
}

def project(tenant: Tenant, screening: Screening) {
    # Puts `screening` on the storefront, or refreshes its entry there.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        give_public_key(find_movie(tenant, screening.movie_id));
        fields = _public_fields(tenant, screening);
        storefront = _storefront(tenant);
        existing = [
            e
            for e in _entries(storefront)
            if e.screening_id == node_id(screening)
        ];
        if existing {
            shown = existing[0];
        } else {
            shown = StorefrontScreening(
                screening_id=node_id(screening),
                starts_at=screening.starts_at,
                ends_at=screening.ends_at,
                state=screening.state
            );
            storefront ++> shown;
            grant(shown, level=AccessLevel.READ);
        }
        shown.starts_at = screening.starts_at;
        shown.ends_at = screening.ends_at;
        shown.state = screening.state;
        shown.movie = fields["movie"];
        shown.venue = fields["venue"];
        shown.screen = fields["screen"];
        shown.seat_map = fields["seat_map"];
        flush_now();
    } finally {
        restore(me);
    }
}

def unproject(tenant: Tenant, screening_id: str) {
    # Takes the screening off the storefront, if it's there.
    storefront = _read(tenant.storefront_id);
    if not isinstance(storefront, Storefront) {
        return;
    }
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        gone = [
            e
            for e in _entries(storefront as Storefront)
            if e.screening_id == screening_id
        ];
        if gone {
            Jac.destroy(gone);
            flush_now();
        }
    } finally {
        restore(me);
    }
}

def public_view(shown: StorefrontScreening) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "screening_id": shown.screening_id,
        "starts_at": shown.starts_at,
        "ends_at": shown.ends_at,
        "state": shown.state,
        "movie": shown.movie,
        "venue": shown.venue,
        "screen": shown.screen,
        "seat_map": shown.seat_map
    };
}

def public_programme(tenant: Tenant) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The storefront's screenings, earliest first, as anyone may read them.
    storefront = _read(tenant.storefront_id);
    if not isinstance(storefront, Storefront) {
        return [];
    }
    shown = sorted(
        _entries(storefront as Storefront),
        key=lambda (e: StorefrontScreening) -> str { return e.starts_at; }  # jac:ignore[W1037]
    );
    return [public_view(e) for e in shown];
}

def set_branding(tenant: Tenant, shown: dict[str, any]) {  # jac:ignore[W1037]
    # Puts the cinema's published theme and logo on its storefront (P3.8a).
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        storefront = _storefront(tenant);
        storefront.branding = shown;
        flush_now();
    } finally {
        restore(me);
    }
}

def branding_of(tenant: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    # The storefront's published theme and logo, as anyone may read them; {} for none.
    storefront = _read(tenant.storefront_id);
    if not isinstance(storefront, Storefront) {
        return {};
    }
    return dict((storefront as Storefront).branding);
}

def upcoming(tenant: Tenant) -> list[StorefrontScreening] {
    # The storefront's screenings that haven't started, earliest first (P4.1).
    storefront = _read(tenant.storefront_id);
    if not isinstance(storefront, Storefront) {
        return [];
    }
    return not_started(_entries(storefront as Storefront), now());
}

def not_started(
    entries: list[StorefrontScreening], at: datetime
) -> list[StorefrontScreening] {
    # The entries starting after `at`, earliest first.
    return sorted(
        [
            e
            for e in entries
            if datetime.fromisoformat(e.starts_at) > at
        ],
        key=lambda (e: StorefrontScreening) -> str { return e.starts_at; }  # jac:ignore[W1037]
    );
}

def showtime(shown: StorefrontScreening) -> dict[str, any] {  # jac:ignore[W1037]
    # A screening as a line in a movie's list of showtimes.
    return {
        "screening_id": shown.screening_id,
        "starts_at": shown.starts_at,
        "venue": shown.venue,
        "screen": shown.screen
    };
}

def on_day(
    entries: list[StorefrontScreening], at: datetime, tz: str
) -> list[StorefrontScreening] {
    # The entries starting on `at`'s calendar day in the cinema's time zone `tz`.
    zone = ZoneInfo(tz);
    day = at.astimezone(zone).date();
    return [
        e
        for e in entries
        if datetime.fromisoformat(e.starts_at).astimezone(zone).date() == day
    ];
}

def by_cinema_day(
    entries: list[StorefrontScreening], at: datetime, tz: str, days: int
) -> list[tuple[str, list[StorefrontScreening]]] {
    # The entries from `at`'s calendar day onward, `days` days in all, grouped by the
    # cinema's calendar day (time zone `tz`): [("2026-10-03", [...]), ...], earliest
    # first, leaving out days without showtimes.
    zone = ZoneInfo(tz);
    first = at.astimezone(zone).date();
    last = first + timedelta(days=days - 1);
    groups: list[tuple[str, list[StorefrontScreening]]] = [];
    for e in sorted(
        entries, key=lambda (e: StorefrontScreening) -> str { return e.starts_at; }
    ) {  # jac:ignore[W1037]
        day = datetime.fromisoformat(e.starts_at).astimezone(zone).date();
        if day < first or day > last {
            continue;
        }
        label = day.isoformat();
        if not groups or groups[len(groups) - 1][0] != label {
            groups.append((label, []));
        }
        groups[len(groups) - 1][1].append(e);
    }
    return groups;
}

def set_home(tenant: Tenant, page: dict[str, any]) {  # jac:ignore[W1037]
    # Puts the cinema's published home page (movies named by key) on its storefront.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        storefront = _storefront(tenant);
        storefront.home = page;
        flush_now();
    } finally {
        restore(me);
    }
}

def home_of(tenant: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    # The storefront's published home page, as anyone may read it; {} for the default.
    storefront = _read(tenant.storefront_id);
    if not isinstance(storefront, Storefront) {
        return {};
    }
    return dict((storefront as Storefront).home);
}

def movies_by_key(tenant: Tenant) -> dict[str, Movie] {
    # The cinema's movies that have a public key, by key.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found = [tenant-->[?:Movie]];
    } finally {
        restore(me);
    }
    return {
        m.public_key: m
        for m in found
        if m.public_key
    };
}

def venues_with_screens(tenant: Tenant) -> list[tuple[Venue, int]] {
    # The cinema's venues, each with its number of screens (P4.1d).
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found = [(v, len([v-->[?:Auditorium]])) for v in [tenant-->[?:Venue]]];
    } finally {
        restore(me);
    }
    return found;
}
