"""Seats kept for the counter (owner, 2026-10-30).

A cinema that already sells at its counter, on paper, keeps some seats for it; online
customers can't book those, so the two never sell the same seat. Chosen once per screen
(Auditorium.counter_seats), changeable for one showtime (Screening.counter_add and
counter_free). Until the cinema's release time before the showtime
(Tenant.counter_release_hours, 2 hours unless changed), they're **kept**: online holds
refuse them (hold_api), and the storefront shows them as sold at the box office. The
Box office sells them as any other. After the release time, unsold ones are for anyone,
except seats staff keep for the counter after it (Screening.counter_late), which stay
kept until the showtime starts.
"""

import from datetime { datetime, timedelta }
import from core.tenancy.models { Tenant }
import from core.catalog.models { Auditorium, Screening }
import from core.catalog.venues { find_auditorium }

def counter_labels(screen: Auditorium | None, screening: Screening) -> list[str] {
    # The showtime's counter seats: the screen's, with this showtime's changes.
    base = list(screen.counter_seats) if screen is not None else [];
    found = [
        l
        for l in base + list(screening.counter_add)
        if l not in screening.counter_free
    ];
    return sorted(set(found));
}

def released_at(cinema: Tenant, screening: Screening) -> datetime {
    # When the showtime's counter seats go on sale online.
    return datetime.fromisoformat(screening.starts_at)
        - timedelta(hours=max(0, cinema.counter_release_hours));
}

def is_released(cinema: Tenant, screening: Screening, at: datetime) -> bool {
    return at >= released_at(cinema, screening);
}

def kept_for_counter(cinema: Tenant, screening: Screening, at: datetime) -> list[str] {
    # The seats online customers can't book right now: once released, only those kept
    # after the release time.
    if is_released(cinema, screening, at) {
        return sorted(set(screening.counter_late));
    }
    return counter_labels(find_auditorium(cinema, screening.auditorium_id), screening);
}
