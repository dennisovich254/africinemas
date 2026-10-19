"""The pattern drawn from a logo (ADR-0045): the brief, the image kept, the places.

No network: the model call (`send`) is replaced. Only a real image is stored, re-encoded
as WebP and no larger than MAX_SIDE; places are some of PLACES, in their order.
"""

import io;
import base64;
import from PIL { Image }
import from core.theming.tokens { DEFAULT_THEME }
import from core.theming.branding { parse_theme }
import core.theming.pattern as pattern;
import from core.theming.pattern {
    PatternFailed,
    PLACES,
    MAX_SIDE,
    pattern_prompt,
    as_webp,
    checked_places
}

def _png(width: int, height: int) -> bytes {
    out = io.BytesIO();
    Image.new("RGB", (width, height), (232, 90, 140)).save(out, "PNG");
    return out.getvalue();
}

def _theme(scheme: str) -> any {  # jac:ignore[W1037]
    data: dict[str, any] = DEFAULT_THEME.as_dict();  # jac:ignore[W1037]
    data["scheme"] = scheme;
    return parse_theme(data);
}

test "the brief asks for the logo's motifs in the theme's colours, on its page colour" {
    light = pattern_prompt(_theme("light"));
    assert DEFAULT_THEME.light.background in light;
    assert DEFAULT_THEME.light.accent in light;
    assert "No text" in light;
    dark = pattern_prompt(_theme("dark"));
    assert DEFAULT_THEME.dark.background in dark , "a dark theme's pattern sits on its dark page";
}

test "only a real image is kept, as WebP no larger than MAX_SIDE" {
    kept = as_webp(_png(1600, 900));
    shown = Image.open(io.BytesIO(kept));
    assert shown.format == "WEBP";
    assert max(shown.size) == MAX_SIDE;
    try {
        as_webp(b"<svg onload=alert(1)>");
        assert False , "not an image must be refused";
    } except PatternFailed {}
}

test "a drawing comes from the model's answer; an answer without an image fails" {
    image = base64.b64encode(_png(800, 500)).decode();
    pattern.send = lambda (logo: bytes, brief: str) -> any { return {
        "candidates": [{"content": {"parts": [{"inlineData": {"data": image}}]}}]
    }; };
    drawn = pattern.draw_pattern(_png(100, 100), _theme("auto"));
    assert Image.open(io.BytesIO(drawn)).format == "WEBP";
    pattern.send = lambda (logo: bytes, brief: str) -> any { return {
        "candidates": [{"content": {"parts": [{"text": "I can't draw that"}]}}]
    }; };
    try {
        pattern.draw_pattern(_png(100, 100), _theme("auto"));
        assert False , "an answer without an image must fail";
    } except PatternFailed {}
}

test "places are some of the allowed ones, in their order" {
    assert checked_places(["footer", "hero"]) == ["hero", "footer"];
    assert checked_places([]) == [];
    assert checked_places(PLACES) == PLACES;
    for bad in [["everywhere"], "hero", None] {
        try {
            checked_places(bad);
            assert False , bad;
        } except ValueError {}
    }
}
