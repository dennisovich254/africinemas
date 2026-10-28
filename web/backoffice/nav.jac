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
         # The dashboard (P7.3): owners, managers, finance and auditors.
         ("reports", "Reports", "financial_reports.read"),
         # Staff who set up the cinema's locations (owners, admins), P3.7a.
         ("venues", "Venues", "venues.configure"),
         # Staff who read seat plans (box office, managers, admins); not ushers.
         ("screens", "Screens", "seats.read"),
         # Staff who add films (owners, admins, content managers), P3.7a.
         ("movies", "Movies", "movies.create"),
         ("screenings", "Screenings", "showtimes.create"),
         # The price list is a cinema setting (P3.6, P3.7b).
         ("prices", "Prices", "tenant.settings.update"),
         ("box-office", "Box office", "bookings.create"),
         # The snack catalog (P12): managers build it; the box office reads it here.
         ("snacks", "Snacks & glasses", "concessions.read"),
         ("scanner", "Scanner", "tickets.scan"),
         # Handing over snacks bought with tickets, by their pickup code (P12.9).
         ("snack-counter", "Snack counter", "concessions.collect"),
         ("staff", "Staff", "employees.read"),
         # Who changed what (P7.2, P7.3): owners and auditors.
         ("audit", "Audit log", "audit.read"),
         # Verifying the owner and the business (P14.4): the owner alone.
         ("verification", "Verification", "tenant.verification"),
         # Reading and accepting the cinema agreement (P15.1): the owner alone.
         ("agreement", "Cinema agreement", "tenant.verification"),
         # AfriCinemas' monthly statements and invoices (P15.4): who reads the reports.
         ("billing", "Billing", "financial_reports.read"),
         ("settings", "Settings", "tenant.settings.update"),
         # Asking AfriCinemas for technical help (P13.5a).
         ("help", "Help", "support.request"),
         # Everyone's own name and password (P12.15).
         ("profile", "Your profile", "")
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
