"""The hold expiry sweeper (P4.4, architecture §24; ADR-0005, ADR-0007).

Holds lapse by themselves: every read treats a hold past its time as gone (P4.2), and
its seat claims expire with it. So nothing waits for the sweeper; it is housekeeping.
For each open hold (OPEN_HOLDS, listed when the hold is made) it:

- marks a plain hold whose time is up "expired" and frees its seats' slots, but only
  slots it still holds (a newer hold may have taken a seat since);
- never touches a paying hold (PAYMENT_PENDING seats), however late: only the payment's
  outcome ends it;
- drops ended holds (released, replaced, expired) from the list, and entries whose hold
  never got made (its request failed) once they are DANGLING_SECONDS old.

It leaves the seat claims alone (a holder's claim may belong to their newer hold) and
deletes only lapsed ones (and lapsed VISITOR_HOLDS entries), which hold nothing. Every server copy runs it, and each step
does nothing the second time, so running it twice, or at once, changes nothing more.
"""

import os;
import from datetime { datetime }
import from core.clock { now }
import from core.claims { claims_in, release, drop_lapsed }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    system_root_id
}
import from core.catalog.venues { find_screening, slots_of }
import from core.booking.models { SeatHold }
import from core.booking.availability { SeatState }
import from core.booking.hold_api { OPEN_HOLDS, VISITOR_HOLDS, free_seats }

# How often it runs; tests shorten it (AFRICINEMAS_SWEEP_SECONDS).
glob SWEEP_SECONDS: int = int(os.environ.get("AFRICINEMAS_SWEEP_SECONDS", "60")),
     DANGLING_SECONDS: int = 300,
     ENDED: list[str] = ["released", "replaced", "expired"];

def due(status: str, expires_at: str, paying: bool, at: datetime) -> bool {
    # A plain hold whose time is up at `at`; a paying hold never is.
    if status != "held" or paying {
        return False;
    }
    return not expires_at or datetime.fromisoformat(expires_at) <= at;
}

def settled(status: str) -> bool {
    # An ended hold: nothing more for the sweeper to do.
    return status in ENDED;
}

def open_holds -> list[str] {
    # The ids of the holds still listed as open.
    return [listed[0] for listed in claims_in(OPEN_HOLDS)];
}

def _read(node_ref: str) -> any {  # jac:ignore[W1037]
    # A node by id, read as the system root (the sweeper acts for no caller).
    me = node_id(root);
    act_as(system_root_id());
    try {
        found: any = jobj(node_ref);  # jac:ignore[W1037]
    } finally {
        restore(me);
    }
    return found;
}

def _expire(tenant: Tenant, hold: SeatHold, at: datetime) -> bool {
    # Ends `hold` if it is due, freeing the slots it still holds. True when it ended.
    screening = find_screening(tenant, hold.screening_id);
    slots = slots_of(tenant, screening) if screening is not None else [];
    hold_id = node_id(hold);
    paying = any(
        x.hold_id == hold_id and x.state == SeatState.PAYMENT_PENDING.value
        for x in slots
    );
    if not due(hold.status, hold.expires_at, paying, at) {
        return False;
    }
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        free_seats(slots, list(hold.seats), hold_id);
        hold.status = "expired";
        flush_now();
    } finally {
        restore(me);
    }
    return True;
}

def sweep -> dict[str, int] {
    # One pass over the open holds; returns how many holds it expired and how many
    # lapsed seat claims it deleted.
    at = now();
    expired = 0;
    for (hold_ref, tenant_id, age) in claims_in(OPEN_HOLDS) {
        hold = _read(hold_ref);
        tenant = _read(tenant_id);
        if not isinstance(hold, SeatHold) or not isinstance(tenant, Tenant) {
            if age >= DANGLING_SECONDS {
                release(OPEN_HOLDS, hold_ref, tenant_id);
            }
            continue;
        }
        if _expire(tenant as Tenant, hold as SeatHold, at) {
            expired += 1;
        }
        if settled((hold as SeatHold).status) {
            release(OPEN_HOLDS, hold_ref, tenant_id);
        }
    }
    deleted = drop_lapsed("seat") + drop_lapsed(VISITOR_HOLDS);
    return {"expired": expired, "claims_deleted": deleted};
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=SWEEP_SECONDS)
def sweep_holds {
    # Runs as Jac's system identity on every server copy.
    sweep();
}
