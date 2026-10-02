"""P4.1d E2E: the storefront's structure, from finding a movie to its showtime.

Search finds movies and venues and says when nothing matches; the venue picker narrows
the page and is remembered; a time in What's on opens its showtime; genre chips narrow
What's on and the Movies page; the phone menu works by keyboard; the Movies and Cinemas pages list what's
on and where. Phone checks and review screenshots of the new pages.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call, add_venue, add_screen }
import from e2e.support.catalog { cinema_with_programme, publish_showing, day_ahead }

glob HOME: str = '[data-testid="home-page"]',
     CARD_TITLES_JS: str = "[...document.querySelectorAll('[data-testid=section-now_showing] [data-testid=movie-card] h3')].map(h => h.innerText.trim())",
     DAY_TITLES_JS: str = "[...document.querySelectorAll('[data-testid=day-movie] h3')].map(h => h.innerText.trim())",
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    'a[href], button, summary, select, input')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""",
     HEADINGS_JS: str = "[...document.querySelectorAll('h1,h2,h3,h4')].map(h => +h.tagName[1])";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _page(browser: any, pw: any, project: str) -> any {  # jac:ignore[W1037]
    return browser.new_context(**context_options(pw, project, "light")).new_page();
}

def _home(page: any, slug: str) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/c/{slug}");
    page.wait_for_selector(HOME);
    page.wait_for_selector('[data-testid="section-today"]');
}

def _two_venues -> dict[str, str] {
    # The usual cinema, plus a CBD venue showing Supa Modo, and Supa Modo as Family.
    owner = cinema_with_programme();
    cbd = add_venue(owner, "CBD");
    hall = add_screen(owner, cbd, "Hall A");
    assert call(
        owner["token"],
        "save_layout",
        {
            "tenant": owner["slug"],
            "auditorium_id": hall,
            "rows": 1,
            "cols": 2,
            "seats": [
                {"label": "A1", "row": 0, "col": 0},
                {"label": "A2", "row": 0, "col": 1}
            ]
        }
    )["ok"];
    assert call(
        owner["token"],
        "publish_layout",
        {"tenant": owner["slug"], "auditorium_id": hall}
    )["ok"];
    supa = [
        m
        for m in call(owner["token"], "list_movies", {"tenant": owner["slug"]})[
            "movies"
        ]
        if m["title"] == "Supa Modo"
    ][0];
    assert call(
        owner["token"],
        "update_movie",
        {
            "tenant": owner["slug"],
            "movie_id": supa["movie_id"],
            "title": supa["title"],
            "synopsis": supa["synopsis"],
            "runtime_minutes": supa["runtime_minutes"],
            "age_rating": "PG",
            "genres": ["Family"],
            "language": "Swahili"
        }
    )["ok"];
    owner["screen"] = hall;
    owner["cbd_show"] = publish_showing(owner, supa["movie_id"], day_ahead(2), "15:00");
    return owner;
}

test "search finds a movie and a cinema, and says when nothing matches" {
    owner = _two_venues();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            _home(page, owner["slug"]);
            page.click('[data-testid="search-button"]');
            page.wait_for_selector('[data-testid="search-panel"]');
            _type(page, "#storefront-search", "rafi");
            page.wait_for_selector(
                '[data-testid="search-results"] a:has-text("Rafiki")'
            );
            _type(page, "#storefront-search", "cbd");
            page.wait_for_selector('[data-testid="search-results"] a:has-text("CBD")');
            _type(page, "#storefront-search", "zzz");
            page.wait_for_selector('[data-testid="search-empty"]');
            _type(page, "#storefront-search", "rafiki");
            page.click('[data-testid="search-results"] a:has-text("Rafiki")');
            page.wait_for_selector('[data-testid="movie-page"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the venue picker narrows the page, and is remembered" {
    owner = _two_venues();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(viewport={"width": 1440, "height": 900}).new_page();
        _home(page, owner["slug"]);
        page.select_option('[data-testid="venue-picker"]', "CBD");
        page.wait_for_function(
            f"JSON.stringify({CARD_TITLES_JS}) === JSON.stringify(['Supa Modo'])"
        );
        assert page.evaluate(DAY_TITLES_JS) == ["Supa Modo"];
        page.reload();
        page.wait_for_selector(HOME);
        page.wait_for_function(
            "document.querySelector('[data-testid=venue-picker]') && document.querySelector('[data-testid=venue-picker]').value === 'CBD'"
        );
        assert page.evaluate(CARD_TITLES_JS) == ["Supa Modo"];
        page.select_option('[data-testid="venue-picker"]', "");
        page.wait_for_function(f"{CARD_TITLES_JS}.length === 2");
    } finally {
        close_contexts(browser);
    }
}

test "tapping a time in What's on opens that showtime" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            _home(page, owner["slug"]);
            assert page.locator('[data-testid="quick-book"]').count() == 0;
            page.locator(
                '[data-testid="day-showtimes"] [data-testid="showtime"]'
            ).first.click();
            page.wait_for_selector('[data-testid="screening-page"]');
            assert page.url.endswith(f"/s/{owner['first']}") , page.url;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "genre chips narrow What's on and the Movies page" {
    owner = _two_venues();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        _home(page, owner["slug"]);
        chips = page.locator('[data-testid="genre-chips"] button');
        assert chips.all_inner_texts() == ["All", "Drama", "Family"];
        chips.nth(2).click();
        page.wait_for_function(
            f"JSON.stringify({DAY_TITLES_JS}) === JSON.stringify(['Supa Modo'])"
        );
        assert chips.nth(2).get_attribute("aria-pressed") == "true";
        chips.nth(0).click();
        page.wait_for_function(f"{DAY_TITLES_JS}.length === 2");
        page.goto(f"{BASE_URL}/c/{owner['slug']}/movies");
        page.wait_for_selector('[data-testid="movie-genre-chips"]');
        page.click('[data-testid="movie-genre-chips"] button:has-text("Family")');
        page.wait_for_function(
            "JSON.stringify([...document.querySelectorAll('[data-testid=movie-card] h3')].map(h => h.innerText.trim())) === JSON.stringify(['Supa Modo'])"
        );
    } finally {
        close_contexts(browser);
    }
}

test "the phone menu opens and closes by keyboard, with the venue picker inside" {
    owner = _two_venues();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        _home(page, owner["slug"]);
        page.focus('[data-testid="storefront-menu"]');
        page.keyboard.press("Enter");
        page.wait_for_selector('[data-testid="storefront-menu-sheet"]');
        sheet = page.locator('[data-testid="storefront-menu-sheet"]');
        assert sheet.locator("a").all_inner_texts()
            == ["Movies", "Showtimes", "Cinemas"];
        assert sheet.locator('[data-testid="venue-picker-menu"]').count() == 1;
        page.keyboard.press("Escape");
        page.wait_for_selector(
            '[data-testid="storefront-menu-sheet"]', state="detached"
        );
        assert page.evaluate("document.activeElement.dataset.testid")
            == "storefront-menu";
    } finally {
        close_contexts(browser);
    }
}

test "the Movies and Cinemas pages list what's on and where" {
    owner = _two_venues();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        page.goto(f"{BASE_URL}/c/{owner['slug']}/movies");
        page.wait_for_selector(
            '[data-testid="movies-page"] [data-testid="movie-card"]'
        );
        assert page.locator('[data-testid="movie-card"]').count() == 2;
        assert "Movies ·" in page.title();
        page.goto(f"{BASE_URL}/c/{owner['slug']}/cinemas");
        page.wait_for_selector('[data-testid="venue-card"]');
        cards = page.locator('[data-testid="venue-card"]');
        assert cards.count() == 2;
        assert "CBD" in cards.nth(0).inner_text();
        cards.nth(0).locator('button:has-text("See what\'s on")').click();
        page.wait_for_selector(HOME);
        page.wait_for_function(
            f"JSON.stringify({DAY_TITLES_JS}) === JSON.stringify(['Supa Modo'])"
        );
    } finally {
        close_contexts(browser);
    }
}

test "the new pages pass the phone checks" {
    owner = _two_venues();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
        ).new_page();
        for (path, ready) in [
            ("", '[data-testid="section-today"]'),
            ("/movies", '[data-testid="movies-page"] [data-testid="movie-card"]'),
            ("/cinemas", '[data-testid="venue-card"]')
        ] {
            page.goto(f"{BASE_URL}/c/{owner['slug']}{path}");
            page.wait_for_selector(ready);
            assert page.evaluate(OVERFLOW_JS) <= 0 , f"{path or '/'} scrolls sideways";
            assert page.evaluate(SMALL_TARGETS_JS) == [] , (
                path,
                page.evaluate(SMALL_TARGETS_JS)
            );
            levels = page.evaluate(HEADINGS_JS);
            assert levels.count(1) == 1 , (path, levels);
            assert all(b - a <= 1 for (a, b) in zip(levels, levels[1:])) , (
                path,
                levels
            );
            assert "jac:ignore" not in page.inner_text("body") , path;
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the storefront structure" {
    owner = _two_venues();
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for width in [375, 768, 1440] {
                page = browser.new_context(
                    viewport={"width": width, "height": 900},
                    color_scheme=scheme,
                    reduced_motion="reduce"
                ).new_page();
                for (name, path, ready) in [
                    ("home", "", '[data-testid="section-today"]'),
                    ("movies", "/movies", '[data-testid="movie-card"]'),
                    ("cinemas", "/cinemas", '[data-testid="venue-card"]')
                ] {
                    page.goto(f"{BASE_URL}/c/{owner['slug']}{path}");
                    page.wait_for_selector(ready);
                    page.evaluate("document.fonts.ready");
                    page.wait_for_timeout(300);
                    page.screenshot(
                        path=artifact(f"structure-{name}-{width}-{scheme}.png"),
                        full_page=True
                    );
                }
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}

test "the full-width hero shows the featured movie under a see-through header" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            _home(page, owner["slug"]);
            hero = page.locator('[data-testid="section-hero"]');
            header = page.locator('[data-testid="storefront-header"]');
            assert header.get_attribute("data-over-hero") == "true";
            assert "Rafiki" in hero.locator("h2").inner_text();
            # Nothing laid over the picture but the words: no thumbnails or arrows.
            assert hero.locator("li, [aria-label='Next movie']").count() == 0;
            assert hero.locator('[data-testid="hero-cta"]').is_visible();
            page.mouse.wheel(0, 600);
            page.wait_for_function(
                "document.querySelector('[data-testid=storefront-header]').dataset.overHero === 'false'"
            );
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
