"""P3.5a: the screening lifecycle and scheduling rules (pure logic, core/catalog/screening_rules.jac).

Architecture §121 lifecycle, with CANCELLED as the exceptional state; §120 no overlapping
screenings on one screen. A screening occupies its screen for the movie's running time
plus a cleaning buffer; intervals are end-exclusive, so back-to-back screenings fit.
"""

import from datetime { datetime, timedelta, timezone }
import from core.catalog.screening_rules {
    ScreeningState,
    InvalidTransition,
    InvalidStart,
    CLEANING_BUFFER_MIN,
    transition,
    occupies_screen,
    can_reschedule,
    ends_at,
    overlaps,
    parse_start
}

glob NOW: datetime = datetime(2026, 10, 1, 12, 0, tzinfo=timezone.utc);

def _at(hour: int, minute: int = 0) -> datetime {
    return datetime(2026, 10, 2, hour, minute, tzinfo=timezone.utc);
}

test "the lifecycle moves forward one step at a time, as the architecture lays out" {
    path = [
        ScreeningState.DRAFT,
        ScreeningState.SCHEDULED,
        ScreeningState.PUBLISHED,
        ScreeningState.ON_SALE,
        ScreeningState.SALES_CLOSED,
        ScreeningState.STARTED,
        ScreeningState.COMPLETED
    ];
    state: ScreeningState = path[0];
    for target in path[1:] {
        state = transition(state, target);
        assert state == target;
    }
}

test "the allowed step backs: unschedule, unpublish, reopen sales" {
    assert transition(ScreeningState.SCHEDULED, ScreeningState.DRAFT)
        == ScreeningState.DRAFT;
    assert transition(ScreeningState.PUBLISHED, ScreeningState.SCHEDULED)
        == ScreeningState.SCHEDULED;
    assert transition(ScreeningState.SALES_CLOSED, ScreeningState.ON_SALE)
        == ScreeningState.ON_SALE;
}

test "any screening that hasn't started can be cancelled; nothing leaves a final state" {
    for state in [
        ScreeningState.DRAFT,
        ScreeningState.SCHEDULED,
        ScreeningState.PUBLISHED,
        ScreeningState.ON_SALE,
        ScreeningState.SALES_CLOSED
    ] {
        assert transition(state, ScreeningState.CANCELLED) == ScreeningState.CANCELLED;
    }
    for (current, target) in [
        (ScreeningState.STARTED, ScreeningState.CANCELLED),
        (ScreeningState.COMPLETED, ScreeningState.ON_SALE),
        (ScreeningState.CANCELLED, ScreeningState.SCHEDULED),
        (ScreeningState.DRAFT, ScreeningState.ON_SALE),
        (ScreeningState.DRAFT, ScreeningState.PUBLISHED),
        (ScreeningState.ON_SALE, ScreeningState.COMPLETED),
        (ScreeningState.PUBLISHED, ScreeningState.PUBLISHED)
    ] {
        try {
            transition(current, target);
            assert False , f"{current.value} -> {target.value} was allowed";
        } except InvalidTransition {}
    }
}

test "every state but cancelled keeps the screen busy; only unpublished ones can move" {
    assert [
        s.value
        for s in ScreeningState
        if not occupies_screen(s)
    ]
        == ["cancelled"];
    assert [
        s.value
        for s in ScreeningState
        if can_reschedule(s)
    ]
        == ["draft", "scheduled"];
}

test "a screening ends after the running time plus the cleaning buffer" {
    assert CLEANING_BUFFER_MIN == 15;
    assert ends_at(_at(18), 100) == _at(19, 55);
}

test "overlap is end-exclusive: back to back fits, a minute's overlap doesn't" {
    first = (_at(18), _at(20));
    assert not overlaps(first[0], first[1], _at(20), _at(22)) , "back to back";
    assert not overlaps(first[0], first[1], _at(16), _at(18)) , "just before";
    assert overlaps(first[0], first[1], _at(19, 59), _at(22));
    assert overlaps(first[0], first[1], _at(17), _at(18, 1));
    assert overlaps(first[0], first[1], _at(18, 30), _at(19)) , "inside";
    assert overlaps(first[0], first[1], _at(17), _at(21)) , "around";
}

test "a start time needs a time zone, is stored in UTC, and must be ahead but within a year" {
    got = parse_start("2026-10-02T19:30:00+03:00", NOW);
    assert got == datetime(2026, 10, 2, 16, 30, tzinfo=timezone.utc) , got;
    assert got.tzinfo == timezone.utc;
    for (text, reason) in [
        ("2026-10-02T19:30:00", "invalid_time"),
        ("tomorrow at 7", "invalid_time"),
        ("", "invalid_time"),
        ("2026-10-01T11:00:00+00:00", "in_past"),
        ("2026-10-01T12:00:00+00:00", "in_past"),
        ((NOW + timedelta(days=367)).isoformat(), "invalid_time")
    ] {
        try {
            parse_start(text, NOW);
            assert False , f"{text!r} was accepted";
        } except InvalidStart as e {
            assert e.code == reason , f"{text!r}: {e.code}";
        }
    }
    assert parse_start((NOW + timedelta(days=366)).isoformat(), NOW) , "a year ahead is fine";
}
