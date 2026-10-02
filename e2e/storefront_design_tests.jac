"""P4.1c E2E: the storefront home design.

The date strip shows one day's showtimes at a time, grouped by movie; the hero puts the
featured movie on its backdrop with Book tickets; the header links jump to the page's
sections, with location, contact and questions together under Visit us. Layout and
screenshots of every template are in e2e/home_page_tests.jac.
"""

import io;
import base64;
import from PIL { Image }
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { call }
import from e2e.support.catalog { cinema_with_programme }

glob HOME: str = '[data-testid="home-page"]',
     DAY: str = '[data-testid="day-option"]',
     DAY_MOVIES_JS: str = "[...document.querySelectorAll('[data-testid=day-movie] h3')].map(h => h.innerText.trim())",
     IMAGE_SHOWN_JS: str = "s => { const i = document.querySelector(s); return !!i && i.complete && i.naturalWidth > 0; }";

def _page(browser: any, pw: any, project: str) -> any {  # jac:ignore[W1037]
    return browser.new_context(**context_options(pw, project, "dark")).new_page();
}

def _home(page: any, slug: str) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/c/{slug}");
    page.wait_for_selector(HOME);
    page.wait_for_selector('[data-testid^="section-"]');
}

def _backdrop(owner: dict[str, str], movie_id: str) {
    out = io.BytesIO();
    Image.new("RGB", (1280, 720), "#1D3557").save(out, format="PNG");
    answer = call(
        owner["token"],
        "upload_backdrop",
        {
            "tenant": owner["slug"],
            "movie_id": movie_id,
            "content_type": "image/png",
            "data_base64": base64.b64encode(out.getvalue()).decode()
        }
    );
    assert answer["ok"] , answer;
}

test "the date strip shows one day's showtimes at a time, grouped by movie" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            _home(page, owner["slug"]);
            days = page.locator(DAY);
            assert days.count() == 2;
            assert days.nth(0).get_attribute("aria-pressed") == "true";
            assert page.evaluate(DAY_MOVIES_JS) == ["Rafiki", "Supa Modo"];
            days.nth(1).click();
            page.wait_for_function(
                f"JSON.stringify({DAY_MOVIES_JS}) === JSON.stringify(['Rafiki'])"
            );
            assert days.nth(1).get_attribute("aria-pressed") == "true";
            assert "20:00" in page.inner_text('[data-testid="day-showtimes"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the hero puts the featured movie on its backdrop, and Book tickets leads to it" {
    owner = cinema_with_programme();
    _backdrop(owner, owner["rafiki"]);
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _home(page, owner["slug"]);
        hero_image = '[data-testid="section-hero"] img';
        page.wait_for_function(IMAGE_SHOWN_JS, arg=hero_image);
        # The real backdrop, not the blurred poster that stands in for one.
        assert "blur" not in (page.get_attribute(hero_image, "class") or "");
        page.click('[data-testid="hero-cta"]');
        page.wait_for_selector('[data-testid="movie-page"]');
        page.wait_for_function(IMAGE_SHOWN_JS, arg='[data-testid="movie-hero"] img');
    } finally {
        close_contexts(browser);
    }
}

test "the header links jump to the page's sections, with Visit us together" {
    owner = cinema_with_programme();
    sections = [
        {"type": "hero", "visible": True, "fields": {}},
        {"type": "today", "visible": True, "fields": {}},
        {"type": "now_showing", "visible": True, "fields": {}},
        {
            "type": "coming_soon",
            "visible": True,
            "fields": {"movie_ids": [owner["kati"]]}
        },
        {
            "type": "location",
            "visible": True,
            "fields": {"address": "Mwanzi Road, Westlands"}
        },
        {"type": "contact", "visible": True, "fields": {"phone": "+254 700 000 000"}},
        {
            "type": "faq",
            "visible": True,
            "fields": {"items": [{"question": "Parking?", "answer": "Free."}]}
        }
    ];
    saved = call(
        owner["token"],
        "save_home_page",
        {"tenant": owner["slug"], "page": {"template": "marquee", "sections": sections}}
    );
    assert saved["ok"] , saved;
    assert call(owner["token"], "publish_home_page", {"tenant": owner["slug"]})["ok"];
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        _home(page, owner["slug"]);
        nav = page.locator("header nav a");
        assert nav.all_inner_texts() == ["What's on", "Coming soon", "Visit us"];
        band = page.locator('[data-testid="visit-us"]');
        for kind in ["location", "contact", "faq"] {
            assert band.locator(f'[data-testid="section-{kind}"]').count() == 1 , kind;
        }
        page.click('header nav a:has-text("Visit us")');
        page.wait_for_function("location.hash === '#visit-us'");
        page.wait_for_function(
            "(() => { const r = document.querySelector('[data-testid=visit-us]').getBoundingClientRect(); return r.top >= 0 && r.top < innerHeight; })()"
        );
        assert "Kati Kati" in page.inner_text('[data-testid="section-coming_soon"]');
    } finally {
        close_contexts(browser);
    }
}
