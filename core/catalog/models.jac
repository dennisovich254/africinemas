"""Cinema setup: a cinema's venues (its locations) and their auditoriums (screens) (P3.1),
and each screen's seat layout versions (P3.2).

Tenant -> Venue -> Auditorium -> SeatLayout. The nodes are owned by the cinema's principal
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
    has tenant_id: str,
        venue_id: str,
        name: str,
        created_at: str = "";
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
