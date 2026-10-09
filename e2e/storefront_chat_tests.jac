"""P8.4 E2E: a cinema's chat on its storefront, and trailers on the movie page.

The server answers from a script these tests write (AFRICINEMAS_AGENT_SCRIPT, set by
scripts/e2e_env.sh): no model, no key. A visitor opens "Ask <cinema>", taps a suggestion
and gets the reply with the programme and a movie card, plays the trailer inside the
chat, and follows a time to its showtime page (which has no chat button: its seat bar is
fixed to the bottom). Back on the storefront, the conversation is still there. A reply
naming a showtime no tool returned adds no card. Phone and PC, light and dark
(screenshots for review); the movie page plays the trailer too.
"""

import os;
import json;
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call }
import from e2e.support.catalog { cinema_with_programme }

glob SCRIPT_ENV: str = "AFRICINEMAS_AGENT_SCRIPT",
     PANEL: str = '[data-testid="chat-panel"]',
     TRAILER: str = "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    '[data-testid=chat-panel] a[href], [data-testid=chat-panel] button, [data-testid=chat-panel] input')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.h < 44)""";

def _script(steps: list[any]) {  # jac:ignore[W1037]
    # The model's next answers, for the server to use (scripts/e2e_env.sh).
    path = os.environ[SCRIPT_ENV];
    os.makedirs(os.path.dirname(path), exist_ok=True);
    with open(path, "w") as f {
        json.dump(steps, f);
    }
}

def _cinema -> dict[str, str] {
    # Rafiki (poster, YouTube trailer) and Supa Modo on sale, and Rafiki's movie key.
    owner = cinema_with_programme();
    assert call(
        owner["token"],
        "set_trailer",
        {
            "tenant": owner["slug"],
            "movie_id": owner["rafiki"],
            "url": "https://youtu.be/dQw4w9WgXcQ"
        }
    )["ok"];
    shown = call("", "public_screenings", {"slug": owner["slug"]})["screenings"];
    owner["rafiki_key"] = [
        s["movie"]["movie_key"]
        for s in shown
        if s["movie"]["title"] == "Rafiki"
    ][0];
    return owner;
}

test "a visitor asks the cinema's chat and gets the programme, a movie and its trailer" {
    (pw, browser) = shared_browser();
    try {
        owner = _cinema();
        slug = owner["slug"];
        for project in PROJECTS {
            for scheme in ["light", "dark"] {
                page = browser.new_context(
                    **context_options(pw, project, scheme)
                ).new_page();
                page.goto(f"{BASE_URL}/c/{slug}");
                page.click('[data-testid="chat-open"]');
                page.wait_for_selector(PANEL);
                assert page.locator('[data-testid="chat-suggestion"]').count() == 3;
                _script(
                    [
                        {"tool": "whats_on", "args": {"cinema": slug, "day": ""}},
                        {
                            "tool": "movie_details",
                            "args": {"cinema": slug, "movie_key": owner["rafiki_key"]}
                        },
                        "Rafiki and Supa Modo are on. Here's Rafiki."
                    ]
                );
                page.click('[data-testid="chat-suggestion"] >> nth=0');
                page.wait_for_selector('[data-testid="chat-movie"]');
                log = page.inner_text('[data-testid="chat-log"]');
                assert "What's on tonight?" in log and "Here's Rafiki." in log , log;
                programme = page.inner_text('[data-testid="chat-programme"]');
                assert "Rafiki" in programme and "Supa Modo" in programme , programme;
                assert page.locator('[data-testid="chat-showtime"]').count() >= 3;
                page.click('[data-testid="chat-movie"] [data-testid="play-trailer"]');
                frame = page.wait_for_selector('[data-testid="trailer"] iframe');
                assert frame.get_attribute("src").startswith(TRAILER);
                assert page.evaluate(OVERFLOW_JS) <= 0 , f"{project}: scrolls sideways";
                small = page.evaluate(SMALL_TARGETS_JS);
                assert small == [] , f"{project}: small targets {small}";
                page.screenshot(
                    path=artifact(f"chat-{project}-{scheme}.png"), full_page=False
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}

test "a made-up showtime adds no card, and the conversation outlives a page change" {
    (pw, browser) = shared_browser();
    try {
        owner = _cinema();
        slug = owner["slug"];
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        page.goto(f"{BASE_URL}/c/{slug}");
        page.click('[data-testid="chat-open"]');
        _script(
            [{"tool": "whats_on", "args": {"cinema": slug, "day": ""}}, "Here you go."]
        );
        page.fill('[data-testid="chat-input"]', "What's on?");  # jac:ignore[W6002]
        page.click('[data-testid="chat-send"]');
        page.wait_for_selector('[data-testid="chat-programme"]');
        # Words only, naming a time no tool returned: no new card.
        _script(["Rafiki is also on at 23:59."]);
        page.fill('[data-testid="chat-input"]', "Any later show?");  # jac:ignore[W6002]
        page.click('[data-testid="chat-send"]');
        page.wait_for_function(
            "() => document.querySelectorAll('[data-testid=chat-reply]').length === 2"
        );
        assert page.locator('[data-testid="chat-programme"]').count() == 1;
        assert page.locator('[data-testid="chat-movie"]').count() == 0;
        # A time leads to its showtime page, which has no chat button.
        page.click('[data-testid="chat-showtime"] >> nth=0');
        page.wait_for_selector('[data-testid="screening-page"]');
        assert page.locator('[data-testid="chat-open"]').count() == 0;
        # Back on the storefront, the conversation is still there.
        page.goto(f"{BASE_URL}/c/{slug}");
        page.click('[data-testid="chat-open"]');
        page.wait_for_selector('[data-testid="chat-programme"]');
        assert page.locator('[data-testid="chat-mine"]').count() == 2;
    } finally {
        close_contexts(browser);
    }
}

test "the movie page plays the trailer when asked" {
    (pw, browser) = shared_browser();
    try {
        owner = _cinema();
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        page.goto(f"{BASE_URL}/c/{owner['slug']}/m/{owner['rafiki_key']}");
        page.wait_for_selector('[data-testid="movie-page"]');
        # Nothing loads from YouTube until the visitor presses play.
        assert page.locator('[data-testid="trailer"]').count() == 0;
        page.click('[data-testid="play-trailer"]');
        frame = page.wait_for_selector('[data-testid="trailer"] iframe');
        assert frame.get_attribute("src").startswith(TRAILER);
        page.screenshot(path=artifact("movie-trailer-desktop.png"), full_page=False);
    } finally {
        close_contexts(browser);
    }
}
