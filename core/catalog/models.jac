"""Cinema setup: a cinema's venues (its locations) and their auditoriums (screens) (P3.1),
each screen's seat layout versions (P3.2), the cinema's movies (P3.4), and screenings (P3.5a).

Tenant -> Venue -> Auditorium -> SeatLayout and -> Screening, and Tenant -> Movie. The nodes are owned by the cinema's principal
(ADR-0003) and granted to its access group (ADR-0004), like every tenant node. Each keeps
its tenant (and venue) id so a lookup by id can check it belongs to the caller's cinema.
"""

import from core.catalog.layout { Seat }

glob ADDRESS_MAX: int = 200,
     # Each (screen, version number) is an atomic claim, so concurrent saves can't both
     # create the same version (ADR-0007).
     LAYOUT_VERSIONS: str = "layout-version",
     DRAFT: str = "draft",
     PUBLISHED: str = "published";

node Venue {
    has tenant_id: str,
        name: str,
        city: str = "",
        address: str = "",
        created_at: str = "";
}

node Auditorium {
    # schedule_rev changes whenever a screening on this screen is created or moved
    # (P3.5a), so concurrent schedulings of one screen write the same record and the
    # database re-runs all but one: a new screening alone wouldn't clash (ADR-0007).
    has tenant_id: str,
        venue_id: str,
        name: str,
        created_at: str = "",
        schedule_rev: int = 0;
}

node SeatLayout {
    # One numbered version of a screen's seat plan (architecture §21, §22). A draft can
    # be rewritten; once published it never changes, and editing the screen starts the
    # next version, so screenings and tickets keep the seats they were sold on.
    has tenant_id: str,
        venue_id: str,
        auditorium_id: str,
        version: int,
        status: str = DRAFT,
        rows: int = 1,
        cols: int = 1,
        seats: list[Seat] = [],
        updated_at: str = "",
        published_at: str = "";
}

node Movie {
    # A film the cinema shows (P3.4). Belongs to the cinema, not to a venue. The poster
    # is a storage key, "tenant/{tenant_id}/media/{uuid}.webp", or "" for none.
    # public_key names the movie on the storefront (P4.1), so its id never leaves the
    # cinema; it's given when the movie first goes on the storefront.
    has tenant_id: str,
        title: str,
        synopsis: str = "",
        runtime_minutes: int = 0,
        age_rating: str = "",
        genres: list[str] = [],
        language: str = "",
        poster_key: str = "",
        public_key: str = "",
        created_at: str = "",
        updated_at: str = "";
}

node Screening {
    # A movie on a screen at a time (P3.5a). Pins the screen's published layout version
    # when it's created, and keeps it (P3.2). Times are UTC ISO 8601; ends_at includes
    # the cleaning buffer. state is a ScreeningState value (screening_rules.jac).
    has tenant_id: str,
        venue_id: str,
        auditorium_id: str,
        movie_id: str,
        layout_id: str,
        layout_version: int,
        starts_at: str,
        ends_at: str,
        state: str = "draft",
        created_at: str = "",
        updated_at: str = "";
}

node SeatSlot {
    # One seat of one screening: the unit of seat inventory (§25), created when the
    # screening is published (P3.5b), one per seat of its pinned layout. state is
    # "available" or "not_for_sale" (BLOCKED and HOUSE seats); holds and sales come in P4.
    has tenant_id: str,
        screening_id: str,
        label: str,
        row: int,
        col: int,
        seat_type: str,
        zone: str = "",
        state: str = "available";
}

node Storefront {
    # A cinema's public projection on the shared guest graph (§4; spike S7), owned by
    # its principal and granted READ to everyone. Anyone who has a node's id can read
    # all of it, so it holds public fields only: never tenant, staff or internal ids.
    # Reached through Tenant.storefront_id, never by searching root.shared.
    # branding is the published theme and logo (P3.8a): {version, theme, logo}, or {}
    # for the platform default.
    has slug: str,
        name: str,
        branding: dict[str, any] = {};  # jac:ignore[W1037]
}

node StorefrontScreening {
    # One published screening as the storefront shows it (P3.5b). Public fields only.
    has screening_id: str,
        starts_at: str,
        ends_at: str,
        state: str,
        movie: dict[str, any] = {},  # jac:ignore[W1037]
        venue: dict[str, str] = {},
        screen: dict[str, str] = {},
        seat_map: dict[str, any] = {};  # jac:ignore[W1037]
}

node PriceList {
    # A cinema's prices (P3.6): the validated list in parse_price_list's shape, and a
    # version that goes up on every save, so quotes and orders can say which they used.
    has tenant_id: str,
        version: int = 0,
        data: dict[str, any] = {},  # jac:ignore[W1037]
        updated_at: str = "";
}
