"""The storefront the AI writes (ADR-0048): only a safe, complete template survives.

No network: the model call (`send`) is replaced. The fixture is a template with the slots
filled in the right places and a few hostile extras that must be dropped.
"""

import core.theming.pagecode as pagecode;
import from core.theming.pagecode {
    PageFailed,
    sanitize,
    clean_css,
    bundled_fonts,
    write_page,
    brief,
    brand_brief
}

glob FIXTURE: str = "tests/fixtures/ai_storefront.html";

def _fixture -> str {
    with open(FIXTURE) as f {
        return f.read();
    }
}

test "a complete template keeps its slots and drops scripts, handlers and outside links" {
    made = sanitize(_fixture());
    assert made["problems"] == [] , made["problems"];
    page = made["html"];
    for kept in [
        'data-part="header"',
        'data-each="film.times"',
        'data-text="film.title"',
        'data-img="logo"',
        'data-link="book"',
        'viewBox="0 0 40 40"',
        '<span data-motif="single" class="dove">',
        '<span data-motif="group" class="flock">',
        "<linearGradient",
        "Tickets by AfriCinemas"
    ] {
        assert kept in page , kept;
    }
    for gone in [
        "<script",
        "alert",
        "onclick",
        "<iframe",
        "evil.example",
        "src=",
        'data-motif="flock"',
        '<a data-motif'
    ] {
        assert gone not in page , gone;
    }
}

test "the stylesheet is scoped to the page, with no outside urls, imports or fixed boxes" {
    css = sanitize(_fixture())["css"];
    assert ".ai-page {" in css and ".ai-page .hero {" in css;
    assert ".ai-page h1, .ai-page h2" in css;
    assert "evil.example" not in css and "@import" not in css;
    assert "fixed" not in css and ".ai-page .sneaky { color: red }" in css;
    assert "url(#sunset)" in css , "SVG paint by id stays";
    assert "@media (max-width: 600px)" in css;
    assert "'Nunito Variable'" in css and "'Baloo 2 Variable'" in css , "bundled fonts";
    assert clean_css("body { margin: 0 } :root { --a: 1 }")
        == ".ai-page { margin: 0 }\n.ai-page { --a: 1 }";
    assert bundled_fonts("Cinzel, serif") == "'Cinzel Variable', serif";
    assert bundled_fonts("'Cinzel Variable', serif") == "'Cinzel Variable', serif";
}

test "a template missing a part is reported" {
    made = sanitize("<style></style><main data-part=\"home\"></main>");
    joined = " ".join(made["problems"]);
    assert "header" in joined and "footer" in joined and "logo" in joined;
    assert "data-link=\"book\"" in joined and "AfriCinemas" in joined;
}

test "write_page asks again with what was missing, then gives up" {
    answers = ["<main data-part=\"home\"></main>", _fixture()];
    briefs: list[str] = [];
    def scripted(_logo: bytes, prompt: str, _model: str) -> str {
        briefs.append(prompt);
        return answers.pop(0);
    }
    pagecode.send = scripted;
    page = write_page(b"logo", "Kijiji Cinema");
    assert "data-part=\"header\"" in page["html"] and page["css"];
    assert len(briefs) == 2
        and "was missing" in briefs[1]
        and "Kijiji Cinema" in briefs[0];
    def broken(_logo: bytes, _prompt: str, _model: str) -> str {
        raise PageFailed("503 busy");
    }
    pagecode.send = broken;
    try {
        write_page(b"logo", "Kijiji Cinema");
        assert False , "must fail";
    } except PageFailed {}
}

test "the page is written in the site's own colours, fonts and corners" {
    brand = {
        "scheme": "dark",
        "colours": {"background": "#120f0a", "accent": "#d9b44c"},
        "fonts": ["Raleway", "DM Sans"],
        "corners": "sharp, almost square (2px)",
        "figures": ["one dove in flight", "three doves"],
        "tagline": "Where every show takes flight"
    };
    prompts: list[str] = [];
    def scripted(_logo: bytes, prompt: str, _model: str) -> str {
        prompts.append(prompt);
        return _fixture();
    }
    pagecode.send = scripted;
    write_page(b"logo", "Rupa's Mall", brand);
    sent = prompts[0];
    for part in [
        "Colour scheme: dark",
        "background: #120f0a",
        "accent: #d9b44c",
        "headings in Raleway, body text in DM Sans",
        "Corners: sharp",
        "one dove in flight; three doves",
        "Where every show takes flight"
    ] {
        assert part in sent , part;
    }
    bare = brand_brief({** brand, "figures": []});
    assert "no figures to place" in bare , "no motif slots without figures";
    assert "brand system" not in brief("Rupa's Mall") , "no brand, no system";
}
