"""P4.1: the storefront shows a showtime only until it starts."""

import from datetime { datetime, timezone }
import from core.catalog.models { StorefrontScreening }
import from core.catalog.storefront { not_started }

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
