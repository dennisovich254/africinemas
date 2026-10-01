"""How the storefront words a movie's details and its showtimes (P4.1).

Times are shown in the cinema's time zone (from its price list), whatever the visitor's
device is set to: a showtime is at 18:15 in the cinema, not 15:15 on a phone set to UTC.
"""

def _date(starts_at: str) -> any {  # jac:ignore[W1037]
    return new(Date, starts_at);  # jac:ignore[W2001]
}

def:pub time_label(starts_at: str, tz: str) -> str {
    # "18:15".
    return _date(starts_at).toLocaleTimeString(
        [], {"hour": "2-digit", "minute": "2-digit", "hour12": False, "timeZone": tz}
    );
}

def:pub day_label(starts_at: str, tz: str) -> str {
    # "Fri 3 Oct".
    return _date(starts_at).toLocaleDateString(
        [], {"weekday": "short", "day": "numeric", "month": "short", "timeZone": tz}
    );
}

def:pub long_day_label(starts_at: str, tz: str) -> str {
    # "Friday 3 October".
    return _date(starts_at).toLocaleDateString(
        [], {"weekday": "long", "day": "numeric", "month": "long", "timeZone": tz}
    );
}

def:pub runtime_label(minutes: int) -> str {
    # "1 h 23 min", "45 min", or "" when unknown.
    if minutes <= 0 {
        return "";
    }
    hours = int(minutes / 60);
    rest = minutes - hours * 60;
    if hours == 0 {
        return f"{rest} min";
    }
    return f"{hours} h {rest} min" if rest else f"{hours} h";
}

def:pub details_line(movie: dict[str, any]) -> str {  # jac:ignore[W1037]
    # "16 · 1 h 23 min · Drama", leaving out what the cinema hasn't filled in.
    parts: list[str] = [];
    if movie["age_rating"] {
        parts.append(movie["age_rating"]);
    }
    runtime = runtime_label(movie["runtime_minutes"] or 0);
    if runtime {
        parts.append(runtime);
    }
    genres: list[str] = movie["genres"] or [];
    if len(genres) > 0 {
        parts.append(", ".join(genres));
    }
    return " · ".join(parts);
}

def:pub where_label(showtime: dict[str, any]) -> str {  # jac:ignore[W1037]
    # "Westgate · Screen 1".
    venue: str = showtime["venue"]["name"] or "";
    screen: str = showtime["screen"]["name"] or "";
    return f"{venue} · {screen}" if venue and screen else venue or screen;
}

def:pub by_day(
    showtimes: list[dict[str, any]],  # jac:ignore[W1037]
    tz: str
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Showtimes (earliest first) grouped by the cinema's calendar day:
    # [{"day": "Friday 3 October", "showtimes": [...]}].
    groups: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in showtimes {
        day = long_day_label(s["starts_at"], tz);
        if len(groups) == 0 or groups[len(groups) - 1]["day"] != day {
            groups.append({"day": day, "showtimes": []});
        }
        groups[len(groups) - 1]["showtimes"].append(s);
    }
    return groups;
}
