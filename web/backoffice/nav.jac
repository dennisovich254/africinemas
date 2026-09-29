"""The back-office sections and who sees them (P2.7b).

A section is listed when the member holds the permission that section is for (from
`my_access.permissions`). The nav is a convenience, not a security boundary: every
endpoint authorizes on the server (ADR-0008). Sections key on the permission to *work*
there, not merely read, so an usher (who can read showtimes to check tickets) sees the
scanner and not the screenings setup.
"""

glob SUFFIX: str = ".africinemas.co.ke",
     SLUG_CHARS: str = "abcdefghijklmnopqrstuvwxyz0123456789",
     # (key, label, permission). The empty key is the overview, which everyone sees.
     SECTIONS: list[tuple[str, str, str]] = [
         ("", "Overview", ""),
         ("screenings", "Screenings", "showtimes.create"),
         ("box-office", "Box office", "bookings.create"),
         ("scanner", "Scanner", "tickets.scan"),
         ("staff", "Staff", "employees.read"),
         ("settings", "Settings", "tenant.settings.update")
     ];

def:pub web_address(slug: str) -> str {
    # Where the cinema's storefront lives.
    return slug + SUFFIX;
}

def:pub section_path(slug: str, key: str) -> str {
    return f"/app/{slug}/{key}" if key else f"/app/{slug}";
}

def:pub nav_for(slug: str, permissions: list[str]) -> list[dict[str, str]] {
    return [
        {"label": label, "to": section_path(slug, key), "key": key}
        for (key, label, needs) in SECTIONS
        if not needs or needs in permissions
    ];
}

def:pub section_label(key: str) -> str {
    for (k, label, _) in SECTIONS {
        if k == key {
            return label;
        }
    }
    return "";
}

def:pub role_label(role_key: str) -> str {
    # "box_office_agent@venue-1" -> "Box office agent (venue-1)".
    parts = role_key.split("@");
    name = parts[0].replace("_", " ");
    name = name[:1].upper() + name[1:];
    return f"{name} ({parts[1]})" if len(parts) > 1 else name;
}

def:pub suggest_slug(name: str) -> str {
    # A starting point for the web address, from the cinema's name; the server's
    # check_slug has the final word.
    out = "";
    for ch in name.lower() {
        if ch in SLUG_CHARS {
            out += ch;
        } elif out and not out.endswith("-") {
            out += "-";
        }
    }
    return out.strip("-")[:40].strip("-");
}
