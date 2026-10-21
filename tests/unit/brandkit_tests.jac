"""A cinema's brand kit from its logo (ADR-0046, ADR-0049): the plan, the figures, the look.

No network: Claude (`ask`) is replaced. Only designed look values survive; a figure is
cut out of the logo itself (its box, its colour) and traced as an SVG; a failing plan
gives no figures and the default look, and says so.
"""

import io;
import re;
import from PIL { Image, ImageDraw }
import core.theming.brandkit as brandkit;
import from core.ai.claude { ClaudeFailed }
import from core.theming.brandkit {
    KitFailed,
    DEFAULT_LOOK,
    LOOK_PARTS,
    checked_look,
    plan_schema,
    plan_kit,
    cut_motif,
    draw_kit
}

glob GOLD: tuple[int, int, int] = (201, 164, 58),
     ORANGE: tuple[int, int, int] = (231, 111, 81),
     BIRD_BOX: list[int] = [200, 20, 290, 100],
     PLAN: dict[str, any] = {  # jac:ignore[W1037]
         "motifs": [
             {"name": "a bird in flight", "box": BIRD_BOX, "colour": "#c9a43a"},
             {"name": "a third one", "box": [0, 0, 5, 5], "colour": "#c9a43a"}
         ],
         "card": "notched",
         "frame": "open",
         "divider": "motif",
         "heading": "caps",
         "fonts": "gallery",
         "header": "centred",
         "hero": "split",
         "surfaces": "flat",
         "density": "compact",
         "tagline": '"Where Nairobi meets the movies, every single night of the week and more"'
     };

def _logo -> bytes {
    # A gold bird on an orange stripe, beside gold lettering, on a clear background.
    img = Image.new("RGBA", (300, 120), (0, 0, 0, 0));
    d = ImageDraw.Draw(img);
    d.rectangle((10, 30, 150, 90), fill=GOLD + (255, ));  # the "lettering"
    d.rectangle((190, 55, 300, 70), fill=ORANGE + (255, ));  # a sun stripe behind the bird
    d.ellipse((215, 45, 265, 80), fill=GOLD + (255, ));  # the bird's body
    d.polygon([(225, 50), (205, 22), (250, 48)], fill=GOLD + (255, ));  # a wing
    out = io.BytesIO();
    img.save(out, "WEBP", lossless=True);
    return out.getvalue();
}

obj Scripted {
    has answers: list[any] = [],  # jac:ignore[W1037]
        sent: list[str] = [];

    def ask(
        content: list[dict[str, any]],  # jac:ignore[W1037]
        schema: dict[str, any],  # jac:ignore[W1037]
        system: str = "",
        effort: str = "",
        timeout: float = 0.0
    ) -> dict[str, any] {  # jac:ignore[W1037]
        self.sent.append(str(content)[-400:] + system);
        answer = self.answers.pop(0);
        if isinstance(answer, Exception) {
            raise answer;
        }
        return answer;
    }
}

test "a figure is cut out of the logo itself and traced as an SVG" {
    svg = cut_motif(_logo(), BIRD_BOX, GOLD);
    assert svg.startswith('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ');
    assert re.search(r'<path fill="#000" fill-rule="evenodd" d="M[0-9.]+,[0-9.]+', svg);
    assert "C" in svg , "smooth curves, not pixel steps";
    # The orange stripe behind the bird is left out: the traced shape is bird-sized,
    # about as wide as tall, not a long stripe.
    size = re.search(r'viewBox="0 0 ([0-9.]+) ([0-9.]+)"', svg);
    assert size is not None;
    w = float(size.group(1));
    h = float(size.group(2));
    assert w / h < 1.6 , (w, h);
    for bad in [[0, 0, 4, 4], [400, 400, 500, 500]] {
        try {
            cut_motif(_logo(), bad, GOLD);
            assert False , bad;
        } except KitFailed {}
    }
}

test "a look is designed choices, nothing else; an older look gains the defaults" {
    older = {"card": "notched", "frame": "open", "divider": "row", "heading": "caps"};
    full = checked_look(older);
    assert full == {** DEFAULT_LOOK, ** older};
    assert checked_look(full) == full;
    for bad in [
        {},
        {"card": "blob", "frame": "open", "divider": "row", "heading": "caps"},
        {"card": "notched", "frame": "open", "divider": "row"},
        {** full, "fonts": "comic sans"},
        {** full, "hero": "fullscreen backdrop"},
        "notched"
    ] {
        try {
            checked_look(bad);
            assert False , bad;
        } except ValueError {}
    }
}

test "the schema holds every part of the look to its designed values" {
    schema = plan_schema();
    for (key, allowed) in LOOK_PARTS {
        assert schema["properties"][key]["enum"] == list(allowed) , key;
    }
    figure = schema["properties"]["motifs"]["items"];
    assert figure["required"] == ["name", "box", "colour"];
    assert schema["additionalProperties"] == False;
}

test "the plan keeps Claude's figures and look; a failure gives the default look" {
    model = Scripted(answers=[PLAN]);
    brandkit.ask = model.ask;
    (figures, look, tagline, from_ai) = plan_kit(_logo(), "Rupa's Mall");
    assert from_ai;
    assert [f["name"] for f in figures] == ["a bird in flight", "a third one"];
    assert figures[0]["colour"] == GOLD and figures[0]["box"] == BIRD_BOX;
    assert look["fonts"] == "gallery"
        and look["hero"] == "split"
        and look["card"] == "notched";
    assert tagline.startswith("Where Nairobi")
        and len(tagline) <= 60
        and '"' not in tagline;
    assert "300 x 120 pixels" in model.sent[0] , "Claude is told the logo's size for its boxes";
    brandkit.ask = Scripted(answers=[ClaudeFailed("the model declined")]).ask;
    (none, fallback, no_line, answered) = plan_kit(_logo(), "Rupa's Mall");
    assert none == [] and fallback == DEFAULT_LOOK and no_line == "" and not answered;
}

test "a kit keeps the figures that cut; with none, the divider is a plain line" {
    brandkit.ask = Scripted(answers=[PLAN]).ask;
    kit = draw_kit(_logo(), "Rupa's Mall");
    assert [m["name"] for m in kit["motifs"]] == ["a bird in flight"] , "the empty box is left out";
    assert kit["motifs"][0]["type"] == "svg" and kit["from_ai"];
    assert kit["look"]["divider"] == "motif";
    nothing = {
        ** PLAN,
        "motifs": [{"name": "a ghost", "box": [0, 0, 5, 5], "colour": "#c9a43a"}]
    };
    brandkit.ask = Scripted(answers=[nothing]).ask;
    bare = draw_kit(_logo(), "Rupa's Mall");
    assert bare["motifs"] == [] and bare["look"]["divider"] == "line";
    brandkit.ask = Scripted(answers=[ClaudeFailed("402")]).ask;
    failed = draw_kit(_logo(), "Rupa's Mall");
    assert not failed["from_ai"] and failed["motifs"] == [];
}
