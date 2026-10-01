"""P4.1b E2E: a cinema's home page, drawn from its published sections and template.

Pages are published through the API here (the back-office editor comes in P4.1b-b).
A cinema that hasn't published one shows the default Marquee page; switching template
changes the layout; hiding a section removes it; sections with nothing to show are left
out. Review screenshots of each template at 375, 768 and 1440 px, light and dark.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    context_options,
    artifact
}
import from e2e.support.api { call }
import from e2e.support.catalog { cinema_with_programme }

glob HOME: str = '[data-testid="home-page"]',
     SECTION_ORDER_JS: str = "[...document.querySelectorAll('[data-testid^=section-]')].map(e => e.dataset.testid.slice(8))",
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    'a[href], button, summary, input, select, textarea')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""",
     HEADINGS_JS: str = "[...document.querySelectorAll('h1,h2,h3,h4')].map(h => +h.tagName[1])";

def _sections(
    owner: dict[str, str], order: list[str], hidden: list[str] | None = None
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Every section filled in, in `order`, with `hidden` ones hidden.
    fields: dict[str, dict[str, any]] = {  # jac:ignore[W1037]
        "hero": {
            "headline": "Films worth the trip",
            "text": "Two screens in Westlands, open every day.",
            "movie_id": owner["rafiki"]
        },
        "today": {},
        "now_showing": {},
        "coming_soon": {"movie_ids": [owner["kati"]]},
        "about": {
            "title": "About Nova",
            "text": "A family-run cinema since 1998.\nFree parking for three hours."
        },
        "location": {
            "address": "Mwanzi Road, Westlands, Nairobi",
            "map_url": "https://maps.example.com/nova",
            "hours": [
                {"days": "Mon–Fri", "times": "12:00–23:00"},
                {"days": "Sat–Sun", "times": "10:00–23:30"}
            ]
        },
        "contact": {
            "phone": "+254 700 000 000",
            "email": "hello@nova.example",
            "links": [{"label": "Instagram", "url": "https://instagram.com/nova"}]
        },
        "faq": {
            "items": [
                {
                    "question": "Is there parking?",
                    "answer": "Yes, free for three hours."
                },
                {
                    "question": "Can I bring food?",
                    "answer": "Snacks from our café only."
                }
            ]
        }
    };
    return [
        {"type": kind, "visible": kind not in (hidden or []), "fields": fields[kind]}
        for kind in order
    ];
}

def _publish(owner: dict[str, str], template: str, sections: list[dict[str, any]]) {  # jac:ignore[W1037]
    saved = call(
        owner["token"],
        "save_home_page",
        {"tenant": owner["slug"], "page": {"template": template, "sections": sections}}
    );
    assert saved["ok"] , saved;
    published = call(owner["token"], "publish_home_page", {"tenant": owner["slug"]});
    assert published["ok"] , published;
}

def _open(page: any, slug: str) -> list[str] {  # jac:ignore[W1037]
    # The storefront's section types, in order, once the page has drawn.
    page.goto(f"{BASE_URL}/c/{slug}");
    page.wait_for_selector(HOME);
    page.wait_for_selector('[data-testid^="section-"]');
    return page.evaluate(SECTION_ORDER_JS);
}

glob ORDERS: dict[str, list[str]] = {
         "marquee": [
             "hero",
             "now_showing",
             "coming_soon",
             "today",
             "about",
             "location",
             "contact",
             "faq"
         ],
         "schedule": [
             "today",
             "now_showing",
             "coming_soon",
             "hero",
             "location",
             "about",
             "contact",
             "faq"
         ],
         "compact": [
             "now_showing",
             "today",
             "coming_soon",
             "location",
             "contact",
             "about",
             "faq",
             "hero"
         ]
     };

def _shown(template: str) -> list[str] {
    # The template's order without "today": the seeded showtimes are days ahead.
    return [
        k
        for k in ORDERS[template]
        if k != "today"
    ];
}

test "a cinema that hasn't published a page shows the default Marquee page" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        assert _open(page, owner["slug"]) == ["hero", "now_showing"];
        assert page.get_attribute(HOME, "data-template") == "marquee";
        assert "Rafiki" in page.inner_text('[data-testid="section-hero"]');
        page.click('[data-testid="hero-cta"]');
        page.wait_for_selector('[data-testid="movie-page"]');
    } finally {
        close_contexts(browser);
    }
}

test "switching template changes the storefront's layout, and hiding a section removes it" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        for template in ["marquee", "schedule", "compact"] {
            _publish(owner, template, _sections(owner, ORDERS[template]));
            assert _open(page, owner["slug"]) == _shown(template) , template;
            assert page.get_attribute(HOME, "data-template") == template;
        }
        width = page.evaluate(
            f"document.querySelector('{HOME}').getBoundingClientRect().width"
        );
        assert width <= 672 , f"Compact is a narrow column, not {width}px";
        _publish(
            owner,
            "marquee",
            _sections(owner, ORDERS["marquee"], hidden=["about", "faq"])
        );
        assert _open(page, owner["slug"])
            == ["hero", "now_showing", "coming_soon", "location", "contact"];
    } finally {
        close_contexts(browser);
    }
}

test "coming soon, location, contact and questions show what the cinema wrote" {
    owner = cinema_with_programme();
    _publish(owner, "marquee", _sections(owner, ORDERS["marquee"]));
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _open(page, owner["slug"]);
        assert "Kati Kati" in page.inner_text('[data-testid="section-coming_soon"]');
        about = page.inner_text('[data-testid="section-about"]');
        assert "About Nova" in about and "Free parking" in about;
        location = page.locator('[data-testid="section-location"]');
        assert location.locator(
            'a[href="https://maps.example.com/nova"]'
        ).get_attribute(
            "target"
        )
            == "_blank";
        assert "Sat–Sun" in location.inner_text();
        contact = page.locator('[data-testid="section-contact"]');
        assert contact.locator('a[href="tel:+254700000000"]').count() == 1;
        assert contact.locator('a[href="mailto:hello@nova.example"]').count() == 1;
        faq = page.locator('[data-testid="section-faq"]');
        assert not faq.locator("text=free for three hours").is_visible();
        faq.locator("summary", has_text="Is there parking?").click();
        assert faq.locator("text=free for three hours").is_visible();
    } finally {
        close_contexts(browser);
    }
}

test "every template passes the phone checks" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
        ).new_page();
        for template in ["marquee", "schedule", "compact"] {
            _publish(owner, template, _sections(owner, ORDERS[template]));
            _open(page, owner["slug"]);
            assert page.evaluate(OVERFLOW_JS) <= 0 , f"{template} scrolls sideways";
            assert page.evaluate(SMALL_TARGETS_JS) == [] , (
                template,
                page.evaluate(SMALL_TARGETS_JS)
            );
            levels = page.evaluate(HEADINGS_JS);
            assert levels.count(1) == 1 , (template, levels);
            assert all(b - a <= 1 for (a, b) in zip(levels, levels[1:])) , (
                template,
                levels
            );
            assert "jac:ignore" not in page.inner_text("body") , template;
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of each template" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        for template in ["marquee", "schedule", "compact"] {
            _publish(owner, template, _sections(owner, ORDERS[template]));
            for scheme in ["light", "dark"] {
                for width in [375, 768, 1440] {
                    page = browser.new_context(
                        viewport={"width": width, "height": 900},
                        color_scheme=scheme,
                        reduced_motion="reduce"
                    ).new_page();
                    _open(page, owner["slug"]);
                    page.evaluate("document.fonts.ready");
                    page.wait_for_timeout(300);
                    page.screenshot(
                        path=artifact(f"home-{template}-{width}-{scheme}.png"),
                        full_page=True
                    );
                    page.context.close();
                }
            }
        }
    } finally {
        close_contexts(browser);
    }
}
