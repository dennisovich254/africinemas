"""Seat holds (P4.3): Screening -> SeatHold.

Owned by the cinema's principal (ADR-0003) and granted to its access group (ADR-0004),
like every tenant node. A hold is one visitor's seats on one showtime for a few minutes;
the seats themselves are atomic claims (core/claims.jac), the source of truth for who
holds them. The hold node records what the visitor holds, for them and for staff.
"""

node SeatHold {
    # holder is the visitor's random id (kept by their browser for the visit). status
    # is "held" while live, "released" or "replaced" after; a hold past expires_at has
    # lapsed whatever its status says.
    has tenant_id: str,
        screening_id: str,
        holder: str,
        seats: list[str] = [],
        status: str = "held",
        created_at: str = "",
        expires_at: str = "";
}
