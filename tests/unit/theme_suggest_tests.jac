"""Theme suggestions from a logo (ADR-0043, ADR-0049), with a scripted model (no key).

The logo's colours are read by code, exactly; whatever the model proposes is rebuilt as
theme data, repaired and validated, so every theme an owner sees is readable and uses
only allowlisted fonts; a failing model gives one theme built from the logo instead.
"""

import io;
import from PIL { Image }
import from core.ai.claude { ClaudeFailed }
import from core.theming.tokens {
    DEFAULT_THEME,
    DISPLAY_FONTS,
    BODY_FONTS,
    ROLES,
    validate_theme
}
import from core.theming.branding { parse_theme }
import core.theming.suggest as suggest;
import from core.theming.suggest {
    ThemeProposal,
    ModeColours,
    logo_colours,
    checked_proposal,
    theme_schema,
    proposal_from,
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
        radius=radius,
        scheme="light",
        template="schedule"
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

test "the model picks light or dark for everyone; anything else follows the device" {
    dark = _proposal("Neon Nights");
    dark.scheme = "dark";
    assert checked_proposal(dark)["theme"]["scheme"] == "dark";
    odd = _proposal("Sepia");
    odd.scheme = "sepia";
    assert checked_proposal(odd)["theme"]["scheme"] == "auto";
}

test "a home page layout is offered only when it is one of the templates" {
    assert checked_proposal(_proposal("Busy Nights"))["template"] == "schedule";
    odd = _proposal("Odd");
    odd.template = "magazine";
    assert checked_proposal(odd)["template"] == "";
    assert suggest.code_proposal(["#78141e"])["template"] == "" , "the fallback offers none";
}

test "only allowlisted fonts and corners reach the owner" {
    shown = checked_proposal(_proposal("Comic", font="Comic Sans MS", radius="blob"));
    assert shown is not None;
    assert shown["theme"]["display_font"] in DISPLAY_FONTS;
    assert shown["theme"]["display_font"] == DEFAULT_THEME.display_font;
    assert shown["theme"]["body_font"] in BODY_FONTS;
    assert shown["theme"]["radius"] == DEFAULT_THEME.radius;
}

def _answer(p: ThemeProposal) -> dict[str, any] {  # jac:ignore[W1037]
    # A proposal as Claude's JSON answer.
    return {
        "mood": p.mood,
        "reason": p.reason,
        "light": {r: getattr(p.light, r) for r in ROLES},
        "dark": {r: getattr(p.dark, r) for r in ROLES},
        "display_font": p.display_font,
        "body_font": p.body_font,
        "radius": p.radius,
        "scheme": p.scheme,
        "template": p.template
    };
}

obj Scripted {
    # Claude's answers in order (an exception is raised); what each ask sent.
    has answers: list[any] = [],  # jac:ignore[W1037]
        sent: list[str] = [];

    def ask(
        content: list[dict[str, any]],  # jac:ignore[W1037]
        schema: dict[str, any],  # jac:ignore[W1037]
        system: str = "",
        effort: str = "",
        timeout: float = 0.0
    ) -> dict[str, any] {  # jac:ignore[W1037]
        self.sent.append(str(content) + system + str(schema));
        answer = self.answers.pop(0);
        if isinstance(answer, Exception) {
            raise answer;
        }
        return answer;
    }
}

test "the model's theme is checked, and a broken one gives the logo's theme" {
    model = Scripted(
        answers=[
            _answer(
                _proposal("A very long mood name that goes on and on and on for ever")
            ),
            _answer(_proposal("Broken", {"accent": "not a colour"}))
        ]
    );
    suggest.ask = model.ask;
    got = suggest.suggest_from_logo(_logo(), "Nova Cinemas");
    assert got["from_ai"] and len(got["proposals"]) == 1;
    name = got["proposals"][0]["theme"]["name"];
    assert len(name) <= 40 and not name.startswith("A ") , name;
    assert validate_theme(parse_theme(got["proposals"][0]["theme"])) == [];
    assert got["colours"][0]["hex"] == "#78141e";
    sent = model.sent[0];
    assert "#78141e" in sent , "the model sees the logo's exact colours";
    assert "Nova Cinemas" in sent;
    assert "'type': 'image'" in sent , "and the logo itself";
    assert any([d in sent for d in suggest.DIRECTIONS]) , "each ask has a style direction";
    # The next ask's theme is broken: the owner gets the logo's theme instead.
    again = suggest.suggest_from_logo(_logo(), "Nova Cinemas");
    assert not again["from_ai"];
    assert again["proposals"][0]["theme"]["name"] == "From your logo";
}

test "a failing model gives one theme built from the logo" {
    suggest.ask = Scripted(answers=[ClaudeFailed("the model declined")]).ask;
    got = suggest.suggest_from_logo(_logo(), "Nova Cinemas");
    assert not got["from_ai"];
    assert len(got["proposals"]) == 1;
    theme = got["proposals"][0]["theme"];
    assert theme["name"] == "From your logo";
    assert validate_theme(parse_theme(theme)) == [];
    # Built on the logo's key colour (repair may darken it for contrast).
    assert theme["light"]["accent"] != DEFAULT_THEME.light.accent;
    # An answer missing a part is a failure too, never a half theme.
    half = _answer(_proposal("Half"));
    half["dark"] = {"background": "#000000"};
    suggest.ask = Scripted(answers=[half]).ask;
    assert not suggest.suggest_from_logo(_logo(), "Nova Cinemas")["from_ai"];
}

test "the schema allows only the theme's roles, fonts, corners, schemes and templates" {
    schema = theme_schema();
    props = schema["properties"];
    assert props["light"]["required"] == list(ROLES);
    assert props["display_font"]["enum"] == list(DISPLAY_FONTS);
    assert props["body_font"]["enum"] == list(BODY_FONTS);
    assert props["scheme"]["enum"] == ["light", "dark"];
    assert set(props["template"]["enum"]) == {"marquee", "schedule", "compact"};
    assert schema["additionalProperties"] == False;
    made = proposal_from(_answer(_proposal("Golden Hour")));
    assert made.light.accent == "#78141e" and made.template == "schedule";
}
