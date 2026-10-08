"""How the dashboard words and sizes the sales report (P7.3).

Dates are the cinema's local days ("2026-10-05"), as the report uses them; they're
shown as "Mon 5 Oct", read as UTC so the device's time zone never shifts a day. Money
is in cents.
"""

import from ..storefront.checkout_rules { money }

glob:pub PRESETS: list[tuple[str, str]] = [
         ("today", "Today"),
         ("last7", "Last 7 days"),
         ("last30", "Last 30 days"),
         ("next7", "Next 7 days"),
         ("custom", "Custom")
     ];

def _day(day: str) -> any {  # jac:ignore[W1037]
    return new(Date, day + "T00:00:00Z");  # jac:ignore[W2001]
}

def:pub shifted(day: str, days: int) -> str {
    # The day `days` after `day` (before, when negative): "2026-10-05", 2 -> "2026-10-07".
    moved = _day(day);
    moved.setUTCDate(moved.getUTCDate() + days);
    stamp: str = moved.toISOString();
    return stamp[0:10];
}

def:pub preset_range(preset: str, today: str) -> list[str] {
    # [first, last] of a preset, around the cinema's today.
    if preset == "last7" {
        return [shifted(today, -6), today];
    }
    if preset == "last30" {
        return [shifted(today, -29), today];
    }
    if preset == "next7" {
        return [today, shifted(today, 6)];
    }
    return [today, today];
}

def:pub day_label(day: str) -> str {
    # "2026-10-05" -> "Mon 5 Oct".
    return _day(day).toLocaleDateString(
        "en-GB",
        {"weekday": "short", "day": "numeric", "month": "short", "timeZone": "UTC"}
    );
}

def:pub point_label(start: str, unit: str) -> str {
    # A chart point's name: its day, or "Week of Mon 5 Oct".
    return f"Week of {day_label(start)}" if unit == "week" else day_label(start);
}

def:pub period_label(first: str, last: str) -> str {
    return day_label(first)
        if first == last
        else f"{day_label(first)} to {day_label(last)}";
}

def _one_decimal(value: float) -> str {
    # 25 -> "25.0", 18.18 -> "18.2" (whole tenths, as money() does cents).
    tenths = int(value * 10 + 0.5);
    return f"{int(tenths / 10)}.{tenths % 10}";
}

def:pub percent(value: float) -> str {
    # 25 -> "25.0%".
    return _one_decimal(value) + "%";
}

def:pub compact_money(cents: int, currency: str) -> str {
    # Axis labels: "KES 0", "KES 950", "KES 12k", "KES 1.5M".
    units = int(cents / 100);
    if units >= 1000000 {
        return f"{currency} {_one_decimal(units / 1000000)}M";
    }
    if units >= 1000 {
        return f"{currency} {int(units / 1000 + 0.5)}k";
    }
    return f"{currency} {units}";
}

def:pub nice_max(value: int) -> int {
    # The chart's top: `value` rounded up to 1, 2 or 5 times a power of ten (at least 1).
    if value <= 0 {
        return 1;
    }
    step = 1;
    while step * 10 <= value {
        step = step * 10;
    }
    for m in [1, 2, 5, 10] {
        if value <= m * step {
            return m * step;
        }
    }
    return 10 * step;
}

def:pub money_label(cents: int, currency: str) -> str {
    return money(cents, currency);
}

def:pub result_label(result: str) -> str {
    # An audit event's result in words (never a colour alone).
    if result == "ok" {
        return "Done";
    }
    if result == "pending" {
        return "Not finished";
    }
    if result == "forbidden" {
        return "Refused: not allowed";
    }
    if result == "not_found" {
        return "Refused: not found";
    }
    if result == "no_shift" {
        return "Refused: no shift open";
    }
    return "Refused: " + " ".join(result.split("_"));
}

# The audited actions (tests/isolation/registry.jac) as people say them, for the audit
# log's filter and rows; an action missing here shows as its code.
glob:pub ACTIONS: list[tuple[str, str]] = [
         ("sale.cash", "Cash sale"),
         ("sale.mpesa_started", "M-Pesa sale started"),
         ("ticket.scanned", "Ticket scanned"),
         ("shift.started", "Shift started"),
         ("shift.ended", "Shift ended"),
         ("staff.invited", "Staff invited"),
         ("staff.joined", "Staff joined"),
         ("staff.roles_changed", "Staff roles changed"),
         ("staff.status_changed", "Staff enabled or disabled"),
         ("staff.removed", "Staff removed"),
         ("cinema.created", "Cinema created"),
         ("cinema.renamed", "Cinema renamed"),
         ("prices.saved", "Prices saved"),
         ("venue.created", "Venue added"),
         ("venue.updated", "Venue changed"),
         ("venue.deleted", "Venue deleted"),
         ("screen.created", "Screen added"),
         ("screen.renamed", "Screen renamed"),
         ("screen.deleted", "Screen deleted"),
         ("layout.saved", "Seat layout saved"),
         ("layout.published", "Seat layout published"),
         ("movie.created", "Movie added"),
         ("movie.updated", "Movie changed"),
         ("movie.deleted", "Movie deleted"),
         ("movie.poster_uploaded", "Poster uploaded"),
         ("movie.backdrop_uploaded", "Backdrop uploaded"),
         ("movie.backdrop_removed", "Backdrop removed"),
         ("showtime.created", "Showtime added"),
         ("showtime.rescheduled", "Showtime moved"),
         ("showtime.scheduled", "Showtime scheduled"),
         ("showtime.published", "Showtime published"),
         ("showtime.unpublished", "Showtime unpublished"),
         ("showtime.cancelled", "Showtime cancelled"),
         ("theme.saved", "Theme saved"),
         ("theme.published", "Theme published"),
         ("theme.rolled_back", "Theme rolled back"),
         ("theme.logo_uploaded", "Logo uploaded"),
         ("theme.logo_removed", "Logo removed"),
         ("home_page.saved", "Home page saved"),
         ("home_page.published", "Home page published"),
         ("home_page.rolled_back", "Home page rolled back"),
         ("home_page.photo_uploaded", "Home page photo uploaded"),
         ("home_page.photo_removed", "Home page photo removed")
     ];

def:pub action_label(action: str) -> str {
    for (code, label) in ACTIONS {
        if code == action {
            return label;
        }
    }
    return action;
}

def:pub resource_label(kind: str) -> str {
    # "home_page" -> "Home page".
    words = " ".join(kind.split("_"));
    return words[:1].upper() + words[1:];
}
