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

def:pub cinema_today(tz: str) -> str {
    # Today's date where the cinema is, as "2026-10-03".
    return new(Date).toLocaleDateString("en-CA", {"timeZone": tz});  # jac:ignore[W2001]
}

def:pub date_label(date: str, today: str) -> str {
    # "Today", "Tomorrow" or "Sat 4 Oct" for a cinema date ("2026-10-04").
    if date == today {
        return "Today";
    }
    noon_utc: any = new(Date, f"{date}T12:00:00Z");  # jac:ignore[W1037,W2001]
    next_day: any = new(Date, f"{today}T12:00:00Z");  # jac:ignore[W1037,W2001]
    next_day.setUTCDate(next_day.getUTCDate() + 1);
    if noon_utc.getTime() == next_day.getTime() {
        return "Tomorrow";
    }
    return noon_utc.toLocaleDateString(
        [], {"weekday": "short", "day": "numeric", "month": "short", "timeZone": "UTC"}
    );
}

def:pub by_movie(showtimes: list[dict[str, any]]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # One day's showtimes grouped by movie, in order of each movie's first showtime:
    # [{"movie_key", "title", "has_poster", "showtimes": [...]}].
    groups: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in showtimes {
        found: dict[str, any] | None = None;  # jac:ignore[W1037]
        for g in groups {
            if g["movie_key"] == s["movie_key"] {
                found = g;
            }
        }
        if found is None {
            groups.append(
                {
                    "movie_key": s["movie_key"],
                    "title": s["title"],
                    "has_poster": s["has_poster"],
                    "genres": s.get("genres") or [],
                    "age_rating": s.get("age_rating") or "",
                    "runtime_minutes": s.get("runtime_minutes") or 0,
                    "showtimes": [s]
                }
            );
        } else {
            found["showtimes"].append(s);
        }
    }
    return groups;
}

def:pub release_label(date: str) -> str {
    # "Opens Fri 18 Dec 2026" for a release date ("2026-12-18").
    noon_utc: any = new(Date, f"{date}T12:00:00Z");  # jac:ignore[W1037,W2001]
    nice: str = noon_utc.toLocaleDateString(
        [],
        {
            "weekday": "short",
            "day": "numeric",
            "month": "short",
            "year": "numeric",
            "timeZone": "UTC"
        }
    );
    return f"Opens {nice}";
}

def:pub sorted_unique(items: list[str]) -> list[str] {
    # Each item once, A to Z (for filter options).
    found: list[str] = [];
    for item in items {
        if item and item not in found {
            found.append(item);
        }
    }
    return sorted(found, key=lambda (t: str) -> str { return t.lower(); });
}

def:pub cinema_date(starts_at: str, tz: str) -> str {
    # A showtime's calendar day where the cinema is, as "2026-10-03".
    return _date(starts_at).toLocaleDateString("en-CA", {"timeZone": tz});
}

def:pub listed(item: str, items: list[str] | None) -> bool {
    # Whether `item` is one of `items`. Typed, so it compiles to a value check: `in` on
    # an untyped value became JavaScript's `in`, which tests an array's indexes (JI-035).
    found: list[str] = items or [];
    return item in found;
}
