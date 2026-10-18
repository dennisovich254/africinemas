"""Theme suggestions from a logo (ADR-0043), with a scripted model (MockLLM, no key).

The logo's colours are read by code, exactly; whatever the model proposes is rebuilt as
theme data, repaired and validated, so every theme an owner sees is readable and uses
only allowlisted fonts; a failing model gives one theme built from the logo instead.
"""

import io;
import from PIL { Image }
import from jaclang.byllm.lib { MockLLM }
import from core.theming.tokens {
    DEFAULT_THEME,
    DISPLAY_FONTS,
    BODY_FONTS,
    validate_theme
}
import from core.theming.branding { parse_theme }
import core.theming.suggest as suggest;
import from core.theming.suggest {
    ThemeProposal,
    ModeColours,
    logo_colours,
    checked_proposal
}

glob RED: tuple[int, int, int, int] = (120, 20, 30, 255),
     GOLD: tuple[int, int, int, int] = (230, 180, 40, 255);

def _logo -> bytes {
    # A red square with a gold disc, on a transparent canvas twice its size.
    img = Image.new("RGBA", (200, 200), (0, 0, 0, 0));
    for x in range(50, 150) {
        for y in range(50, 150) {
            img.putpixel(
                (x, y), GOLD if (x - 100) ** 2 + (y - 100) ** 2 < 900 else RED
            );
        }
    }
    out = io.BytesIO();
    img.save(out, "WEBP", lossless=True);
    return out.getvalue();
}

def _mode(base: dict[str, str], changes: dict[str, str]) -> ModeColours {
    colours = dict(base);
    for (role, value) in changes.items() {
        colours[role] = value;
    }
    return ModeColours(**colours);
}

def _proposal(
    mood: str,
    light: dict[str, str] | None = None,
    font: str = "Bebas Neue",
    radius: str = "medium"
) -> ThemeProposal {
    return ThemeProposal(
        mood=mood,
        reason="Gold from the disc, red from the square.",
        light=_mode(
            DEFAULT_THEME.light.as_dict(), {"accent": "#78141e"} | (light or {})
        ),
        dark=_mode(DEFAULT_THEME.dark.as_dict(), {"accent": "#e6b428"}),
        display_font=font,
        body_font="Outfit",
        radius=radius
    );
}

test "the logo's colours are read exactly, transparent pixels skipped" {
    (swatches, keys) = logo_colours(_logo());
    hexes = [s.hex for s in swatches];
    assert hexes[0] == "#78141e" , hexes;
    assert "#e6b428" in hexes , hexes;
    assert "#000000" not in hexes , "the transparent canvas is not part of the logo";
    assert abs(sum([s.share for s in swatches]) - 1.0) < 0.01;
    assert set(keys) <= set(hexes) , (keys, hexes);
    assert keys , "a red and gold logo has brand colours";
}

test "a proposal is rebuilt as a readable theme; a broken one is dropped" {
    good = checked_proposal(_proposal("Crimson Premiere"));
    assert good is not None;
    assert good["theme"]["name"] == "Crimson Premiere";
    assert validate_theme(parse_theme(good["theme"])) == [];
    # Unreadable: white text on a white page. Repaired, never shown as it is.
    pale = checked_proposal(
        _proposal("Pale", {"ink": "#ffffff", "background": "#ffffff"})
    );
    assert pale is not None and pale["adjusted"] > 0;
    assert validate_theme(parse_theme(pale["theme"])) == [];
    # Not a colour at all: the proposal is dropped.
    assert checked_proposal(_proposal("Broken", {"accent": "gold"})) is None;
    # A hex without its "#" is still a colour.
    assert checked_proposal(_proposal("Bare", {"accent": "78141e"})) is not None;
}

test "only allowlisted fonts and corners reach the owner" {
    shown = checked_proposal(_proposal("Comic", font="Comic Sans MS", radius="blob"));
    assert shown is not None;
    assert shown["theme"]["display_font"] in DISPLAY_FONTS;
    assert shown["theme"]["display_font"] == DEFAULT_THEME.display_font;
    assert shown["theme"]["body_font"] in BODY_FONTS;
    assert shown["theme"]["radius"] == DEFAULT_THEME.radius;
}

test "the model's themes are checked, and a long mood name is cut" {
    suggest.theme_model = MockLLM(
        outputs=[
            [
                _proposal("Crimson Premiere"),
                _proposal("Broken", {"accent": "not a colour"}),
                _proposal("A very long mood name that goes on and on and on for ever"),
                _proposal("Golden Hour")
            ]
        ]
    );
    got = suggest.suggest_from_logo(_logo(), "Nova Cinemas");
    assert got["from_ai"];
    names = [p["theme"]["name"] for p in got["proposals"]];
    # At most three of the four were read, and the broken one never shows.
    assert names[0] == "Crimson Premiere" , names;
    assert "Broken" not in names and len(names) == 2 , names;
    assert all([len(n) <= 40 for n in names]) , names;
    for p in got["proposals"] {
        assert validate_theme(parse_theme(p["theme"])) == [];
    }
    assert got["colours"][0]["hex"] == "#78141e";
    sent = str(suggest.theme_model.sent("messages"));
    assert "#78141e" in sent , "the model sees the logo's exact colours";
    assert "Nova Cinemas" in sent;
}

test "a failing model gives one theme built from the logo" {
    suggest.theme_model = MockLLM(outputs=["this is not a list of themes"]);
    got = suggest.suggest_from_logo(_logo(), "Nova Cinemas");
    assert not got["from_ai"];
    assert len(got["proposals"]) == 1;
    theme = got["proposals"][0]["theme"];
    assert theme["name"] == "From your logo";
    assert validate_theme(parse_theme(theme)) == [];
    # Built on the logo's key colour (repair may darken it for contrast).
    assert theme["light"]["accent"] != DEFAULT_THEME.light.accent;
}
