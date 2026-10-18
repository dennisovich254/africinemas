"""Test-only app entry for the hold expiry sweeper (P4.4). Never imported by main.jac.

The production endpoints a showtime and its holds need, plus probes that run the sweep
on demand and read what is stored (not the effective state every read shows). Served by
a real server, the scheduled sweep runs too (hold_sweeper_schedule_tests.jac).
"""

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
import from core.catalog.storefront_api { public_seat_availability }  # jac:ignore[W2037]
import from core.booking.hold_api { hold_seats, release_hold }  # jac:ignore[W2037]
import from core.claims { holder }
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.catalog.venues { find_screening, slots_of }
import from core.catalog.models { Screening, SeatSlot }
import from core.booking.models { SeatHold }
import from core.booking.sweeper { sweep, open_holds, sweep_holds }  # jac:ignore[W2037]

def _showtime(slug: str, screening_id: str) -> tuple[Tenant, Screening] {
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    return (cinema, screening);
}

def _holds_of(slots: list[SeatSlot]) -> list[SeatHold] {
    # A showtime's holds, oldest first. Each hangs on its first seat (P4.7). Call as
    # the cinema's principal.
    found: list[SeatHold] = [];
    for x in slots {
        for h in [x-->[?:SeatHold]] {
            found.append(h);
        }
    }
    return sorted(
        found,
        key=lambda (h: SeatHold) -> str { return h.created_at; }  # jac:ignore[W1037]
    );
}

def:pub sw_sweep -> dict[str, int] {
    return sweep();
}

def:pub sw_open_holds -> int {
    return len(open_holds());
}

def:pub sw_seat_claim(screening_id: str, label: str) -> str | None {
    return holder(f"seat:{screening_id}", label);
}

def:pub sw_stored(slug: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The slots' stored states and the showtime's holds (holder, status), oldest first.
    (cinema, screening) = _showtime(slug, screening_id);
    seat_slots = slots_of(cinema, screening);
    slots = {x.label: x.state for x in seat_slots};
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [[h.holder, h.status] for h in _holds_of(seat_slots)];
    } finally {
        restore(me);
    }
    return {"slots": slots, "holds": found};
}

def:pub sw_pay(slug: str, screening_id: str, holder_id: str) -> bool {
    # Stands in for checkout (P4.5): the holder's seats become payment pending.
    (cinema, screening) = _showtime(slug, screening_id);
    slots = slots_of(cinema, screening);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        holds = [
            h
            for h in _holds_of(slots)
            if h.holder == holder_id and h.status == "held"
        ];
        for x in slots {
            if x.label in holds[0].seats {
                x.state = "payment_pending";
            }
        }
        flush_now();
    } finally {
        restore(me);
    }
    return True;
}
