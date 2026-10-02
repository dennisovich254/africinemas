"""Seat holds (P4.3) and orders (P4.5): Screening -> SeatHold, Screening -> Order.

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

node Order {
    # An order (P4.5, architecture §26, §27): a visitor's tickets for the seats of one
    # hold, priced by the server and snapshotted, so later price edits never change it.
    # status is "pending_payment" until Phase 5 pays (or ends) it, by pay_by. request
    # is what was asked ([seat, ticket type] pairs, sorted), to tell a replay of the
    # same request from a different one under the same idempotency key. reference is
    # for people (receipts, the box office), never an internal id.
    has tenant_id: str,
        screening_id: str,
        holder: str,
        hold_id: str,
        idempotency_key: str,
        reference: str,
        request: list[list[str]] = [],
        status: str = "pending_payment",
        currency: str = "",
        price_list_version: int = 0,
        lines: list[dict[str, any]] = [],  # jac:ignore[W1037]
        total_cents: int = 0,
        created_at: str = "",
        pay_by: str = "";
}
