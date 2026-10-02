"""P4.2: a seat's state at a moment, as everyone sees it (core/booking/availability.jac).

A hold lapses by itself when its time is up: every read treats an expired hold as
available, so nothing waits for the sweeper (architecture §24). A hold that is paying
(PAYMENT_PENDING) never lapses this way. Every state has text, not only a colour
(architecture §102), and only available seats can be sold.
"""

import from datetime { datetime, timedelta, timezone }
import from core.booking.availability {
    SeatState,
    effective_state,
    public_state,
    state_text,
    sellable
}

glob NOW: datetime = datetime(2026, 10, 3, 18, 0, tzinfo=timezone.utc);

def _at(minutes: int) -> str {
    return (NOW + timedelta(minutes=minutes)).isoformat();
}

test "a hold counts until it expires, then the seat is available again" {
    assert effective_state("held", _at(5), NOW) == SeatState.HELD;
    assert effective_state("held", _at(0), NOW) == SeatState.AVAILABLE;
    assert effective_state("held", _at(-1), NOW) == SeatState.AVAILABLE;
    assert effective_state("held", "", NOW) == SeatState.AVAILABLE;
}

test "a paying hold never lapses by itself; sold and unsellable seats stay as they are" {
    assert effective_state("payment_pending", _at(-30), NOW)
        == SeatState.PAYMENT_PENDING;
    assert effective_state("sold", "", NOW) == SeatState.SOLD;
    assert effective_state("not_for_sale", "", NOW) == SeatState.NOT_FOR_SALE;
    assert effective_state("available", _at(5), NOW) == SeatState.AVAILABLE;
}

test "visitors see four states, each with its own words" {
    assert public_state(SeatState.PAYMENT_PENDING) == "held";
    assert public_state(SeatState.HELD) == "held";
    shown = [public_state(s) for s in SeatState];
    assert sorted(set(shown)) == ["available", "held", "not_for_sale", "sold"];
    texts = [state_text(p) for p in ["available", "held", "not_for_sale", "sold"]];
    assert len(set(texts)) == 4 and all(texts) , texts;
}

test "only available seats can be sold" {
    assert [
        s
        for s in SeatState
        if sellable(s)
    ]
        == [SeatState.AVAILABLE];
}
