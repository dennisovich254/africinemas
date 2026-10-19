"""The pattern drawn from a logo (ADR-0045): the brief, the image kept, the style.

No network: the model call (`send`) is replaced. Only a real image is stored, re-encoded
as WebP and no larger than MAX_SIDE; the style is one of STYLES, the model's pick or
DEFAULT_STYLE.
"""

import io;
import base64;
import from PIL { Image }
import from jaclang.byllm.lib { MockLLM }
import from core.theming.tokens { DEFAULT_THEME }
import from core.theming.branding { parse_theme }
import core.theming.pattern as pattern;
import from core.theming.pattern {
    PatternFailed,
    STYLES,
    DEFAULT_STYLE,
    MAX_SIDE,
    pattern_prompt,
    as_webp,
    checked_style,
    choose_style
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

test "a transparent ground stays transparent, never black" {
    clear = Image.new("RGBA", (64, 64), (0, 0, 0, 0));
    clear.putpixel((10, 10), (232, 90, 140, 255));
    out = io.BytesIO();
    clear.save(out, "PNG");
    kept = Image.open(io.BytesIO(as_webp(out.getvalue())));
    assert kept.mode == "RGBA";
    assert kept.getpixel((40, 40))[3] == 0 , "the ground is see-through";
}

test "a drawing comes from the model's answer; an answer without an image fails" {
    image = base64.b64encode(_png(800, 500)).decode();
    pattern.send = lambda (_logo: bytes, _brief: str) -> any { return {
        "candidates": [{"content": {"parts": [{"inlineData": {"data": image}}]}}]
    }; };
    drawn = pattern.draw_pattern(_png(100, 100), _theme("auto"));
    assert Image.open(io.BytesIO(drawn)).format == "WEBP";
    pattern.send = lambda (_logo: bytes, _brief: str) -> any { return {
        "candidates": [{"content": {"parts": [{"text": "I can't draw that"}]}}]
    }; };
    try {
        pattern.draw_pattern(_png(100, 100), _theme("auto"));
        assert False , "an answer without an image must fail";
    } except PatternFailed {}
}

test "a style is one of the designed ones" {
    for style in STYLES {
        assert checked_style(style) == style;
    }
    for bad in ["everywhere", "", None, ["ambient"]] {
        try {
            checked_style(bad);
            assert False , bad;
        } except ValueError {}
    }
}

test "the model picks the style; if it can't, the pattern is ambient" {
    pattern.style_model = MockLLM(outputs=["spotlight"]);
    assert choose_style(_png(100, 100), _png(200, 100)) == "spotlight";
    pattern.style_model = MockLLM(outputs=["somewhere odd"]);
    assert choose_style(_png(100, 100), _png(200, 100)) == DEFAULT_STYLE;
}
