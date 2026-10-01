"""P4.1: the storefront shows a showtime only until it starts; P4.1b: "today" is the
cinema's day, in its own time zone."""

import from datetime { datetime, timezone }
import from core.catalog.models { StorefrontScreening }
import from core.catalog.storefront { not_started, on_day, by_cinema_day }

def _entry(screening_id: str, starts_at: str) -> StorefrontScreening {
    return StorefrontScreening(
        screening_id=screening_id,
        starts_at=starts_at,
        ends_at=starts_at,
        state="published"
    );
}

test "showtimes that have started drop off, and the rest come earliest first" {
    entries = [
        _entry("late", "2026-10-03T21:00:00+00:00"),
        _entry("started", "2026-10-03T18:00:00+00:00"),
        _entry("now", "2026-10-03T19:00:00+00:00"),
        _entry("soon", "2026-10-03T19:01:00+00:00")
    ];
    at = datetime(2026, 10, 3, 19, 0, tzinfo=timezone.utc);
    assert [e.screening_id for e in not_started(entries, at)] == ["soon", "late"];
    assert not_started([], at) == [];
}

test "today's showtimes are those on the cinema's calendar day, in its time zone" {
    entries = [
        # 23:30 in Nairobi on the 2nd: the day before, there.
        _entry("eve", "2026-10-02T20:30:00+00:00"),
        # 00:30 in Nairobi on the 3rd, though still the 2nd in UTC.
        _entry("midnight", "2026-10-02T21:30:00+00:00"),
        _entry("evening", "2026-10-03T15:00:00+00:00"),
        # 00:30 on the 4th in Nairobi.
        _entry("next", "2026-10-03T21:30:00+00:00")
    ];
    at = datetime(2026, 10, 3, 9, 0, tzinfo=timezone.utc);
    assert [e.screening_id for e in on_day(entries, at, "Africa/Nairobi")]
        == ["midnight", "evening"];
    assert [e.screening_id for e in on_day(entries, at, "UTC")] == ["evening", "next"];
}

test "showtimes group by the cinema's calendar day, for the next seven days" {
    entries = [
        _entry("a", "2026-10-03T15:00:00+00:00"),
        _entry("b", "2026-10-03T21:30:00+00:00"),  # 00:30 on the 4th in Nairobi
        _entry("c", "2026-10-04T18:00:00+00:00"),
        _entry("d", "2026-10-09T18:00:00+00:00"),  # day 7 of the week
        _entry("e", "2026-10-10T18:00:00+00:00")  # the following week
    ];
    at = datetime(2026, 10, 3, 9, 0, tzinfo=timezone.utc);
    days = by_cinema_day(entries, at, "Africa/Nairobi", 7);
    assert [(d, [e.screening_id for e in group]) for (d, group) in days]
        == [("2026-10-03", ["a"]), ("2026-10-04", ["b", "c"]), ("2026-10-09", ["d"])];
    assert by_cinema_day([], at, "Africa/Nairobi", 7) == [];
}
