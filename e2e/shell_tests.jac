"""P0.8c E2E: the responsive shell (AppShell, BottomActionBar, ResponsiveTable) on a phone
and a desktop, exercised through the living style guide at /design-system (ADR-0002).

Expected colours come from the theme tokens, never hard-coded values.
"""

import from playwright.sync_api { sync_playwright }
import from core.theming.tokens { DEFAULT_THEME }
import from core.theming.css { BACKOFFICE_THEME }
import from e2e.support.web {
    BASE_URL,
    PROJECTS,
    context_options,
    hex_to_rgb,
    computed,
    artifact
}

glob GUIDE: str = BASE_URL + "/design-system",
     SIDEBAR: str = '[data-testid="shell-sidebar"]',
     MENU: str = '[data-testid="shell-menu-button"]',
     DRAWER: str = '[data-testid="shell-drawer"]',
     TITLE: str = '[data-testid="shell-title"]',
     BAR: str = '[data-testid="bottom-action-bar"]',
     TABLE: str = '[data-testid="responsive-table"] table',
     CARDS: str = '[data-testid="responsive-table-cards"]',
     SURFACE: str = "[data-surface]",
     # Every control a finger or keyboard can reach, skipping visually hidden ones (sr-only).
     SMALL_TARGETS_JS: str = """scope => [...document.querySelectorAll(
    `${scope} a[href], ${scope} button, ${scope} [role=button], ${scope} input, ${scope} select`)]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1
      && getComputedStyle(e).visibility !== 'hidden'; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""";

def _open(
    browser: any, pw: any, project: str, scheme: str = "light", path: str = ""
) -> any {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, scheme)).new_page();
    page.goto(GUIDE + path);
    page.wait_for_selector(TITLE);
    if scheme == "dark" {
        page.wait_for_function("document.documentElement.classList.contains('dark')");
    }
    return page;
}

def _visible(page: any, selector: str) -> bool {  # jac:ignore[W1037]
    return page.locator(selector).first.is_visible();
}

test "desktop shows the sidebar, a phone shows a menu button instead" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for project in PROJECTS {
                page = _open(browser, pw, project);
                on_desktop = project == "desktop";
                assert _visible(page, SIDEBAR) == on_desktop , f"{project}: sidebar visibility";
                assert _visible(page, MENU) != on_desktop , f"{project}: menu button visibility";
                page.context.close();
            }
        } finally {
            browser.close();
        }
    }
}

test "the phone drawer opens, closes with Escape and returns focus" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = _open(browser, pw, "mobile");
            page.click(MENU);
            page.wait_for_selector(DRAWER, state="visible");
            assert page.locator(DRAWER).get_attribute("role") == "dialog";
            assert page.locator(f"{DRAWER} nav a").count() >= 3 , "drawer lists the navigation";
            page.keyboard.press("Escape");
            page.wait_for_selector(DRAWER, state="hidden");
            # Radix restores focus just after the drawer unmounts (a 0 ms timer), so wait for it.
            page.wait_for_function(
                "document.activeElement?.getAttribute('data-testid') === 'shell-menu-button'",
                timeout=2000
            );
        } finally {
            browser.close();
        }
    }
}

test "navigating from the drawer changes page without a reload and closes it" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = _open(browser, pw, "mobile");
            page.evaluate("window.__noReload = true");
            page.click(MENU);
            page.wait_for_selector(DRAWER, state="visible");
            page.click(f'{DRAWER} a:has-text("Screenings")');
            page.wait_for_url("**/design-system/screenings");
            page.wait_for_selector(DRAWER, state="hidden");
            assert page.locator(TITLE).inner_text().strip() == "Screenings";
            assert page.evaluate("window.__noReload === true") , "client-side navigation, no full reload";
        } finally {
            browser.close();
        }
    }
}

test "the sidebar marks the current page" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = _open(browser, pw, "desktop", path="/staff");
            current = page.locator(f'{SIDEBAR} a[aria-current="page"]');
            assert current.count() == 1;
            assert current.inner_text().strip() == "Staff";
            assert page.locator(TITLE).inner_text().strip() == "Staff";
        } finally {
            browser.close();
        }
    }
}

test "the bottom action bar stays in view and never covers the content" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for project in PROJECTS {
                page = _open(browser, pw, project);
                for where in ["0", "document.documentElement.scrollHeight / 2"] {
                    page.evaluate(f"window.scrollTo(0, {where})");
                    box = page.locator(BAR).evaluate(
                        "e => { const r = e.getBoundingClientRect(); return [r.top, r.bottom, innerHeight]; }"
                    );
                    assert box[0] >= 0 and box[1] <= box[2] + 1 , f"{project}: bar out of view at scroll {where}: {box}";
                }
                page.evaluate(
                    "window.scrollTo(0, document.documentElement.scrollHeight)"
                );
                gap = page.evaluate(
                    """() => {
                      const bar = document.querySelector('[data-testid="bottom-action-bar"]').getBoundingClientRect();
                      const last = document.querySelector('[data-testid="guide-end"]').getBoundingClientRect();
                      return bar.top - last.bottom; }"""
                );
                assert gap >= 0 , f"{project}: the bar covers the end of the content by {-gap}px";
                page.context.close();
            }
        } finally {
            browser.close();
        }
    }
}

test "the table becomes cards below the md breakpoint" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for (width, want_table) in [
                (1440, True),
                (768, True),
                (767, False),
                (375, False)
            ] {
                page = browser.new_context(
                    viewport={"width": width, "height": 900}
                ).new_page();
                page.goto(GUIDE);
                page.wait_for_selector(TITLE);
                assert _visible(page, TABLE) == want_table , f"{width}px: table visibility";
                assert _visible(page, CARDS) != want_table , f"{width}px: cards visibility";
                if not want_table {
                    headers = page.locator(f"{TABLE} th").all_inner_texts();
                    labels = page.locator(f"{CARDS} li").first.locator(
                        "dt"
                    ).all_inner_texts();
                    assert [h.strip() for h in headers]
                        == [l.strip() for l in labels] , "each card labels every column";
                    assert page.locator(f"{CARDS} li").count()
                        == page.locator(f"{TABLE} tbody tr").count();
                }
                page.context.close();
            }
        } finally {
            browser.close();
        }
    }
}

test "every visible control on a phone is at least 44 x 44 px" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = _open(browser, pw, "mobile");
            small = page.evaluate(SMALL_TARGETS_JS, "body");
            assert small == [] , f"tap targets under 44px: {small}";
            page.click(MENU);
            page.wait_for_selector(DRAWER, state="visible");
            small = page.evaluate(SMALL_TARGETS_JS, DRAWER);
            assert small == [] , f"drawer tap targets under 44px: {small}";
        } finally {
            browser.close();
        }
    }
}

test "keyboard focus is visible in the theme's focus-ring colour" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for scheme in ["light", "dark"] {
                page = _open(browser, pw, "desktop", scheme);
                tokens = BACKOFFICE_THEME.dark
                    if scheme == "dark"
                    else BACKOFFICE_THEME.light;
                page.keyboard.press("Tab");
                first = page.evaluate("document.activeElement.textContent.trim()");
                assert first == "Skip to content" , f"first tab stop is {first!r}";
                assert page.evaluate(
                    "document.activeElement.getBoundingClientRect().width"
                )
                    > 1 , "the skip link becomes visible when focused";
                for _ in range(6) {
                    # Finish colour transitions first so the settled ring colour is read.
                    ring = page.evaluate(
                        """() => { document.activeElement.getAnimations().forEach(a => a.finish());
                          const s = getComputedStyle(document.activeElement);
                          return [document.activeElement.textContent.trim().slice(0, 30),
                                  s.outlineStyle, s.outlineColor, parseFloat(s.outlineWidth)]; }"""
                    );
                    assert ring[1] != "none" and ring[3] >= 2 , f"{scheme}: no visible focus on {ring[
                        0
                    ]!r}: {ring}";
                    assert ring[2] == hex_to_rgb(tokens.focus_ring) , f"{scheme}: focus ring on {ring[
                        0
                    ]!r} is {ring[2]}";
                    page.keyboard.press("Tab");
                }
                page.context.close();
            }
        } finally {
            browser.close();
        }
    }
}

test "no sideways scroll on a 375 px phone, drawer open or closed" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = browser.new_context(
                viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
            ).new_page();
            page.goto(GUIDE);
            page.wait_for_selector(TITLE);
            overflow_js = "document.documentElement.scrollWidth - document.documentElement.clientWidth";
            assert page.evaluate(overflow_js) <= 0 , "page scrolls sideways at 375px";
            page.click(MENU);
            page.wait_for_selector(DRAWER, state="visible");
            assert page.evaluate(overflow_js) <= 0 , "open drawer scrolls sideways at 375px";
        } finally {
            browser.close();
        }
    }
}

test "the guide renders the back-office and storefront themes in both modes" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for scheme in ["light", "dark"] {
                for (query, theme) in [
                    ("", BACKOFFICE_THEME),
                    ("?surface=storefront", DEFAULT_THEME)
                ] {
                    page = _open(browser, pw, "desktop", scheme, query);
                    tokens = theme.dark if scheme == "dark" else theme.light;
                    where = f"{scheme}{query or ' back-office'}";
                    assert computed(page, SURFACE, "background-color")
                        == hex_to_rgb(tokens.background) , f"{where}: page background";
                    assert computed(page, SIDEBAR, "background-color")
                        == hex_to_rgb(tokens.surface) , f"{where}: sidebar";
                    assert computed(page, f"{BAR} button", "background-color")
                        == hex_to_rgb(tokens.accent) , f"{where}: primary action";
                    page.context.close();
                }
            }
        } finally {
            browser.close();
        }
    }
}

test "unknown paths show a not-found page with a way home" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = browser.new_context(
                **context_options(pw, "mobile", "light")
            ).new_page();
            page.goto(BASE_URL + "/no-such-page");
            page.wait_for_selector('[data-testid="not-found"]');
            page.click('[data-testid="not-found"] a');
            page.wait_for_selector('[data-testid="welcome-card"]');
        } finally {
            browser.close();
        }
    }
}

test "review screenshots of the shell at 375, 768 and 1440 px in light and dark" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for scheme in ["light", "dark"] {
                for width in [375, 768, 1440] {
                    for (query, name) in [
                        ("", "backoffice"),
                        ("?surface=storefront", "storefront")
                    ] {
                        page = browser.new_context(
                            viewport={"width": width, "height": 900},
                            color_scheme=scheme
                        ).new_page();
                        page.goto(GUIDE + query);
                        page.wait_for_selector(TITLE);
                        page.evaluate("document.fonts.ready");
                        page.screenshot(
                            path=artifact(f"shell-{name}-{width}-{scheme}.png")
                        );
                        if width == 375 and name == "backoffice" {
                            page.click(MENU);
                            page.wait_for_selector(DRAWER, state="visible");
                            page.wait_for_timeout(400);
                            page.screenshot(
                                path=artifact(f"shell-drawer-375-{scheme}.png")
                            );
                        }
                        page.context.close();
                    }
                }
            }
        } finally {
            browser.close();
        }
    }
}
