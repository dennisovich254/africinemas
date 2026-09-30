"""A cinema's theme as data (P3.8a): presets, strict reading, and reported repairs.

A theme travels as Theme.as_dict()'s shape: a name, twenty colour roles for each of light
and dark, a display font, a body font and a radius. parse_theme accepts exactly that and
nothing else (no extra keys, strict #RRGGBB colours, allowlisted fonts and radius), so
only token values can ever be stored or turned into CSS (architecture §55).
repair_reporting makes a theme readable (tokens.repair_theme) and lists what changed.
"""

import from core.theming.tokens {
    DEFAULT_THEME,
    ROLES,
    Theme,
    ThemeTokens,
    InvalidThemeValue,
    repair_theme
}

glob NAME_MAX: int = 40,
     KEYS: list[str] = ["name", "light", "dark", "display_font", "body_font", "radius"],
     MODES: list[str] = ["light", "dark"];

def _tokens(values: dict[str, str], changes: dict[str, str]) -> ThemeTokens {
    merged = dict(values);
    for (role, value) in changes.items() {
        merged[role] = value;
    }
    return ThemeTokens(**merged);
}

def _preset(name: str, light: dict[str, str], dark: dict[str, str]) -> Theme {
    return Theme(
        name=name,
        light=_tokens(DEFAULT_THEME.light.as_dict(), light),
        dark=_tokens(DEFAULT_THEME.dark.as_dict(), dark),
        display_font=DEFAULT_THEME.display_font,
        body_font=DEFAULT_THEME.body_font,
        radius=DEFAULT_THEME.radius
    );
}

# The default and the three dark looks offered alongside Espresso Noir on 2026-09-27
# (docs/IMPLEMENTATION_PLAN.md, theming model). Each passes every contrast rule as it is.
glob PRESETS: list[Theme] = [
         DEFAULT_THEME,
         _preset(
             "Projector Black",
             {},
             {
                 "background": "#0B0B0C",
                 "surface": "#18171A",
                 "raised": "#232126",
                 "border": "#35323A",
                 "field": "#8E8894",
                 "ink": "#F6F4EF",
                 "muted": "#ABA69C",
                 "accent": "#E0A526",
                 "on_accent": "#1A1203",
                 "accent_ink": "#E0A526",
                 "link": "#F0C45A",
                 "danger": "#F87171",
                 "success": "#4ADE80",
                 "warning": "#FBBF24",
                 "focus_ring": "#E0A526",
                 "seat_available": "#8E8894",
                 "seat_selected": "#E0A526",
                 "on_seat_selected": "#1A1203",
                 "seat_held": "#6B6574",
                 "seat_sold": "#2C2A30"
             }
         ),
         _preset(
             "Velvet Curtain",
             {},
             {
                 "background": "#110A0C",
                 "surface": "#1E1115",
                 "raised": "#2A171D",
                 "border": "#45252E",
                 "field": "#A1868B",
                 "ink": "#F8EFEA",
                 "muted": "#C3A9A6",
                 "accent": "#E0A526",
                 "on_accent": "#1A1203",
                 "accent_ink": "#E8B546",
                 "link": "#F0C45A",
                 "danger": "#FF8A8A",
                 "success": "#4ADE80",
                 "warning": "#FBBF24",
                 "focus_ring": "#E0A526",
                 "seat_available": "#A1868B",
                 "seat_selected": "#E0A526",
                 "on_seat_selected": "#1A1203",
                 "seat_held": "#9F445A",
                 "seat_sold": "#3A2027"
             }
         ),
         _preset(
             "Blackout Crimson",
             {
                 "accent": "#E11D48",
                 "on_accent": "#FFFFFF",
                 "accent_ink": "#BE123C",
                 "link": "#BE123C",
                 "focus_ring": "#BE123C",
                 "seat_selected": "#BE123C",
                 "on_seat_selected": "#FFFFFF",
                 "seat_held": "#B4536A"
             },
             {
                 "background": "#0A0A0A",
                 "surface": "#161515",
                 "raised": "#211F1F",
                 "border": "#343131",
                 "field": "#8F8989",
                 "ink": "#F7F5F5",
                 "muted": "#ADA6A6",
                 "accent": "#E11D48",
                 "on_accent": "#FFFFFF",
                 "accent_ink": "#FF5C7A",
                 "link": "#FF8FA3",
                 "danger": "#FF8A8A",
                 "success": "#4ADE80",
                 "warning": "#FBBF24",
                 "focus_ring": "#FF5C7A",
                 "seat_available": "#8F8989",
                 "seat_selected": "#E11D48",
                 "on_seat_selected": "#FFFFFF",
                 "seat_held": "#AB3B53",
                 "seat_sold": "#2B2828"
             }
         )
     ];

def _mode(data: any, mode: str) -> ThemeTokens {  # jac:ignore[W1037]
    if not isinstance(data, dict) or sorted(data.keys()) != sorted(ROLES) {
        raise InvalidThemeValue(f"{mode} needs exactly the colour roles {ROLES}");
    }
    for value in data.values() {
        if not isinstance(value, str) {
            raise InvalidThemeValue(f"not a #RRGGBB colour: {value!r}");
        }
    }
    return ThemeTokens(**data);  # parses each colour strictly
}

def parse_theme(data: any) -> Theme {  # jac:ignore[W1037]
    # The theme in `data`, or InvalidThemeValue for anything but exactly a theme.
    if not isinstance(data, dict) or sorted(data.keys()) != sorted(KEYS) {
        raise InvalidThemeValue(f"a theme has exactly the fields {KEYS}");
    }
    name = data["name"];
    if not isinstance(name, str) {
        raise InvalidThemeValue("the theme's name must be text");
    }
    name = " ".join(name.split());
    if not name or len(name) > NAME_MAX {
        raise InvalidThemeValue(f"name the theme in 1 to {NAME_MAX} characters");
    }
    for key in ["display_font", "body_font", "radius"] {
        if not isinstance(data[key], str) {
            raise InvalidThemeValue(f"{key} must be text");
        }
    }
    return Theme(
        name=name,
        light=_mode(data["light"], "light"),
        dark=_mode(data["dark"], "dark"),
        display_font=data["display_font"],
        body_font=data["body_font"],
        radius=data["radius"]
    );
}

def repair_reporting(theme: Theme) -> tuple[Theme, list[dict[str, str]]] {
    # `theme` made readable, and each colour the repair changed.
    fixed = repair_theme(theme);
    changes: list[dict[str, str]] = [];
    for mode in MODES {
        before = (theme.light if mode == "light" else theme.dark).as_dict();
        after = (fixed.light if mode == "light" else fixed.dark).as_dict();
        for role in ROLES {
            if before[role] != after[role] {
                changes.append(
                    {
                        "mode": mode,
                        "role": role,
                        "before": before[role],
                        "after": after[role]
                    }
                );
            }
        }
    }
    return (fixed, changes);
}
