"""P3.8a: a cinema's theme as data (core/theming/branding.jac) and its logo (poster.jac).

A theme arrives as plain data (Theme.as_dict's shape) and is read strictly: every colour
role, in both modes, as #RRGGBB, and fonts and radius from the allowlists; anything else
is refused, so nothing but token values can be stored. Unreadable colours are repaired
(tokens.repair_theme), and each change is reported so the owner can see it. Presets are
ready-made themes. A logo is checked like a poster and kept with its transparency.
"""

import io;
import from PIL { Image }
import from core.theming.tokens {
    DEFAULT_THEME,
    ROLES,
    InvalidThemeValue,
    validate_theme,
    repair_theme
}
import from core.theming.branding { PRESETS, NAME_MAX, parse_theme, repair_reporting }
import from core.catalog.poster { PosterRejected, process_logo }

def _data(changes: dict[str, any] | None = None) -> dict[str, any] {  # jac:ignore[W1037]
    data: dict[str, any] = DEFAULT_THEME.as_dict();  # jac:ignore[W1037]
    for (k, v) in (changes or {}).items() {
        data[k] = v;
    }
    return data;
}

def _with_role(mode: str, role: str, value: any) -> dict[str, any] {  # jac:ignore[W1037]
    data = _data();
    tokens = dict(data[mode]);
    tokens[role] = value;
    data[mode] = tokens;
    return data;
}

def _refused(data: any) -> bool {  # jac:ignore[W1037]
    try {
        parse_theme(data);
    } except InvalidThemeValue {
        return True;
    }
    return False;
}

def _png(size: tuple[int, int], mode: str = "RGB") -> bytes {
    out = io.BytesIO();
    fill = (231, 176, 58, 0) if mode == "RGBA" else "#E7B03A";
    Image.new(mode, size, fill).save(out, format="PNG");
    return out.getvalue();
}

test "the presets are the platform default and three cinema looks, readable as they stand" {
    assert [p.name for p in PRESETS]
        == ["AfriCinemas", "Projector Black", "Velvet Curtain", "Blackout Crimson"];
    assert PRESETS[0].as_dict() == DEFAULT_THEME.as_dict();
    for preset in PRESETS {
        assert validate_theme(preset) == [] , preset.name;
        assert repair_theme(preset).as_dict() == preset.as_dict() , preset.name;
    }
}

test "a theme is read from plain data, colours tidied to upper case" {
    lower = _with_role("light", "accent", "#e0a526");
    assert parse_theme(lower).light.accent == "#E0A526";
    assert parse_theme(_data()).as_dict() == DEFAULT_THEME.as_dict();
    assert parse_theme(_data({"name": "  Nova   Gold  "})).name == "Nova Gold";
}

test "anything that isn't a token value is refused" {
    missing = _data();
    light = dict(missing["light"]);
    light.pop("accent");
    missing["light"] = light;
    extra_role = _with_role("dark", "glow", "#FFFFFF");
    for bad in [
        "not a theme",
        missing,
        extra_role,
        _data({"css": "body{display:none}"}),
        _data({"light": "#FFFFFF"}),
        _with_role("light", "accent", "#123456;}body{background:red"),
        _with_role("light", "accent", "red"),
        _with_role("dark", "ink", 123),
        _data({"display_font": "Comic Sans"}),
        _data({"body_font": "url(evil)"}),
        _data({"radius": "huge"}),
        _data({"name": ""}),
        _data({"name": "x" * (NAME_MAX + 1)}),
        _data({"name": 7})
    ] {
        assert _refused(bad) , bad;
    }
    assert len(ROLES) == 20;
}

test "repairs are reported colour by colour, and a readable theme is left alone" {
    unreadable = parse_theme(_with_role("light", "link", "#F5F2EA"));
    (fixed, changes) = repair_reporting(unreadable);
    assert [(c["mode"], c["role"], c["before"]) for c in changes]
        == [("light", "link", "#F5F2EA")] , changes;
    assert changes[0]["after"] == fixed.light.link != "#F5F2EA";
    assert validate_theme(fixed) == [];
    (same, none) = repair_reporting(DEFAULT_THEME);
    assert none == [] and same.as_dict() == DEFAULT_THEME.as_dict();
}

test "a logo keeps its transparency and is scaled down to fit 512 x 512" {
    webp = process_logo(_png((1024, 256), "RGBA"), "image/png");
    img = Image.open(io.BytesIO(webp));
    assert img.format == "WEBP" and img.size == (512, 128) , img.size;
    assert img.mode == "RGBA";
    small = Image.open(io.BytesIO(process_logo(_png((120, 80)), "image/png")));
    assert small.size == (120, 80);
}

test "logos that are too small or not an allowed image are refused" {
    for (data, declared, code) in [
        (_png((32, 32)), "image/png", "too_small"),
        (_png((200, 200)), "image/gif", "wrong_type"),
        (_png((200, 200)), "image/jpeg", "wrong_type"),
        (b"<svg xmlns='http://www.w3.org/2000/svg'/>", "image/svg+xml", "wrong_type")
    ] {
        try {
            process_logo(data, declared);
            assert False , f"{declared} {code} was accepted";
        } except PosterRejected as e {
            assert e.code == code , e.code;
        }
    }
}
