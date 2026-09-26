"""Controllable UTC clock for all domain time logic (holds, tokens, screenings).

Domain code must call `now()` instead of `datetime.now()`, so tests can freeze
and advance time. Control functions refuse to run unless the environment sets
AFRICINEMAS_CLOCK_CONTROL=1, which production never does.
"""

import os;
import from datetime { datetime, timedelta, timezone }

glob CONTROL_ENV: str = "AFRICINEMAS_CLOCK_CONTROL";

glob _frozen_at: datetime | None = None,
     _offset: timedelta = timedelta(0);

class ClockControlDisabled(RuntimeError) {}

def _require_control {
    if os.environ.get(CONTROL_ENV) != "1" {
        raise ClockControlDisabled(
            f"clock control is disabled; set {CONTROL_ENV}=1 (tests only)"
        );
    }
}

def now -> datetime {
    base = _frozen_at if _frozen_at is not None else datetime.now(timezone.utc);
    return base + _offset;
}

def freeze(at: datetime) {
    _require_control();
    if at.tzinfo is None {
        raise ValueError("freeze() needs a timezone-aware datetime");
    }
    _frozen_at = at.astimezone(timezone.utc);
    _offset = timedelta(0);
}

def advance(seconds: float) {
    _require_control();
    _offset = _offset + timedelta(seconds=seconds);
}

def reset {
    _frozen_at = None;
    _offset = timedelta(0);
}
