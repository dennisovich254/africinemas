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
    checked_proposal,
    ThemeModel,
    _short_name
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
    # A dark page in light mode would make the mode switch look wrong: dropped.
    assert checked_proposal(
        _proposal("Upside Down", {"background": "#101010", "ink": "#f0f0f0"})
    )
        is None;
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

test "the model's theme is checked, and a broken one gives the logo's theme" {
    suggest.theme_model = MockLLM(
        outputs=[
            _proposal("A very long mood name that goes on and on and on for ever"),
            _proposal("Broken", {"accent": "not a colour"})
        ]
    );
    got = suggest.suggest_from_logo(_logo(), "Nova Cinemas");
    assert got["from_ai"] and len(got["proposals"]) == 1;
    name = got["proposals"][0]["theme"]["name"];
    assert len(name) <= 40 and not name.startswith("A ") , name;
    assert validate_theme(parse_theme(got["proposals"][0]["theme"])) == [];
    assert got["colours"][0]["hex"] == "#78141e";
    sent = str(suggest.theme_model.sent("messages"));
    assert "#78141e" in sent , "the model sees the logo's exact colours";
    assert "Nova Cinemas" in sent;
    assert any([d in sent for d in suggest.DIRECTIONS]) , "each ask has a style direction";
    # The next ask's theme is broken: the owner gets the logo's theme instead.
    again = suggest.suggest_from_logo(_logo(), "Nova Cinemas");
    assert not again["from_ai"];
    assert again["proposals"][0]["theme"]["name"] == "From your logo";
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

obj ScriptedThemeModel(ThemeModel) {
    # A ThemeModel whose attempts are scripted per model name: no network.
    has fails: list[str] = [],
        tried: list[dict[str, any]] = [];  # jac:ignore[W1037]

    override def _attempt(params: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
        self.tried.append(params);
        if params["model"] in self.fails {
            raise RuntimeError(f"{params['model']} is overloaded");
        }
        return {"answered_by": params["model"]};
    }
}

test "an overloaded model hands over to the next, each with its own time limit" {
    model = ScriptedThemeModel(
        model_name="test/lite",
        fallback_models=["test/flash", "test/older"],
        fails=["test/lite"]
    );
    got = model.model_call_no_stream({"model": "ignored", "messages": []});
    assert got == {"answered_by": "test/flash"};
    assert [t["model"] for t in model.tried] == ["test/lite", "test/flash"];
    assert all(
        [
            t["timeout"] == model.attempt_timeout and t["num_retries"] == 0
            for t in model.tried
        ]
    );
    every = ScriptedThemeModel(
        model_name="test/lite",
        fallback_models=["test/flash"],
        fails=["test/lite", "test/flash"]
    );
    try {
        every.model_call_no_stream({"messages": []});
        assert False , "all models failing must raise";
    } except RuntimeError as e {
        assert "test/flash" in str(e);
    }
}

test "a theme's name is short, even when the model wrote a sentence" {
    assert _short_name("Midnight Premiere") == "Midnight Premiere";
    assert _short_name("A bold, high-contrast theme that leans into the purples")
        == "Bold High-contrast Theme";
    assert len(_short_name("Supercalifragilistic " * 5)) <= 40;
    assert _short_name("   ") == "From your logo";
}
