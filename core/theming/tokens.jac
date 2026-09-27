"""Tenant theme model: typed colour tokens, strict parsing, WCAG AA validation and repair.

A theme is data, never code. Colours are strict #RRGGBB values, fonts and radius come
from allowlists, and every colour pair a component draws must meet WCAG AA contrast in
both light and dark mode (docs/IMPLEMENTATION_PLAN.md, P0.8a). Tenants and AI only ever
produce values of these types; `repair_theme` makes any proposal readable.
"""

import re;
import from colorsys { hls_to_rgb, rgb_to_hls }

glob HEX_PATTERN: str = r"^#[0-9A-Fa-f]{6}$",
     ROLES: list[str] = [
         "background",
         "surface",
         "raised",
         "border",
         "field",
         "ink",
         "muted",
         "accent",
         "on_accent",
         "accent_ink",
         "link",
         "danger",
         "success",
         "warning",
         "focus_ring",
         "seat_available",
         "seat_selected",
         "on_seat_selected",
         "seat_held",
         "seat_sold"
     ],
     DISPLAY_FONTS: list[str] = [
         "Bebas Neue",
         "Outfit",
         "Inter",
         "DM Sans",
         "Raleway",
         "Figtree"
     ],
     BODY_FONTS: list[str] = [
         "Outfit",
         "Inter",
         "DM Sans",
         "Figtree",
         "Noto Sans",
         "Public Sans",
         "Roboto"
     ],
     RADII: list[str] = ["none", "small", "medium", "large"],
     TEXT: float = 4.5,
     UI: float = 3.0;

# (foreground role, background role, minimum ratio). Text pairs need 4.5:1 and
# non-text UI pairs (borders, focus rings, seat shapes) need 3:1 (WCAG 1.4.3 / 1.4.11).
glob RULES: list[tuple[str, str, float]] = [
         ("ink", "background", TEXT),
         ("ink", "surface", TEXT),
         ("ink", "raised", TEXT),
         ("muted", "background", TEXT),
         ("muted", "surface", TEXT),
         ("muted", "raised", TEXT),
         ("muted", "seat_sold", TEXT),
         ("on_accent", "accent", TEXT),
         ("accent_ink", "background", TEXT),
         ("accent_ink", "surface", TEXT),
         ("link", "background", TEXT),
         ("link", "surface", TEXT),
         ("danger", "background", TEXT),
         ("danger", "surface", TEXT),
         ("success", "background", TEXT),
         ("success", "surface", TEXT),
         ("warning", "background", TEXT),
         ("warning", "surface", TEXT),
         ("on_seat_selected", "seat_selected", TEXT),
         ("field", "surface", UI),
         ("focus_ring", "background", UI),
         ("focus_ring", "surface", UI),
         ("seat_available", "background", UI),
         ("seat_available", "surface", UI),
         ("seat_selected", "background", UI),
         ("seat_selected", "surface", UI),
         ("seat_held", "background", UI),
         ("seat_held", "surface", UI)
     ],
     # Fills that must sit on the same side (dark/light) as the page background, so one
     # text colour can be readable on all of them.
     CANVAS_ROLES: list[str] = ["surface", "raised", "seat_sold"];

class InvalidThemeValue(ValueError) {}

def parse_hex(value: str) -> str {
    if not isinstance(value, str) or re.fullmatch(HEX_PATTERN, value) is None {
        raise InvalidThemeValue(f"not a #RRGGBB colour: {value!r}");
    }
    return value.upper();
}

obj ThemeTokens {
    has background: str,
        surface: str,
        raised: str,
        border: str,
        field: str,
        ink: str,
        muted: str,
        accent: str,
        on_accent: str,
        accent_ink: str,
        link: str,
        danger: str,
        success: str,
        warning: str,
        focus_ring: str,
        seat_available: str,
        seat_selected: str,
        on_seat_selected: str,
        seat_held: str,
        seat_sold: str;

    def postinit {
        for role in ROLES {
            setattr(self, role, parse_hex(getattr(self, role)));
        }
    }

    def as_dict -> dict[str, str] {
        return {role: getattr(self, role) for role in ROLES};
    }
}

obj Theme {
    has name: str,
        light: ThemeTokens,
        dark: ThemeTokens,
        display_font: str,
        body_font: str,
        radius: str;

    def postinit {
        if self.display_font not in DISPLAY_FONTS {
            raise InvalidThemeValue(f"display font not allowed: {self.display_font!r}");
        }
        if self.body_font not in BODY_FONTS {
            raise InvalidThemeValue(f"body font not allowed: {self.body_font!r}");
        }
        if self.radius not in RADII {
            raise InvalidThemeValue(f"radius not allowed: {self.radius!r}");
        }
    }

    # `obj` equality is identity-based (docs/jac-issues/JI-016): compare themes by this view.
    def as_dict -> dict[str, str | dict[str, str]] {
        return {
            "name": self.name,
            "light": self.light.as_dict(),
            "dark": self.dark.as_dict(),
            "display_font": self.display_font,
            "body_font": self.body_font,
            "radius": self.radius
        };
    }
}

obj ContrastIssue {
    has mode: str,
        fg_role: str,
        bg_role: str,
        ratio: float,
        required: float;
}

def _channels(hex_color: str) -> tuple[float, float, float] {
    return (
        int(hex_color[1:3], 16) / 255,
        int(hex_color[3:5], 16) / 255,
        int(hex_color[5:7], 16) / 255
    );
}

def _linear(c: float) -> float {
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4;
}

def relative_luminance(hex_color: str) -> float {
    (r, g, b) = _channels(parse_hex(hex_color));
    return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b);
}

def contrast_ratio(fg: str, bg: str) -> float {
    a = relative_luminance(fg);
    b = relative_luminance(bg);
    return (max(a, b) + 0.05) / (min(a, b) + 0.05);
}

def validate_tokens(tokens: ThemeTokens, mode: str) -> list[ContrastIssue] {
    values = tokens.as_dict();
    issues: list[ContrastIssue] = [];
    for (fg, bg, required) in RULES {
        ratio = contrast_ratio(values[fg], values[bg]);
        if ratio < required {
            issues.append(
                ContrastIssue(
                    mode=mode, fg_role=fg, bg_role=bg, ratio=ratio, required=required
                )
            );
        }
    }
    return issues;
}

def validate_theme(theme: Theme) -> list[ContrastIssue] {
    return validate_tokens(theme.light, "light") + validate_tokens(theme.dark, "dark");
}

def _is_dark(hex_color: str) -> bool {
    return contrast_ratio("#FFFFFF", hex_color) >= contrast_ratio("#000000", hex_color);
}

def _with_lightness(hex_color: str, lightness: float) -> str {
    (r0, g0, b0) = _channels(hex_color);
    (h, _, s) = rgb_to_hls(r0, g0, b0);
    (r, g, b) = hls_to_rgb(h, min(max(lightness, 0.0), 1.0), s);
    return "#" + "".join(f"{round(c * 255):02X}" for c in (r, g, b));
}

def _lightness(hex_color: str) -> float {
    (r, g, b) = _channels(hex_color);
    return rgb_to_hls(r, g, b)[1];
}

def _fix_foreground(fg: str, backgrounds: list[str], required: float) -> str {
    # Move only the lightness (hue and saturation kept) away from the backgrounds until
    # the colour meets `required` against every one of them. Backgrounds share a polarity
    # (see _normalise_canvas), so the darkest/lightest extreme always satisfies them all.
    if all(contrast_ratio(fg, bg) >= required for bg in backgrounds) {
        return fg;
    }
    go_darker = not _is_dark(backgrounds[0]);
    lightness = _lightness(fg);
    candidate = fg;
    for _ in range(101) {
        lightness = lightness - 0.01 if go_darker else lightness + 0.01;
        candidate = _with_lightness(fg, lightness);
        if all(contrast_ratio(candidate, bg) >= required for bg in backgrounds) {
            return candidate;
        }
        if lightness <= 0.0 or lightness >= 1.0 {
            break;
        }
    }
    return "#000000" if go_darker else "#FFFFFF";
}

def _normalise_canvas(values: dict[str, str]) -> dict[str, str] {
    # Pull surface-like fills onto the background's side (dark or light), keeping their hue.
    # Direction is decided by perceived brightness (contrast), not HLS lightness: a saturated
    # yellow at L=0.5 is light while a blue at L=0.6 is dark.
    page_dark = _is_dark(values["background"]);
    for role in CANVAS_ROLES {
        colour = values[role];
        lightness = _lightness(colour);
        for _ in range(101) {
            if _is_dark(colour) == page_dark {
                break;
            }
            lightness = lightness - 0.01 if page_dark else lightness + 0.01;
            colour = _with_lightness(values[role], lightness);
        }
        values[role] = colour;
    }
    return values;
}

def repair_tokens(tokens: ThemeTokens) -> ThemeTokens {
    values = _normalise_canvas(tokens.as_dict());
    for _ in range(10) {
        changed = False;
        for (fg, _, required) in RULES {
            backgrounds = [
                values[b]
                for (f, b, r) in RULES
                if f == fg and r == required
            ];
            fixed = _fix_foreground(values[fg], backgrounds, required);
            if fixed != values[fg] {
                values[fg] = fixed;
                changed = True;
            }
        }
        if not changed {
            break;
        }
    }
    return ThemeTokens(**values);
}

def repair_theme(theme: Theme) -> Theme {
    return Theme(
        name=theme.name,
        light=repair_tokens(theme.light),
        dark=repair_tokens(theme.dark),
        display_font=theme.display_font,
        body_font=theme.body_font,
        radius=theme.radius
    );
}

# The approved platform default: a cinematic storefront. Light: warm off-white + spotlight gold
# (P0.8 preview). Dark: "Espresso Noir" (warm brown-black, sepia, brass gold), chosen 2026-09-27.
glob DEFAULT_THEME: Theme = Theme(
         name="AfriCinemas",
         light=ThemeTokens(
             background="#FBFAF7",
             surface="#FFFFFF",
             raised="#F3F1FA",
             border="#E6E3EF",
             field="#7C7896",
             ink="#15122E",
             muted="#5E5A78",
             accent="#E0A526",
             on_accent="#1A1203",
             accent_ink="#8A5A00",
             link="#3F35C4",
             danger="#B91C1C",
             success="#15803D",
             warning="#A16207",
             focus_ring="#3F35C4",
             seat_available="#6F6A97",
             seat_selected="#A16207",
             on_seat_selected="#FFFFFF",
             seat_held="#7A73C9",
             seat_sold="#D9D7E3"
         ),
         dark=ThemeTokens(
             background="#0F0C09",
             surface="#1C1712",
             raised="#27201A",
             border="#3F342A",
             field="#9C8E7C",
             ink="#F7F1E8",
             muted="#BDAE9A",
             accent="#E7B03A",
             on_accent="#1A1203",
             accent_ink="#E7B03A",
             link="#F2C766",
             danger="#F87171",
             success="#4ADE80",
             warning="#FBBF24",
             focus_ring="#E7B03A",
             seat_available="#9C8E7C",
             seat_selected="#E7B03A",
             on_seat_selected="#1A1203",
             seat_held="#7A6344",
             seat_sold="#332A21"
         ),
         display_font="Bebas Neue",
         body_font="Outfit",
         radius="medium"
     );
