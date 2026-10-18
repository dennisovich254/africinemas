"""Test-only app entry for the redemption race (P6.2). Never imported by main.jac.

The production endpoints a published showtime and redeeming need, without the web
client, plus probes that issue a ticket directly (no payment), freeze the clock inside
the door's time window and read a ticket back.
"""

import from datetime { datetime, timedelta }
import from core.tenancy.signup { create_cinema }  # jac:ignore[W2037]
import from core.tenancy.tenant_api { start_shift }  # jac:ignore[W2037]
import from core.catalog.venue_api { create_venue, create_auditorium }  # jac:ignore[W2037]
import from core.catalog.layout_api { save_layout, publish_layout }  # jac:ignore[W2037]
import from core.catalog.movie_api { create_movie }  # jac:ignore[W2037]
import from core.catalog.screening_api {
    create_screening,  # jac:ignore[W2037]
    schedule_screening,  # jac:ignore[W2037]
    publish_screening  # jac:ignore[W2037]
}
import from core.booking.redeem_api { redeem_ticket }  # jac:ignore[W2037]
import from core.clock { freeze }
import from core.claims { make_permanent }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id,
    assign_id
}
import from core.catalog.venues { find_screening }
import from core.booking.models { Ticket }
import from core.booking.ticket_codes { REFS, reserve_reference, qr_payload }

def:pub race_ticket(slug: str, screening_id: str) -> dict[str, str] {
    # One issued ticket for seat A1, as a confirmed payment would issue it.
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    ticket_id = fresh_node_id();
    owner = f"{node_id(cinema)}|{ticket_id}";
    reference = reserve_reference(owner, 60);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        ticket = Ticket(
            tenant_id=node_id(cinema),
            order_id="race-order",
            screening_id=screening_id,
            seat_label="A1",
            ticket_type="ADULT",
            ticket_name="Adult",
            reference=reference,
            qr=qr_payload(reference)
        );
        assign_id(ticket, ticket_id);
        screening ++> ticket;
        attach_to_tenant(ticket, cinema);
        commit_now();
    } finally {
        restore(me);
    }
    make_permanent(REFS, reference, owner);
    return {"reference": reference, "qr": ticket.qr, "ticket_id": ticket_id};
}

def:pub race_freeze(slug: str, screening_id: str, minutes: int) -> str {
    # Freezes the clock `minutes` after the showtime starts. Needs
    # AFRICINEMAS_CLOCK_CONTROL=1.
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    at = datetime.fromisoformat(screening.starts_at) + timedelta(minutes=minutes);
    freeze(at);
    return at.isoformat();
}

def:pub race_ticket_state(slug: str, screening_id: str) -> list[list[str]] {
    # Every ticket of the showtime: [reference, status, used_at].
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [[t.reference, t.status, t.used_at] for t in [screening-->[?:Ticket]]];
    } finally {
        restore(me);
    }
    return found;
}
