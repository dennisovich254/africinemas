"""P4.1 E2E: browsing a cinema's storefront without an account.

`/c/{slug}` lists the movies on sale as cards (poster, details, next showtimes);
a movie's title leads to its page (`/c/{slug}/m/{movie_key}`), with its showtimes
grouped by day; a showtime leads to its page (`/c/{slug}/s/{screening_id}`). Back
works at every step, and a link to a movie or showtime that isn't on sale says so and
leads back to the cinema. The theme tests (e2e/branding_tests.jac) check the colours.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.catalog { cinema_with_programme }

glob STOREFRONT: str = '[data-testid="storefront"]',
     CARD: str = '[data-testid="movie-card"]',
     SHOWTIME: str = '[data-testid="showtime"]',
     MOVIE_PAGE: str = '[data-testid="movie-page"]',
     SCREENING_PAGE: str = '[data-testid="screening-page"]',
     MISSING: str = '[data-testid="storefront-missing"]',
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    'a[href], button, [role=button], input, select, textarea')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""",
     HEADINGS_JS: str = "[...document.querySelectorAll('h1,h2,h3,h4')].map(h => +h.tagName[1])",
     POSTER_LOADED_JS: str = "e => e.complete && e.naturalWidth > 0";

def _page(browser: any, pw: any, project: str, scheme: str = "light") -> any {  # jac:ignore[W1037]
    return browser.new_context(**context_options(pw, project, scheme)).new_page();
}

def _home(page: any, slug: str) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/c/{slug}");
    page.wait_for_selector(CARD);
}

test "a visitor goes from the movie list to a movie and one of its showtimes, and back" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            _home(page, owner["slug"]);
            cards = page.locator(CARD);
            assert cards.count() == 2;
            assert "Rafiki" in cards.nth(0).inner_text();
            assert "Supa Modo" in cards.nth(1).inner_text();
            # Rafiki has a poster; Supa Modo keeps the same space without one.
            page.wait_for_function(
                f"document.querySelector('{CARD} img') && ({POSTER_LOADED_JS})(document.querySelector('{CARD} img'))"
            );
            assert cards.nth(1).locator("img").count() == 0;
            assert cards.nth(0).locator(SHOWTIME).count() == 2;
            cards.nth(0).locator('a:has-text("Rafiki")').click();
            page.wait_for_selector(MOVIE_PAGE);
            assert "/m/" in page.url;
            assert "Two young women in Nairobi" in page.inner_text(MOVIE_PAGE);
            days = page.locator('[data-testid="showtime-day"]');
            assert days.count() == 2 , days.all_inner_texts();
            days.nth(0).locator(SHOWTIME).first.click();
            page.wait_for_selector(SCREENING_PAGE);
            assert page.url.endswith(f"/s/{owner['first']}");
            shown = page.inner_text(SCREENING_PAGE);
            for text in ["Rafiki", "Westgate", "Screen 1", "18:15"] {
                assert text in shown , f"{text} not in {shown}";
            }
            page.go_back();
            page.wait_for_selector(MOVIE_PAGE);
            page.go_back();
            page.wait_for_selector(CARD);
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a showtime on the movie list leads straight to it, and back to its movie" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        _home(page, owner["slug"]);
        page.locator(CARD).nth(0).locator(SHOWTIME).nth(1).click();
        page.wait_for_selector(SCREENING_PAGE);
        assert page.url.endswith(f"/s/{owner['second']}");
        page.click('[data-testid="back-to-movie"]');
        page.wait_for_selector(MOVIE_PAGE);
        page.click('[data-testid="back-to-cinema"]');
        page.wait_for_selector(CARD);
    } finally {
        close_contexts(browser);
    }
}

test "a link to a movie or showtime that isn't on sale says so and leads back" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        for path in ["m/no-such-movie", "s/no-such-showtime"] {
            page.goto(f"{BASE_URL}/c/{owner['slug']}/{path}");
            page.wait_for_selector(MISSING);
            assert "isn't on sale" in page.inner_text(MISSING);
            page.click('[data-testid="back-to-cinema"]');
            page.wait_for_selector(CARD);
        }
    } finally {
        close_contexts(browser);
    }
}

def _paths(owner: dict[str, str], page: any) -> list[tuple[str, str, str]] {  # jac:ignore[W1037]
    # (name, path, ready selector) for the three storefront pages.
    page.goto(f"{BASE_URL}/c/{owner['slug']}");
    page.wait_for_selector(CARD);
    movie = page.locator(CARD).nth(0).locator('a:has-text("Rafiki")').get_attribute(
        "href"
    );
    return [
        ("storefront-home", f"/c/{owner['slug']}", CARD),
        ("storefront-movie", movie, MOVIE_PAGE),
        (
            "storefront-showtime",
            f"/c/{owner['slug']}/s/{owner['first']}",
            SCREENING_PAGE
        )
    ];
}

test "the storefront pages pass the phone checks" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
        ).new_page();
        for (name, path, ready) in _paths(owner, page) {
            page.goto(BASE_URL + path);
            page.wait_for_selector(ready);
            assert page.evaluate(OVERFLOW_JS) <= 0 , f"{name} scrolls sideways";
            assert page.evaluate(SMALL_TARGETS_JS) == [] , (
                name,
                page.evaluate(SMALL_TARGETS_JS)
            );
            levels = page.evaluate(HEADINGS_JS);
            assert levels.count(1) == 1 , (name, levels);
            assert all(b - a <= 1 for (a, b) in zip(levels, levels[1:])) , (
                name,
                levels
            );
            assert "jac:ignore" not in page.inner_text("body") , name;
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the storefront pages" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        paths = _paths(owner, browser.new_page());
        for scheme in ["light", "dark"] {
            for width in [375, 768, 1440] {
                page = browser.new_context(
                    viewport={"width": width, "height": 900},
                    color_scheme=scheme,
                    reduced_motion="reduce"
                ).new_page();
                for (name, path, ready) in paths {
                    page.goto(BASE_URL + path);
                    page.wait_for_selector(ready);
                    page.evaluate("document.fonts.ready");
                    page.wait_for_timeout(300);
                    page.screenshot(
                        path=artifact(f"{name}-{width}-{scheme}.png"), full_page=True
                    );
                }
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
