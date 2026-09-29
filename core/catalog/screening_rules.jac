"""Screening lifecycle and scheduling rules (P3.5a, architecture §120, §121), as pure logic.

DRAFT          being planned; not visible anywhere.
SCHEDULED      confirmed in the programme; still internal.
PUBLISHED      visible on the storefront (3.5b); not on sale yet.
ON_SALE        tickets can be bought.
SALES_CLOSED   no more sales (e.g. shortly before the start); can reopen.
STARTED        the show is running.
COMPLETED      final.
CANCELLED      final; the one exceptional state, from anything that hasn't started.

A screening keeps its screen busy from its start for the movie's running time plus a
cleaning buffer. Intervals are end-exclusive: one screening may start the minute the
previous one's cleaning ends.
"""

import from datetime { datetime, timedelta, timezone }

enum ScreeningState {
    DRAFT = "draft",
    SCHEDULED = "scheduled",
    PUBLISHED = "published",
    ON_SALE = "on_sale",
    SALES_CLOSED = "sales_closed",
    STARTED = "started",
    COMPLETED = "completed",
    CANCELLED = "cancelled"
}

glob CLEANING_BUFFER_MIN: int = 15,
     MAX_DAYS_AHEAD: int = 366,
     ALLOWED: dict[ScreeningState, set[ScreeningState]] = {
         ScreeningState.DRAFT: {ScreeningState.SCHEDULED, ScreeningState.CANCELLED},
         ScreeningState.SCHEDULED: {
             ScreeningState.DRAFT,
             ScreeningState.PUBLISHED,
             ScreeningState.CANCELLED
         },
         ScreeningState.PUBLISHED: {
             ScreeningState.ON_SALE,
             ScreeningState.SCHEDULED,
             ScreeningState.CANCELLED
         },
         ScreeningState.ON_SALE: {
             ScreeningState.SALES_CLOSED,
             ScreeningState.CANCELLED
         },
         ScreeningState.SALES_CLOSED: {
             ScreeningState.ON_SALE,
             ScreeningState.STARTED,
             ScreeningState.CANCELLED
         },
         ScreeningState.STARTED: {ScreeningState.COMPLETED},
         ScreeningState.COMPLETED: set(),
         ScreeningState.CANCELLED: set()
     };

class InvalidTransition(ValueError) {}

class InvalidStart(ValueError) {
    # A start time we won't schedule, with a code and a message the UI can show.
    def init(self: InvalidStart, code: str, message: str) {
        super.init(message);
        self.code = code;
        self.message = message;
    }
}

def transition(current: ScreeningState, target: ScreeningState) -> ScreeningState {
    if target not in ALLOWED[current] {
        raise InvalidTransition(
            f"a screening can't go from {current.value} to {target.value}"
        );
    }
    return target;
}

def occupies_screen(state: ScreeningState) -> bool {
    return state != ScreeningState.CANCELLED;
}

def can_reschedule(state: ScreeningState) -> bool {
    # Only before it's on the storefront: after that, customers may rely on the time.
    return state in (ScreeningState.DRAFT, ScreeningState.SCHEDULED);
}

def ends_at(start: datetime, runtime_minutes: int) -> datetime {
    # When the screen is free again: the movie, then the cleaning buffer.
    return start + timedelta(minutes=runtime_minutes + CLEANING_BUFFER_MIN);
}

def overlaps(
    a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime
) -> bool {
    return a_start < b_end and b_start < a_end;
}

def parse_start(text: str, now: datetime) -> datetime {
    # A start time in ISO 8601 with a time zone (e.g. "2026-10-02T19:30:00+03:00"),
    # returned in UTC. It must be after `now` and at most MAX_DAYS_AHEAD days ahead.
    try {
        parsed = datetime.fromisoformat(text);
    } except ValueError {
        raise InvalidStart(
            "invalid_time", "Enter a date and time, like 2026-10-02T19:30+03:00."
        );
    }
    if parsed.tzinfo is None {
        raise InvalidStart(
            "invalid_time", "Include the time zone, like 2026-10-02T19:30+03:00."
        );
    }
    start = parsed.astimezone(timezone.utc);
    if start <= now {
        raise InvalidStart("in_past", "Choose a start time in the future.");
    }
    if start > now + timedelta(days=MAX_DAYS_AHEAD) {
        raise InvalidStart(
            "invalid_time", f"Schedule screenings at most {MAX_DAYS_AHEAD} days ahead."
        );
    }
    return start;
}
