"""P0.8a: theme model and validator (typed tokens, strict parsing, WCAG AA, auto-repair)."""

import random;
import from colorsys { rgb_to_hls }
import from core.theming.tokens {
    ThemeTokens,
    Theme,
    ContrastIssue,
    InvalidThemeValue,
    ROLES,
    DEFAULT_THEME,
    contrast_ratio,
    validate_theme,
    repair_theme
}

def _swap(tokens: ThemeTokens, role: str, value: str) -> ThemeTokens {
    return ThemeTokens(**{** tokens.as_dict(), role: value});
}

def _hls(hex_color: str) -> tuple[float, float, float] {
    return rgb_to_hls(
        int(hex_color[1:3], 16) / 255,
        int(hex_color[3:5], 16) / 255,
        int(hex_color[5:7], 16) / 255
    );
}

def _random_hex(rng: random.Random) -> str {
    return "#" + "".join(rng.choice("0123456789ABCDEF") for _ in range(6));
}

def _random_theme(rng: random.Random) -> Theme {
    def palette -> ThemeTokens {
        return ThemeTokens(**{role: _random_hex(rng) for role in ROLES});
    }
    return Theme(
        name="random",
        light=palette(),
        dark=palette(),
        display_font="Bebas Neue",
        body_font="Outfit",
        radius="medium"
    );
}

test "contrast matches WCAG reference values" {
    assert round(contrast_ratio("#000000", "#FFFFFF"), 2) == 21.0;
    assert round(contrast_ratio("#FFFFFF", "#000000"), 2) == 21.0;
    assert round(contrast_ratio("#777777", "#FFFFFF"), 2) == 4.48;
    assert contrast_ratio("#3F35C4", "#3F35C4") == 1.0;
}

test "default theme passes every rule in both modes" {
    issues = validate_theme(DEFAULT_THEME);
    assert issues == [] , f"default theme fails: {issues}";
}

test "colours must be strict #RRGGBB hex" {
    for bad in [
        "red",
        "#FFF",
        "#GGGGGG",
        "#123456;}body{display:none",
        "",
        "#1234567",
        "rgb(0,0,0)"
    ] {
        with testraises(InvalidThemeValue) {
            _swap(DEFAULT_THEME.light, "ink", bad);
        }
    }
    # Lower-case is accepted and normalised to upper-case.
    assert _swap(DEFAULT_THEME.light, "ink", "#15122e").ink == "#15122E";
}

test "fonts and radius come from allowlists" {
    with testraises(InvalidThemeValue) {
        Theme(
            name="x",
            light=DEFAULT_THEME.light,
            dark=DEFAULT_THEME.dark,
            display_font="Comic Sans MS",
            body_font="Outfit",
            radius="medium"
        );
    }
    with testraises(InvalidThemeValue) {
        Theme(
            name="x",
            light=DEFAULT_THEME.light,
            dark=DEFAULT_THEME.dark,
            display_font="Bebas Neue",
            body_font="https://evil.example/font.woff2",
            radius="medium"
        );
    }
    with testraises(InvalidThemeValue) {
        Theme(
            name="x",
            light=DEFAULT_THEME.light,
            dark=DEFAULT_THEME.dark,
            display_font="Bebas Neue",
            body_font="Outfit",
            radius="huge"
        );
    }
}

test "a bad theme is reported rule by rule" {
    unreadable = _swap(DEFAULT_THEME.light, "ink", DEFAULT_THEME.light.background);
    theme = Theme(
        name="bad",
        light=unreadable,
        dark=DEFAULT_THEME.dark,
        display_font="Bebas Neue",
        body_font="Outfit",
        radius="medium"
    );
    issues = validate_theme(theme);
    hit = [
        i
        for i in issues
        if i.mode == "light" and i.fg_role == "ink" and i.bg_role == "background"
    ];
    assert len(hit) == 1 , f"issues: {issues}";
    assert hit[0].ratio < 1.1 and hit[0].required == 4.5;
    assert all(i.mode == "light" for i in issues) , "dark mode was untouched";
}

test "repair makes 200 random palettes pass" {
    rng = random.Random(20260927);
    for n in range(200) {
        repaired = repair_theme(_random_theme(rng));
        issues = validate_theme(repaired);
        assert issues == [] , f"palette {n} still fails after repair: {issues[:3]}";
    }
}

test "repair leaves a valid theme unchanged" {
    # Compared by value: `obj` equality is identity-based (JI-016).
    assert repair_theme(DEFAULT_THEME).as_dict() == DEFAULT_THEME.as_dict();
}

test "repair keeps the hue of saturated colours" {
    rng = random.Random(7);
    for _ in range(100) {
        original = _random_theme(rng);
        repaired = repair_theme(original);
        for mode in ["light", "dark"] {
            before = getattr(original, mode).as_dict();
            after = getattr(repaired, mode).as_dict();
            for role in ROLES {
                (h1, l1, s1) = _hls(before[role]);
                (h2, l2, s2) = _hls(after[role]);
                if before[role] != after[role]
                    and s1 > 0.3
                    and s2 > 0.3
                    and 0.05 < l2 < 0.95 {
                    drift = min(abs(h1 - h2), 1 - abs(h1 - h2));
                    assert drift < 0.03 , f"{mode}.{role} hue drifted {before[role]} -> {after[
                        role
                    ]}";
                }
            }
        }
    }
}
