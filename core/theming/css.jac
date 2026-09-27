"""Theme -> CSS variables, scoped per surface, for light and dark mode (P0.8b).

Only validated values reach CSS: colours are strict #RRGGBB (core.theming.tokens), fonts
and radius come from allowlists, and the surface name is checked against SURFACES, so a
theme can never inject CSS. The platform stylesheet (styles/brand.css) is generated from
here by scripts/gen_brand_css.jac; a unit test fails if the committed file drifts.
"""

import from core.theming.tokens { Theme, ThemeTokens, ROLES, DEFAULT_THEME }

glob SURFACES: list[str] = ["storefront", "backoffice"],
     RADIUS_REM: dict[str, str] = {
         "none": "0rem",
         "small": "0.375rem",
         "medium": "0.625rem",
         "large": "0.875rem"
     },
     # Every allowlisted font (tokens.DISPLAY_FONTS / BODY_FONTS) with its fontsource
     # family name first and a safe fallback. Fonts not yet installed fall back cleanly.
     FONT_STACKS: dict[str, str] = {
         "Bebas Neue": "'Bebas Neue', 'Outfit Variable', sans-serif",
         "Outfit": "'Outfit Variable', 'Outfit', sans-serif",
         "Inter": "'Inter Variable', 'Inter', sans-serif",
         "DM Sans": "'DM Sans Variable', 'DM Sans', sans-serif",
         "Raleway": "'Raleway Variable', 'Raleway', sans-serif",
         "Figtree": "'Figtree Variable', 'Figtree', sans-serif",
         "Noto Sans": "'Noto Sans Variable', 'Noto Sans', sans-serif",
         "Public Sans": "'Public Sans Variable', 'Public Sans', sans-serif",
         "Roboto": "'Roboto Variable', 'Roboto', sans-serif"
     },
     # shadcn variable -> theme role. Note shadcn's "--accent" is the hover background,
     # not the brand accent; the brand accent drives "--primary".
     SHADCN_MAP: dict[str, str] = {
         "--background": "background",
         "--foreground": "ink",
         "--card": "surface",
         "--card-foreground": "ink",
         "--popover": "raised",
         "--popover-foreground": "ink",
         "--primary": "accent",
         "--primary-foreground": "on_accent",
         "--secondary": "raised",
         "--secondary-foreground": "ink",
         "--muted": "raised",
         "--muted-foreground": "muted",
         "--accent": "raised",
         "--accent-foreground": "ink",
         "--destructive": "danger",
         "--border": "border",
         "--input": "field",
         "--ring": "focus_ring"
     };

def _declarations(tokens: ThemeTokens, theme: Theme, scheme: str) -> list[str] {
    values = tokens.as_dict();
    lines = [
        f"  color-scheme: {scheme};",
        f"  --font-display: {FONT_STACKS[theme.display_font]};",
        f"  --font-sans: {FONT_STACKS[theme.body_font]};",
        f"  --radius: {RADIUS_REM[theme.radius]};"
    ];
    for (css_var, role) in SHADCN_MAP.items() {
        lines.append(f"  {css_var}: {values[role]};");
    }
    for role in ROLES {
        lines.append(f"  --ac-{role.replace('_', '-')}: {values[role]};");
    }
    return lines;
}

def theme_css(theme: Theme, surface: str) -> str {
    if surface not in SURFACES {
        raise ValueError(f"unknown surface: {surface!r}");
    }
    scope = f'[data-surface="{surface}"]';
    light = "\n".join(_declarations(theme.light, theme, "light"));
    dark = "\n".join(_declarations(theme.dark, theme, "dark"));
    return f"{scope} {{\n{light}\n}}\n\n.dark {scope} {{\n{dark}\n}}\n";
}

# The platform back-office look (P0.8 preview): calm neutral surfaces, indigo actions.
# Tenants only change its logo and accent (3.8), never the whole palette.
glob BACKOFFICE_THEME: Theme = Theme(
         name="AfriCinemas back-office",
         light=ThemeTokens(
             background="#F6F6FA",
             surface="#FFFFFF",
             raised="#F1F0F7",
             border="#E4E3EE",
             field="#7C7896",
             ink="#16142B",
             muted="#5B5873",
             accent="#3F35C4",
             on_accent="#FFFFFF",
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
             background="#121121",
             surface="#1B1A2E",
             raised="#24233A",
             border="#2E2C47",
             field="#7A7796",
             ink="#F4F3FA",
             muted="#A3A1B8",
             accent="#5B51E6",
             on_accent="#FFFFFF",
             accent_ink="#E0A526",
             link="#A59EF7",
             danger="#F87171",
             success="#4ADE80",
             warning="#FBBF24",
             focus_ring="#E0A526",
             seat_available="#8D86C9",
             seat_selected="#E0A526",
             on_seat_selected="#1A1203",
             seat_held="#6E67D6",
             seat_sold="#34305A"
         ),
         display_font="Bebas Neue",
         body_font="Outfit",
         radius="medium"
     ),
     BASE_RULES: str = """[data-surface] {
  background: var(--background);
  color: var(--foreground);
  font-family: var(--font-sans);
}

[data-surface] .font-display {
  font-family: var(--font-display);
  letter-spacing: 0.02em;
}
""";

def platform_stylesheet -> str {
    header = "/* GENERATED from core/theming (tokens.jac + css.jac) by scripts/gen_brand_css.jac.\n   Do not edit by hand: change the tokens and regenerate. */\n\n";
    return (
        header
        + BASE_RULES
        + "\n"
        + theme_css(DEFAULT_THEME, "storefront")
        + "\n"
        + theme_css(BACKOFFICE_THEME, "backoffice")
    );
}
