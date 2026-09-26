"""P0.3: controllable clock used by expiry logic (holds, tokens, screenings)."""

import os;
import from datetime { datetime, timedelta, timezone }
import from core.clock { now, freeze, advance, reset, ClockControlDisabled }

glob T0: datetime = datetime(2026, 10, 1, 18, 30, tzinfo=timezone.utc);

test "now is timezone-aware UTC" {
    reset();
    assert now().tzinfo is not None;
    assert now().utcoffset() == timedelta(0);
}

test "freeze pins now and advance moves it" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    try {
        freeze(T0);
        assert now() == T0;
        advance(seconds=600);
        assert now() == T0 + timedelta(minutes=10);
    } finally {
        reset();
    }
}

test "reset returns to real time" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    freeze(T0);
    reset();
    assert abs((now() - datetime.now(timezone.utc)).total_seconds()) < 5;
}

test "clock control is refused unless explicitly enabled" {
    os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
    with testraises(ClockControlDisabled) {
        freeze(T0);
    }
    with testraises(ClockControlDisabled) {
        advance(seconds=1);
    }
}
