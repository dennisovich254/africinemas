"""What the Branding page shows and checks, as pure functions (P3.8b).

The server has the final word on every theme (core/theming/branding.jac): these only
label the colour roles for people, keep a malformed hex out of the preview, and say
whether the draft differs from what was last saved.
"""

glob ROLE_LABELS: dict[str, str] = {
         "background": "Page background",
         "surface": "Cards",
         "raised": "Raised panels",
         "border": "Borders",
         "field": "Form field outlines",
         "ink": "Text",
         "muted": "Secondary text",
         "accent": "Accent",
         "on_accent": "Text on accent",
         "accent_ink": "Accent text",
         "link": "Links",
         "danger": "Errors",
         "success": "Success",
         "warning": "Warnings",
         "focus_ring": "Focus ring",
         "seat_available": "Available seats",
         "seat_selected": "Selected seats",
         "on_seat_selected": "Text on selected seats",
         "seat_held": "Held seats",
         "seat_sold": "Sold seats"
     },
     # The colours most cinemas change; the rest sit under "More colours".
     KEY_ROLES: list[str] = [
         "accent",
         "on_accent",
         "background",
         "surface",
         "ink",
         "muted"
     ],
     HEX_CHARS: str = "0123456789abcdefABCDEF",
     RADIUS_LABELS: dict[str, str] = {
         "none": "Square",
         "small": "Slightly rounded",
         "medium": "Rounded",
         "large": "Very rounded"
     };

def:pub role_label(role: str) -> str {
    return ROLE_LABELS[role] if role in ROLE_LABELS else role;
}

def:pub radius_label(radius: str) -> str {
    return RADIUS_LABELS[radius] if radius in RADIUS_LABELS else radius;
}

def:pub key_roles -> list[str] {
    return KEY_ROLES;
}

def:pub other_roles(roles: list[str]) -> list[str] {
    return [
        r
        for r in roles
        if r not in KEY_ROLES
    ];
}

def:pub is_hex(value: str) -> bool {
    # "#RRGGBB", as the server requires.
    if len(value) != 7 or value[0] != "#" {
        return False;
    }
    for ch in value[1:] {
        if ch not in HEX_CHARS {
            return False;
        }
    }
    return True;
}

def:pub with_colour(
    theme: dict[str, any],  # jac:ignore[W1037]
    mode: str,
    role: str,
    value: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # A copy of `theme` with one colour changed.
    tokens: dict[str, str] = {};
    for key in theme[mode] {
        tokens[key] = theme[mode][key];
    }
    tokens[role] = value.upper();
    changed: dict[str, any] = {};  # jac:ignore[W1037]
    for key in theme {
        changed[key] = theme[key];
    }
    changed[mode] = tokens;
    return changed;
}

def:pub with_field(theme: dict[str, any], field: str, value: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A copy of `theme` with its name, a font or the radius changed.
    changed: dict[str, any] = {};  # jac:ignore[W1037]
    for key in theme {
        changed[key] = theme[key];
    }
    changed[field] = value;
    return changed;
}

def:pub same_theme(a: dict[str, any], b: dict[str, any]) -> bool {  # jac:ignore[W1037]
    # Field by field: the server may return a theme's keys in another order.
    if a is None or b is None {
        return a is b;
    }
    for key in ["name", "display_font", "body_font", "radius"] {
        if a[key] != b[key] {
            return False;
        }
    }
    for mode in ["light", "dark"] {
        for role in ROLE_LABELS {
            if a[mode][role] != b[mode][role] {
                return False;
            }
        }
    }
    return True;
}

def:pub adjusted_text(change: dict[str, str]) -> str {
    # "Text (light) was #F5F2EA; it's now #5E5A78, so it stays readable."
    return f"{role_label(change['role'])} ({change['mode']}) was {change[
        'before'
    ]}; it's now {change['after']}, so it stays readable.";
}

def:pub version_label(version: dict[str, any]) -> str {  # jac:ignore[W1037]
    return f"Version {version['version']} · {version['name']}";
}
