"""Cinema setup (P3.1): a cinema's venues (its locations) and their auditoriums (screens).

Tenant -> Venue -> Auditorium. The nodes are owned by the cinema's principal
(ADR-0003) and granted to its access group (ADR-0004), like every tenant node. Each keeps
its tenant (and venue) id so a lookup by id can check it belongs to the caller's cinema.
"""

glob ADDRESS_MAX: int = 200;

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
