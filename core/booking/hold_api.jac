"""Seat holds (P4.3, architecture §24, §25; ADR-0007, ADR-0010): public endpoints, no
login, listed in tests/isolation/registry.jac.

A visitor holds seats of a showtime on the storefront for HOLD_SECONDS while they check
out. The browser names the visitor with a random holder id it keeps for the visit; a
hold is one per (showtime, holder).

- Each seat is an atomic claim (core/claims.jac) in the showtime's namespace, owned by
  the holder and expiring with the hold. A claim is one statement on a primary key, so
  of any number of simultaneous requests for a seat exactly one wins. The owner is the
  holder, not a fresh id, so a request the server replays after a write conflict finds
  its own claims and carries on.
- A request holds all its seats or none: if one is taken, the claims it made are
  released and it answers "seats_taken" with the taken seats.
- Holding again replaces the holder's seats (those no longer wanted are released), up
  to MAX_SEATS. extend_hold pushes the expiry out, never beyond MAX_SECONDS from the
  hold's start. release_hold frees the seats.
- The seats' SeatSlots record the hold too (state "held", hold_expires_at, hold_id), so
  availability reads (P4.2) show it; a hold past its time lapses on every read.
- Only showtimes on the cinema's storefront that haven't started can be held.
"""

import os;
import re;
import math;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, release, renew }
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.authz.context { NotFound }
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Screening, SeatSlot }
import from core.catalog.storefront { upcoming }
import from core.catalog.venues { find_screening, slots_of }
import from core.booking.models { SeatHold }
import from core.booking.availability { SeatState }

glob HOLD_ENV: str = "AFRICINEMAS_HOLD_SECONDS",
     MAX_ENV: str = "AFRICINEMAS_HOLD_MAX_SECONDS",
     HOLD_SECONDS: int = 480,
     MAX_SECONDS: int = 900,
     MAX_SEATS: int = 10,
     HOLDER_PATTERN: str = "[A-Za-z0-9_-]{16,64}";

def _seconds(env: str, fallback: int) -> int {
    # A duration from the environment (tests shorten holds), or the default.
    try {
        value = int(os.environ.get(env, ""));
    } except ValueError {
        return fallback;
    }
    return value if value > 0 else fallback;
}

def _namespace(screening_id: str) -> str {
    return f"seat:{screening_id}";
}

def _showtime(slug: str, screening_id: str) -> tuple[Tenant, Screening] {
    # The cinema and the showtime, if it's on the storefront and hasn't started.
    cinema = open_cinema(slug);
    if cinema is None or not screening_id {
        raise NotFound();
    }
    if not any(e.screening_id == screening_id for e in upcoming(cinema)) {
        raise NotFound();
    }
    screening = find_screening(cinema, screening_id);
    if screening is None {
        raise NotFound();
    }
    return (cinema, screening);
}

def _check_holder(holder: str) {
    if not isinstance(holder, str) or not re.fullmatch(HOLDER_PATTERN, holder) {
        raise Refused(
            "invalid_holder", "This page lost track of you. Reload it and try again."
        );
    }
}

def _live(hold: SeatHold) -> bool {
    return hold.status == "held"
        and bool(hold.expires_at)
        and datetime.fromisoformat(hold.expires_at) > now();
}

def _current(cinema: Tenant, screening: Screening, holder: str) -> SeatHold | None {
    # The holder's live hold on this showtime, if any.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            h
            for h in [screening-->[?:SeatHold]]
            if h.holder == holder and _live(h)
        ];
    } finally {
        restore(me);
    }
    return found[0] if found else None;
}

def _view(hold: SeatHold) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "seats": list(hold.seats),
        "expires_at": hold.expires_at,
        "status": hold.status
    };
}

def _mark(slots: list[SeatSlot], labels: list[str], hold_id: str, until: str) {
    # Records the hold on its seats' slots. Call as the cinema's principal.
    for x in slots {
        if x.label in labels {
            x.state = SeatState.HELD.value;
            x.hold_expires_at = until;
            x.hold_id = hold_id;
        }
    }
}

def _unmark(slots: list[SeatSlot], labels: list[str], hold_id: str) {
    # Frees seats this hold no longer has. Call as the cinema's principal.
    for x in slots {
        if x.label in labels
            and x.hold_id == hold_id
            and x.state == SeatState.HELD.value {
            x.state = SeatState.AVAILABLE.value;
            x.hold_expires_at = "";
            x.hold_id = "";
        }
    }
}

def _hold_seats(
    slug: str, screening_id: str, holder: str, labels: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, screening) = _showtime(slug, screening_id);
    _check_holder(holder);
    wanted: list[str] = [];
    for label in labels or [] {
        cleaned = str(label).strip();
        if cleaned and cleaned not in wanted {
            wanted.append(cleaned);
        }
    }
    if not wanted {
        raise Refused("no_seats", "Choose at least one seat.");
    }
    if len(wanted) > MAX_SEATS {
        raise Refused(
            "too_many_seats", f"You can hold up to {MAX_SEATS} seats at a time."
        );
    }
    slots = slots_of(cinema, screening);
    by_label = {x.label: x for x in slots};
    unknown = [
        label
        for label in wanted
        if label not in by_label
    ];
    if unknown {
        raise Refused(
            "unknown_seats", "Some of these seats don't exist.", {"seats": unknown}
        );
    }
    unsellable = [
        label
        for label in wanted
        if by_label[label].state == SeatState.NOT_FOR_SALE.value
    ];
    if unsellable {
        raise Refused(
            "not_for_sale",
            "Some of these seats aren't for sale.",
            {"seats": unsellable}
        );
    }
    previous = _current(cinema, screening, holder);
    kept: list[str] = list(previous.seats) if previous is not None else [];
    seconds = _seconds(HOLD_ENV, HOLD_SECONDS);
    space = _namespace(screening_id);
    claimed: list[str] = [];
    taken: list[str] = [];
    for label in wanted {
        if claim(space, label, holder, seconds) == holder {
            claimed.append(label);
        } else {
            taken.append(label);
        }
    }
    if taken {
        # All or nothing: give back what this request claimed (not seats it already had).
        for label in claimed {
            if label not in kept {
                release(space, label, holder);
            }
        }
        raise Refused(
            "seats_taken",
            "Someone else has just taken some of these seats.",
            {"seats": taken}
        );
    }
    for label in wanted {
        renew(space, label, holder, seconds);
    }
    dropped = [
        label
        for label in kept
        if label not in wanted
    ];
    for label in dropped {
        release(space, label, holder);
    }
    stamp = now();
    until = (stamp + timedelta(seconds=seconds)).isoformat();
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        hold: SeatHold | None = previous;
        if hold is None {
            hold = SeatHold(
                tenant_id=node_id(cinema),
                screening_id=screening_id,
                holder=holder,
                created_at=stamp.isoformat()
            );
            screening ++> hold;
            attach_to_tenant(hold, cinema);
        }
        made: SeatHold = hold;
        made.seats = wanted;
        made.status = "held";
        made.expires_at = until;
        hold_id = node_id(made);
        _unmark(slots, dropped, hold_id);
        _mark(slots, wanted, hold_id, until);
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "hold": _view(made)};
}

def _my_hold(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, screening) = _showtime(slug, screening_id);
    _check_holder(holder);
    hold = _current(cinema, screening, holder);
    if hold is None {
        raise Refused("no_hold", "You aren't holding any seats for this showtime.");
    }
    return {"ok": True, "hold": _view(hold)};
}

def _release_hold(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, screening) = _showtime(slug, screening_id);
    _check_holder(holder);
    hold = _current(cinema, screening, holder);
    if hold is None {
        raise Refused("no_hold", "You aren't holding any seats for this showtime.");
    }
    space = _namespace(screening_id);
    for label in hold.seats {
        release(space, label, holder);
    }
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        _unmark(slots_of(cinema, screening), list(hold.seats), node_id(hold));
        hold.status = "released";
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True};
}

def _extend_hold(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Pushes the hold's expiry out by HOLD_SECONDS, but never beyond MAX_SECONDS from
    # when the hold began.
    (cinema, screening) = _showtime(slug, screening_id);
    _check_holder(holder);
    hold = _current(cinema, screening, holder);
    if hold is None {
        raise Refused("no_hold", "You aren't holding any seats for this showtime.");
    }
    stamp = now();
    limit = datetime.fromisoformat(hold.created_at)
        + timedelta(seconds=_seconds(MAX_ENV, MAX_SECONDS));
    until = min(stamp + timedelta(seconds=_seconds(HOLD_ENV, HOLD_SECONDS)), limit);
    seconds = max(1, math.ceil((until - stamp).total_seconds()));
    space = _namespace(screening_id);
    for label in hold.seats {
        if not renew(space, label, holder, seconds) {
            raise Refused(
                "no_hold", "Your hold has just ended. Choose your seats again."
            );
        }
    }
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        hold.expires_at = until.isoformat();
        _mark(
            slots_of(cinema, screening),
            list(hold.seats),
            node_id(hold),
            hold.expires_at
        );
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "hold": _view(hold)};
}

def:pub hold_seats(
    slug: str, screening_id: str, holder: str, labels: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _hold_seats(slug, screening_id, holder, labels); }  # jac:ignore[W1037]
    );
}

def:pub my_hold(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _my_hold(slug, screening_id, holder); });  # jac:ignore[W1037]
}

def:pub release_hold(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _release_hold(slug, screening_id, holder); });  # jac:ignore[W1037]
}

def:pub extend_hold(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _extend_hold(slug, screening_id, holder); });  # jac:ignore[W1037]
}
