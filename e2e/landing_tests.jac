"""P3.9 E2E: the AfriCinemas landing page at `/`.

The page cinema owners (and hackathon judges) see first: a hero over a looping cinema
video, three steps with examples of the product, and a closing call. "Create your
cinema" leads to sign-up, "See how it works" to the steps and "Sign in" to sign-in;
signed-in staff get a link to their cinemas instead. The video stays still for "reduce
motion" and can be paused. The theme tests (e2e/theme_tests.jac) check colours and fonts.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { PASSWORD, owner_with_cinema }

glob LANDING: str = '[data-testid="landing"]',
     CTA: str = '[data-testid="primary-cta"]',
     SECONDARY: str = '[data-testid="secondary-cta"]',
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    'a[href], button, [role=button], input, select, textarea')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1
      && getComputedStyle(e).visibility !== 'hidden'; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.id || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""",
     HEADINGS_JS: str = "[...document.querySelectorAll('h1,h2,h3,h4')].map(h => +h.tagName[1])";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _open(browser: any, pw: any, project: str, scheme: str = "light") -> any {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, scheme)).new_page();
    page.goto(BASE_URL + "/");
    page.wait_for_selector(LANDING);
    return page;
}

test "the landing page says what AfriCinemas does and how it works" {
    (pw, browser) = shared_browser();
    try {
        page = _open(browser, pw, "desktop");
        # The value first: what a cinema owner gets, and who it's for.
        assert "fill more seats" in page.inner_text("h1").lower();
        assert "cinema owners" in page.inner_text("header").lower();
        steps = page.locator('[data-testid="how-it-works"] > li').all_inner_texts();
        assert len(steps) == 3 , steps;
        for (step, word) in zip(steps, ["screenings", "M-Pesa", "door"]) {
            assert word.lower() in step.lower() , f"{word} not in {step}";
        }
        assert page.locator('[data-testid="audience"] li').count() == 3;
        video = page.locator('[data-testid="hall-video"]');
        for attr in ["loop", "playsinline", "poster"] {
            assert video.get_attribute(attr) is not None , attr;
        }
        # React sets muted as a property, not an attribute.
        assert page.evaluate(
            "document.querySelector('[data-testid=hall-video]').muted"
        );
        assert video.locator("source").count() == 2;
    } finally {
        close_contexts(browser);
    }
}

test "Create your cinema leads to sign-up, and Sign in to sign-in" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _open(browser, pw, project);
            assert "Create your cinema" in page.inner_text(CTA);
            page.click(SECONDARY);
            page.wait_for_url("**/#how");
            page.click(CTA);
            page.wait_for_url("**/signup");
            page.goto(BASE_URL + "/");
            page.wait_for_selector(LANDING);
            page.click('nav a[href="/login"]');
            page.wait_for_url("**/login");
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "signed-in staff still see the page, with a link to their cinemas" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        page.goto(BASE_URL + "/login");
        _type(page, "#email", owner["email"]);
        _type(page, "#password", PASSWORD);
        page.click('button[type="submit"]');
        page.wait_for_url("**/app");
        page.goto(BASE_URL + "/");
        page.wait_for_selector(LANDING);
        assert page.locator('a[href="/login"]').count() == 0 , "no sign-in link when signed in";
        page.click('a:has-text("Your cinemas")');
        page.wait_for_url("**/app");
    } finally {
        close_contexts(browser);
    }
}

test "the hero video plays, can be paused, and stays still for reduce motion" {
    (pw, browser) = shared_browser();
    try {
        page = _open(browser, pw, "desktop", "dark");
        page.wait_for_function(
            "!document.querySelector('[data-testid=hall-video]').paused"
        );
        page.click('[data-testid="hall-pause"]');
        assert page.evaluate(
            "document.querySelector('[data-testid=hall-video]').paused"
        );
        assert page.get_attribute('[data-testid="hall-pause"]', "aria-label")
            == "Play background video";
        still = browser.new_context(
            viewport={"width": 1440, "height": 900}, reduced_motion="reduce"
        ).new_page();
        still.goto(BASE_URL + "/");
        still.wait_for_selector(LANDING);
        still.wait_for_timeout(800);
        assert still.evaluate(
            "document.querySelector('[data-testid=hall-video]').paused"
        ) , "the video played despite reduce motion";
    } finally {
        close_contexts(browser);
    }
}

test "the landing page passes the phone checks" {
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
        ).new_page();
        page.goto(BASE_URL + "/");
        page.wait_for_selector(LANDING);
        assert page.evaluate(OVERFLOW_JS) <= 0 , "the page scrolls sideways at 375 px";
        assert page.evaluate(SMALL_TARGETS_JS) == [] , page.evaluate(SMALL_TARGETS_JS);
        levels = page.evaluate(HEADINGS_JS);
        assert levels.count(1) == 1 , levels;
        assert all(b - a <= 1 for (a, b) in zip(levels, levels[1:])) , levels;
        assert "jac:ignore" not in page.inner_text("body");
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the landing page" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for width in [375, 768, 1440] {
                # Reduced motion: the poster frame and no fade, so every shot is settled.
                page = browser.new_context(
                    viewport={"width": width, "height": 900},
                    color_scheme=scheme,
                    reduced_motion="reduce"
                ).new_page();
                page.goto(BASE_URL + "/");
                page.wait_for_selector(LANDING);
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"landing-{width}-{scheme}.png"), full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
