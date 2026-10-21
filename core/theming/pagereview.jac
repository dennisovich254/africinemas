"""The written storefront, reviewed before it is kept (ADR-0050).

Claude writes the page in one go and never sees it, so a design meant for a full
programme came out sparse and oversized for a cinema with one film (warui, 2026-10-21),
and a decoration covered a poster. Here the page is rendered the way the storefront fills
it, with the cinema's real programme (or a sample one when it has none), screenshotted in
a headless browser on a desktop and a phone, and shown to Claude with its own template:
it reviews it as an art director and returns the template corrected.

- `filled_document` fills the template like web/storefront/AiPage.jac does: lists
  repeated, empty states decided, text, the logo and posters (2:3, drawn above
  decorations), the motifs painted through their masks, every link inert.
- `shoot` takes the screenshots (Playwright's headless Chromium). No browser installed,
  or any failure: no review, and the written page is kept as it was.
- The answer passes `pagecode.sanitize` like any written page; one that lacks a part
  is dropped and the first page kept. A review never makes a page worse than missing.
"""

import io;
import os;
import base64;
import logging;
import from datetime { datetime }
import from zoneinfo { ZoneInfo }
import from PIL { Image }
import from core.ai.claude { ClaudeFailed, ask_text, image_block, text_block }
import from core.theming.pagecode { sanitize, FONTS, SCRIPT_ENV }

class ReviewSkipped(RuntimeError) {}

::py::
import html as _html
import xml.etree.ElementTree as _ET

_SVG_NS = "http://www.w3.org/2000/svg"


def _motif_style(url):
    return (
        "display:inline-block;background-color:currentColor;"
        f"-webkit-mask:url({url}) center/contain no-repeat;mask:url({url}) center/contain no-repeat"
    )


_POSTER = "display:block;aspect-ratio:2/3;object-fit:cover;max-width:100%;position:relative;z-index:1"
_EMPTY = (
    "display:flex;align-items:flex-end;aspect-ratio:2/3;width:100%;max-width:100%;padding:12px;"
    "box-sizing:border-box;position:relative;z-index:1;font-weight:600;font-size:.875rem;"
    "text-transform:uppercase;background:linear-gradient(160deg,rgba(128,128,128,.28),rgba(128,128,128,.1))"
)


def _fill(el, scope, lists, cinema, logo, motifs):
    for child in list(el):
        each = child.get("data-each")
        if each:
            items = scope.get("times", []) if each == "film.times" else lists.get(each, [])
            at = list(el).index(child)
            el.remove(child)
            for (n, item) in enumerate(items):
                copy = _ET.fromstring(_ET.tostring(child))
                del copy.attrib["data-each"]
                _one(copy, {**scope, **item}, lists, cinema, logo, motifs)
                el.insert(at + n, copy)
            continue
        empty = child.get("data-empty")
        if empty and lists.get(empty):
            el.remove(child)
            continue
        _one(child, scope, lists, cinema, logo, motifs)


def _one(el, scope, lists, cinema, logo, motifs):
    text = el.get("data-text")
    if text:
        for kid in list(el):
            el.remove(kid)
        el.text = cinema if text == "cinema.name" else str(scope.get(text, ""))
    img = el.get("data-img")
    if img == "logo":
        el.set("src", logo)
    elif img == "film.poster":
        if scope.get("_poster_url"):
            el.set("src", scope["_poster_url"])
            el.set("style", _POSTER)
        else:
            el.tag = "span"
            el.set("style", _EMPTY)
            el.text = str(scope.get("film.title", ""))
    motif = el.get("data-motif")
    if motif:
        if motifs:
            el.set("style", _motif_style(motifs[0] if motif == "single" else motifs[-1]))
        else:
            el.set("style", "display:none")
    if el.get("data-link"):
        el.set("href", "#")
    _fill(el, scope, lists, cinema, logo, motifs)


def _document(html_text, css, lists, cinema, logo, motifs, fonts):
    root = _ET.fromstring('<div class="ai-page" xmlns:svg="http://www.w3.org/2000/svg">' + html_text + "</div>")
    _fill(root, {}, lists, cinema, logo, motifs)
    body = _ET.tostring(root, encoding="unicode", method="html")
    # The bundled fonts are the same families as Google's: load those for the picture.
    for (family, bundled) in fonts.items():
        css = css.replace(bundled, f"'{family}'")
    families = "&".join(
        "family=" + f.replace(" ", "+") + ":wght@300;400;500;600;700" for f in fonts
    )
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<link rel='stylesheet' href='https://fonts.googleapis.com/css2?{families}&display=swap'>"
        f"<style>html,body{{margin:0}}\n{css}</style></head><body>{body}</body></html>"
    )


def _shoot(document, sizes, height_max):
    # Screenshots of the document, one per (width, height), each at most height_max tall.
    from playwright.sync_api import sync_playwright

    shots = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        try:
            for (width, height) in sizes:
                page = browser.new_page(viewport={"width": width, "height": height})
                page.set_content(document, wait_until="load", timeout=30000)
                page.wait_for_timeout(800)
                full = page.evaluate("document.documentElement.scrollHeight")
                shots.append(
                    page.screenshot(
                        clip={"x": 0, "y": 0, "width": width, "height": min(full, height_max)},
                        type="jpeg",
                        quality=72,
                    )
                )
                page.close()
        finally:
            browser.close()
    return shots
::py::



glob logger = logging.getLogger(__name__),
     # A desktop and a phone, as the owner's visitors see the page.
     SIZES: list[tuple[int, int]] = [(1280, 900), (390, 844)],
     # Tall enough for the hero and the first sections, small enough for Claude to read.
     SHOT_HEIGHT_MAX: int = 3200,
     # Seconds for the review's model call: it rewrites the whole template.
     TIMEOUT: float = 300.0,
     MAX_OUTPUT_TOKENS: int = 64000,
     FILMS_MAX: int = 6,
     REVIEW_BRIEF: str = """Here is the storefront you designed for this cinema, rendered exactly as visitors will see it, filled with the cinema's real programme: first on a desktop (1280 px wide), then on a phone (390 px wide). Its logo is the first image.

Review it as a demanding art director, against the concept you chose, and fix everything that is off:
- space sized for this programme: no big empty areas, no oversized boxes or headings when there are few films; nothing that only works with a full programme;
- alignment, spacing rhythm and hierarchy; nothing clipped, overlapping or covering a poster;
- posters presented well (they are always 2:3);
- the logo's figures (the motif slots) placed where they help, not scattered;
- readable contrast, comfortable line lengths, tap targets on the phone, no sideways scrolling.

Then answer with the complete corrected template, in exactly the same format and rules as before: one <style> element followed by the <header>, <main> and <footer>, with the same data slots and links. Keep the concept, the colours and the fonts; change what the review found. Nothing else in the answer.

The template you wrote:
""";

def _when(starts_at: str, tz: str, today: str) -> tuple[str, str] {
    # ("18:15", "Today" or "Tomorrow" or "Tue 27 Oct") in the cinema's time zone.
    at = datetime.fromisoformat(starts_at).astimezone(ZoneInfo(tz));
    day = at.date().isoformat();
    label = "Today" if day == today else at.strftime("%a %-d %b");
    return (at.strftime("%H:%M"), label);
}

def _details(m: dict[str, any]) -> str {  # jac:ignore[W1037]
    parts: list[str] = [];
    if m.get("age_rating") {
        parts.append(str(m["age_rating"]));
    }
    minutes = int(m.get("runtime_minutes") or 0);
    if minutes {
        parts.append(
            f"{minutes // 60} h {minutes % 60:02d}"
                if minutes >= 60
                else f"{minutes} min"
        );
    }
    if m.get("genres") {
        parts.append(", ".join(m["genres"]));
    }
    return " · ".join(parts);
}

def programme_lists(home: dict[str, any], posters: dict[str, str]) -> dict[str, any] {  # jac:ignore[W1037]
    # The template's lists from public_home, as the storefront fills them; `posters`
    # are data URLs by movie key.
    tz: str = home["cinema"]["timezone"];
    today = datetime.now(ZoneInfo(tz)).date().isoformat();
    times: dict[str, list[dict[str, str]]] = {};
    today_list: list[dict[str, str]] = [];
    for s in home.get("showtimes", []) {
        (hour, day) = _when(s["starts_at"], tz, today);
        show = {
            "show.time": hour,
            "show.day": day,
            "show.screen": str((s.get("screen") or {}).get("name", "")),
            "show.film": str(s.get("title", ""))
        };
        times.setdefault(s.get("movie_key", ""), []).append(show);
        if day == "Today" {
            today_list.append(show);
        }
    }
    def film(m: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
        return {
            "film.title": str(m.get("title", "")),
            "film.details": _details(m),
            "film.synopsis": str(m.get("synopsis", "") or ""),
            "film.release": str(m.get("release_date", "") or ""),
            "_poster_url": posters.get(m.get("movie_key", ""), ""),
            "times": times.get(m.get("movie_key", ""), [])[:6]
        };
    }
    films = [film(m) for m in home.get("movies", [])[:FILMS_MAX]];
    soon: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for section in home.get("page", {}).get("sections", []) {
        if section.get("type") == "coming_soon" {
            soon = [film(m) for m in section.get("movies", [])[:FILMS_MAX]];
        }
    }
    if not today_list and films {
        # Nothing today: the next day's showtimes stand in, as the storefront's list does.
        today_list = [t for f in films for t in f["times"]][:8];
    }
    return {"featured": films[:1], "films": films, "today": today_list, "soon": soon};
}

def filled_document(
    page: dict[str, str],
    lists: dict[str, any],  # jac:ignore[W1037]
    cinema: str,
    logo_webp: bytes,
    motifs: list[str]
) -> str {
    # The written page filled with the programme, as one HTML document to screenshot.
    logo = f"data:image/webp;base64,{base64.b64encode(logo_webp).decode()}";
    return str(
        _document(page["html"], page["css"], lists, cinema, logo, motifs, FONTS)
    );
}

def _shoot_document(document: str) -> list[bytes] {
    try {
        found: any = _shoot(document, SIZES, SHOT_HEIGHT_MAX);  # jac:ignore[W1037]
    } except Exception as e {
        raise ReviewSkipped(f"no screenshots: {type(e).__name__}: {str(e)[:200]}");
    }
    return list(found);
}

# The screenshots and the model call; tests replace both, so no test opens a browser or
# touches the network.
glob shoot: any = _shoot_document,  # jac:ignore[W1037]
     ask: any = ask_text;  # jac:ignore[W1037]

def review_page(
    logo_webp: bytes,
    cinema: str,
    page: dict[str, str],
    lists: dict[str, any],  # jac:ignore[W1037]
    motifs: list[str],
    brand_text: str = ""
) -> dict[str, str] {
    # The page after Claude's review of its screenshots, or the page as it was when the
    # review can't run or its answer isn't a complete template. Never raises.
    scripted = os.environ.get(SCRIPT_ENV, "");
    if scripted and os.path.isfile(scripted) {
        return page;  # browser tests: the scripted page is the page
    }
    try {
        shots = shoot(filled_document(page, lists, cinema, logo_webp, motifs));
        template = f"<style>\n{page['css']}\n</style>\n{page['html']}";
        content = [image_block(logo_webp)]
            + [image_block(s, "image/jpeg") for s in shots]
            + [
                text_block(
                    REVIEW_BRIEF
                        + template
                        + ("\n\n" + brand_text if brand_text else "")
                )
            ];
        answer = ask(
            content, effort="high", max_tokens=MAX_OUTPUT_TOKENS, timeout=TIMEOUT
        );
    } except (ReviewSkipped, ClaudeFailed) as e {
        logger.warning("page review skipped: %s", str(e)[:300]);
        return page;
    }
    made = sanitize(answer);
    if made["problems"] {
        logger.warning(
            "reviewed page dropped: missing %s", ", ".join(made["problems"])
        );
        return page;
    }
    return {
        "html": made["html"],
        "css": made["css"],
        "model": page.get("model", ""),
        "reviewed": "yes"
    };
}

def _sample_poster(top: tuple[int, int, int], bottom: tuple[int, int, int]) -> str {
    # A plain 2:3 gradient standing in for a poster the cinema hasn't got.
    img = Image.new("RGB", (200, 300));
    for y in range(300) {
        t = y / 300;
        colour = (
            int(top[0] * (1 - t) + bottom[0] * t),
            int(top[1] * (1 - t) + bottom[1] * t),
            int(top[2] * (1 - t) + bottom[2] * t)
        );
        for x in range(200) {
            img.putpixel((x, y), colour);
        }
    }
    out = io.BytesIO();
    img.save(out, "WEBP", quality=60);
    return f"data:image/webp;base64,{base64.b64encode(out.getvalue()).decode()}";
}

def sample_lists -> dict[str, any] {  # jac:ignore[W1037]
    # A small sample programme, for a cinema that has published none yet: the page is
    # still reviewed against real-looking content, not empty sections.
    titles = [
        (
            "The Long Rains",
            "PG-13 · 2 h 04 · Drama",
            (201, 136, 58),
            (22, 12, 6),
            ["18:15", "20:30"]
        ),
        (
            "Nairobi Nights",
            "16 · 1 h 52 · Thriller",
            (47, 111, 143),
            (7, 13, 20),
            ["17:00", "21:10"]
        ),
        ("Matatu Run", "PG · 1 h 41 · Comedy", (143, 42, 42), (18, 7, 7), ["14:30"])
    ];
    films: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for (title, details, top, bottom, hours) in titles {
        films.append(
            {
                "film.title": title,
                "film.details": details,
                "film.synopsis": "A story told on the big screen.",
                "film.release": "",
                "_poster_url": _sample_poster(top, bottom),
                "times": [
                    {
                        "show.time": h,
                        "show.day": "Today",
                        "show.screen": "Screen 1",
                        "show.film": title
                    } for h in hours
                ]
            }
        );
    }
    return {
        "featured": films[:1],
        "films": films,
        "today": [t for f in films for t in f["times"]],
        "soon": []
    };
}
