"""P0.8b E2E: the approved theme really applies in a browser, on a phone and a desktop.

Expected values come from the tokens (core.theming.tokens.DEFAULT_THEME), never from
hard-coded colours, so these tests follow the design system when it changes.
"""

import from playwright.sync_api { sync_playwright }
import from core.theming.tokens { DEFAULT_THEME, ThemeTokens, contrast_ratio }
import from e2e.support.web {
    BASE_URL,
    PROJECTS,
    context_options,
    hex_to_rgb,
    computed,
    artifact,
    painted_color
}

glob SURFACE: str = '[data-surface="storefront"]',
     CTA: str = '[data-testid="primary-cta"]',
     SECONDARY: str = '[data-testid="secondary-cta"]',
     WORDMARK: str = '[data-testid="wordmark"]';

def _assert_tokens(page: any, tokens: ThemeTokens, where: str) {  # jac:ignore[W1037]
    assert computed(page, SURFACE, "background-color")
        == hex_to_rgb(tokens.background) , f"{where}: page background";
    assert computed(page, SURFACE, "color") == hex_to_rgb(tokens.ink) , f"{where}: text colour";
    assert computed(page, CTA, "background-color") == hex_to_rgb(tokens.accent) , f"{where}: primary button fill";
    assert computed(page, CTA, "color") == hex_to_rgb(tokens.on_accent) , f"{where}: primary button text";
}

test "storefront renders the light theme on phone and desktop" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for project in PROJECTS {
                page = browser.new_context(
                    **context_options(pw, project, "light")
                ).new_page();
                page.goto(BASE_URL);
                page.wait_for_selector(CTA);
                assert page.evaluate(
                    "document.documentElement.classList.contains('dark')"
                )
                    == False;
                _assert_tokens(page, DEFAULT_THEME.light, f"{project}/light");
                page.context.close();
            }
        } finally {
            browser.close();
        }
    }
}

test "storefront renders the dark theme on phone and desktop" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for project in PROJECTS {
                page = browser.new_context(
                    **context_options(pw, project, "dark")
                ).new_page();
                page.goto(BASE_URL);
                page.wait_for_selector(CTA);
                page.wait_for_function(
                    "document.documentElement.classList.contains('dark')"
                );
                _assert_tokens(page, DEFAULT_THEME.dark, f"{project}/dark");
                page.context.close();
            }
        } finally {
            browser.close();
        }
    }
}

def _rgb_to_hex(rgb: str) -> str {
    parts = [
        int(float(p)) for p in rgb[rgb.index("(") + 1:rgb.index(")")].split(",")[:3]
    ];
    return "#" + "".join(f"{p:02X}" for p in parts);
}

test "secondary button stays on-theme and readable in both modes" {
    # Caught by eye in the first review screenshots: in dark mode the outline button was
    # painted as a pale grey block. Check the colour actually painted (handles translucent
    # fills), that it sits on the right side (dark/light) for the mode, and that its text reads.
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for scheme in ["light", "dark"] {
                page = browser.new_context(
                    **context_options(pw, "mobile", scheme)
                ).new_page();
                page.goto(BASE_URL);
                page.wait_for_selector(SECONDARY);
                if scheme == "dark" {
                    page.wait_for_function(
                        "document.documentElement.classList.contains('dark')"
                    );
                }
                fill = painted_color(page, SECONDARY);
                text = _rgb_to_hex(computed(page, SECONDARY, "color"));
                fill_is_dark = contrast_ratio("#FFFFFF", fill)
                    >= contrast_ratio("#000000", fill);
                assert fill_is_dark == (scheme == "dark") , f"{scheme}: secondary button painted {fill}";
                assert contrast_ratio(text, fill) >= 4.5 , f"{scheme}: text {text} on {fill} is {contrast_ratio(
                    text, fill
                ):.2f}:1";
                page.context.close();
            }
        } finally {
            browser.close();
        }
    }
}

glob FIRST_FRAME_PROBE: str = """
window.__firstContentFrame = null;
(function tick() {
  const root = document.getElementById('root');
  if (root && root.children.length) {
    // rAF callbacks run just before the browser paints this frame.
    window.__firstContentFrame = {dark: document.documentElement.classList.contains('dark')};
    return;
  }
  requestAnimationFrame(tick);
})();
""";

test "no flash of the light theme on a dark device" {
    # Measured inside the page, so there is no timing race: on the very first frame that
    # paints the app, dark mode must already be applied. Otherwise that frame is light.
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for project in PROJECTS {
                context = browser.new_context(**context_options(pw, project, "dark"));
                context.add_init_script(FIRST_FRAME_PROBE);
                page = context.new_page();
                page.goto(BASE_URL);
                page.wait_for_function("window.__firstContentFrame !== null");
                first_dark = page.evaluate("window.__firstContentFrame.dark");
                assert first_dark == True , f"{project}: the first painted frame was light (flash before dark mode applied)";
                context.close();
            }
        } finally {
            browser.close();
        }
    }
}

test "the theme follows the device switching to dark while open" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = browser.new_context(
                **context_options(pw, "mobile", "light")
            ).new_page();
            page.goto(BASE_URL);
            page.wait_for_selector(CTA);
            page.emulate_media(color_scheme="dark");
            page.wait_for_function(
                "document.documentElement.classList.contains('dark')"
            );
            _assert_tokens(page, DEFAULT_THEME.dark, "mobile/live-switch");
        } finally {
            browser.close();
        }
    }
}

test "brand fonts are loaded and used" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = browser.new_context(
                **context_options(pw, "desktop", "light")
            ).new_page();
            page.goto(BASE_URL);
            page.wait_for_selector(WORDMARK);
            page.evaluate("document.fonts.ready");
            assert "Bebas Neue" in computed(page, WORDMARK, "font-family") , "wordmark uses the display font";
            assert "Outfit" in computed(page, SURFACE, "font-family") , "body uses Outfit";
            assert page.evaluate("document.fonts.check(\"48px 'Bebas Neue'\")") , "Bebas Neue actually loaded";
            assert page.evaluate("document.fonts.check(\"16px 'Outfit Variable'\")") , "Outfit actually loaded";
            assert page.title() == "AfriCinemas";
        } finally {
            browser.close();
        }
    }
}

test "phone layout: no sideways scroll at 375 px and 44 px tap targets" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            page = browser.new_context(
                viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
            ).new_page();
            page.goto(BASE_URL);
            page.wait_for_selector(CTA);
            overflow = page.evaluate(
                "document.documentElement.scrollWidth - document.documentElement.clientWidth"
            );
            assert overflow <= 0 , f"page scrolls sideways by {overflow}px at 375px";
            for selector in [CTA, '[data-testid="secondary-cta"]'] {
                # Measured in the browser: indexing Playwright's FloatRect trips JI-018.
                height = page.locator(selector).evaluate(
                    "e => e.getBoundingClientRect().height"
                );
                assert height >= 44 , f"{selector} tap target is {height}px tall";
            }
        } finally {
            browser.close();
        }
    }
}

test "review screenshots at 375, 768 and 1440 px in light and dark" {
    with sync_playwright() as pw {
        browser = pw.chromium.launch();
        try {
            for scheme in ["light", "dark"] {
                for width in [375, 768, 1440] {
                    page = browser.new_context(
                        viewport={"width": width, "height": 900}, color_scheme=scheme
                    ).new_page();
                    page.goto(BASE_URL);
                    page.wait_for_selector(CTA);
                    page.evaluate("document.fonts.ready");
                    page.screenshot(
                        path=artifact(f"storefront-{width}-{scheme}.png"),
                        full_page=True
                    );
                    page.context.close();
                }
            }
        } finally {
            browser.close();
        }
    }
}
