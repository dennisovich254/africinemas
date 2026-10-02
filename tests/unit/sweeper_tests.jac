"""P4.4: which holds the expiry sweeper acts on (core/booking/sweeper.jac).

Holds lapse by themselves on every read (P4.2); the sweeper only tidies up after them:
it marks a plain hold whose time is up as expired and frees its seats' slots. A hold
that is paying is never touched, however late, and a hold that has ended (released,
replaced or already expired) only leaves the sweeper's list of open holds.
"""

import from datetime { datetime, timedelta, timezone }
import from core.booking.sweeper { due, settled }

glob NOW: datetime = datetime(2026, 10, 3, 18, 0, tzinfo=timezone.utc);

def _at(minutes: int) -> str {
    return (NOW + timedelta(minutes=minutes)).isoformat();
}

test "only a plain hold whose time is up is due" {
    assert due("held", _at(-1), False, NOW);
    assert due("held", _at(0), False, NOW);
    assert due("held", "", False, NOW);
    assert not due("held", _at(5), False, NOW);
    assert not due("released", _at(-1), False, NOW);
    assert not due("expired", _at(-1), False, NOW);
}

test "a paying hold is never due, however late" {
    assert not due("held", _at(-60), True, NOW);
    assert not due("paying", _at(-60), False, NOW);
}

test "ended holds leave the list of open holds; live and paying ones stay" {
    for status in ["released", "replaced", "expired"] {
        assert settled(status) , status;
    }
    for status in ["held", "paying"] {
        assert not settled(status) , status;
    }
}
