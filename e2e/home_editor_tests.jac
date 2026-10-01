"""P4.1b E2E: the home page editor (Settings › Home page).

An owner picks a template, shows, hides, reorders and fills in sections on the Edit tab,
checks the Preview tab (phone or desktop), then publishes; the storefront follows. A problem shows under its field
and stops publishing. Earlier versions can be restored, and About photos uploaded.
"""

import io;
import from PIL { Image }
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { PASSWORD }
import from e2e.support.catalog { cinema_with_programme }

glob EDITOR: str = '[data-testid="home-editor"]',
     PREVIEW: str = '[data-testid="home-preview"]',
     MESSAGE: str = '[data-testid="home-message"]',
     PREVIEW_ORDER_JS: str = "[...document.querySelectorAll('[data-testid=home-preview] [data-testid^=section-]')].map(e => e.dataset.testid.slice(8))",
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    '[data-testid=home-editor] a[href], [data-testid=home-editor] button, [data-testid=home-editor] summary, [data-testid=home-editor] select')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _editor(
    browser: any,  # jac:ignore[W1037]
    pw: any,  # jac:ignore[W1037]
    project: str,
    owner: dict[str, str],
    scheme: str = "light"
) -> any {  # jac:ignore[W1037]
    # Signs in as the owner and opens Settings › Home page, on the Edit tab.
    page = browser.new_context(**context_options(pw, project, scheme)).new_page();
    page.goto(BASE_URL + "/login");
    _type(page, "#email", owner["email"]);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
    page.goto(f"{BASE_URL}/app/{owner['slug']}/settings");
    page.click('[data-testid="settings-tab-home-page"]');
    page.wait_for_selector(EDITOR);
    page.wait_for_selector('[data-testid="edit-hero"]');
    return page;
}

def _tab(page: any, name: str) {  # jac:ignore[W1037]
    # Switches to the Edit or Preview tab; the preview waits until it has drawn.
    page.click(f'[data-testid="home-tab-{name}"]');
    if name == "preview" {
        page.wait_for_selector(f"{PREVIEW} [data-testid^=section-]");
    } else {
        page.wait_for_selector('[data-testid="edit-hero"]');
    }
}

def _open_section(page: any, kind: str) {  # jac:ignore[W1037]
    page.click(f'[data-testid="edit-{kind}"] summary');
}

def _preview_has(page: any, text: str) {  # jac:ignore[W1037]
    page.wait_for_function(
        f"document.querySelector('{PREVIEW}').innerText.includes({text!r})"
    );
}

def _preview_order(page: any, order: list[str]) {  # jac:ignore[W1037]
    page.wait_for_function(
        f"JSON.stringify({PREVIEW_ORDER_JS}) === JSON.stringify({order!r})"
    );
}

def _publish(page: any) {  # jac:ignore[W1037]
    page.click('button:has-text("Publish")');
    page.wait_for_function(
        f"document.querySelector('{MESSAGE}').innerText.includes('is live')"
    );
}

test "an owner picks a template, fills in a section, previews it and publishes" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            # A cinema per device: the second run would otherwise find these edits
            # already saved and published, with nothing left to save.
            owner = cinema_with_programme();
            page = _editor(browser, pw, project, owner);
            page.click('label:has-text("Schedule")');
            _open_section(page, "about");
            _type(page, "#home-4-text", "A family-run cinema since 1998.");
            _tab(page, "preview");
            page.wait_for_selector(f'{PREVIEW}[data-template="schedule"]');
            _preview_has(page, "A family-run cinema since 1998.");
            page.click('button:has-text("Save draft")');
            page.wait_for_function(
                f"document.querySelector('{MESSAGE}').innerText.includes('Draft saved')"
            );
            _publish(page);
            page.wait_for_selector('[data-testid="home-status"]:has-text("is live")');
            page.goto(f"{BASE_URL}/c/{owner['slug']}");
            page.wait_for_selector(
                '[data-testid="home-page"][data-template="schedule"]'
            );
            assert "A family-run cinema since 1998."
                in page.inner_text('[data-testid="section-about"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the preview lays out like a phone or a desktop, whatever the window" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = _editor(browser, pw, "desktop", owner);
        _tab(page, "preview");
        card_columns = "getComputedStyle(document.querySelector('[data-testid=home-preview] [data-testid=movie-card]')).gridTemplateColumns.split(' ')[0]";
        assert page.get_attribute(PREVIEW, "data-device") == "phone";
        assert page.evaluate(card_columns) == "96px";  # the phone layout's 6rem poster
        page.click('[aria-label="Preview size"] button:has-text("Desktop")');
        page.wait_for_function(f"{card_columns} === '120px'");  # 7.5rem from @xl up
    } finally {
        close_contexts(browser);
    }
}

test "hiding and moving sections changes the preview, then the storefront" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = _editor(browser, pw, "desktop", owner);
        # Marquee's default order: Featured movie, Now showing, Coming soon, Today, …
        _tab(page, "preview");
        _preview_order(page, ["hero", "now_showing", "today"]);
        _tab(page, "edit");
        page.click('[aria-label="Move Now showing up"]');
        _tab(page, "preview");
        _preview_order(page, ["now_showing", "hero", "today"]);
        _tab(page, "edit");
        page.uncheck('[data-testid="edit-hero"] input[type="checkbox"]');
        _tab(page, "preview");
        _preview_order(page, ["now_showing", "today"]);
        _publish(page);
        page.goto(f"{BASE_URL}/c/{owner['slug']}");
        page.wait_for_selector('[data-testid="section-now_showing"]');
        assert page.locator('[data-testid="section-hero"]').count() == 0;
    } finally {
        close_contexts(browser);
    }
}

test "a problem shows under its field and stops publishing until it's fixed" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = _editor(browser, pw, "mobile", owner);
        _open_section(page, "location");
        _type(page, "#home-5-map_url", "maps.example.com");
        page.wait_for_selector("#home-5-map_url-error:has-text('https://')");
        assert page.get_attribute("#home-5-map_url", "aria-invalid") == "true";
        assert page.is_disabled('button:has-text("Publish")');
        _type(page, "#home-5-map_url", "https://maps.example.com/nova");
        page.wait_for_function(
            "!document.querySelector('#home-5-map_url-error') || !document.querySelector('#home-5-map_url-error').innerText"
        );
        assert not page.is_disabled('button:has-text("Publish")');
    } finally {
        close_contexts(browser);
    }
}

test "an owner restores an earlier version of the page" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = _editor(browser, pw, "desktop", owner);
        page.click('label:has-text("Compact")');
        _tab(page, "preview");
        page.wait_for_selector(f'{PREVIEW}[data-template="compact"]');
        _publish(page);
        _tab(page, "edit");
        page.click('label:has-text("Schedule")');
        _tab(page, "preview");
        page.wait_for_selector(f'{PREVIEW}[data-template="schedule"]');
        _publish(page);
        _tab(page, "edit");
        page.click('button:has-text("Restore version 1")');
        page.wait_for_selector('[data-testid="home-restore-confirm"]');
        page.click(
            '[data-testid="home-restore-confirm"] button:has-text("Restore version 1")'
        );
        page.wait_for_function(
            f"document.querySelector('{MESSAGE}').innerText.includes('as version 3')"
        );
        assert page.locator('[data-testid="home-versions"] li').count() == 3;
        _tab(page, "preview");
        page.wait_for_selector(f'{PREVIEW}[data-template="compact"]');
    } finally {
        close_contexts(browser);
    }
}

test "an owner uploads a photo and shows it in About" {
    owner = cinema_with_programme();
    out = io.BytesIO();
    Image.new("RGB", (800, 600), "#2E5A7A").save(out, format="PNG");
    (pw, browser) = shared_browser();
    try {
        page = _editor(browser, pw, "desktop", owner);
        _open_section(page, "about");
        _type(page, "#home-4-text", "Our lobby.");
        page.set_input_files(
            "#home-4-photo-file",
            files=[
                {"name": "lobby.png", "mimeType": "image/png", "buffer": out.getvalue()}
            ]
        );
        page.wait_for_selector('[data-testid="home-photo"] img');
        page.check('[data-testid="home-photo"] input[type="checkbox"]');
        _tab(page, "preview");
        page.wait_for_selector(f'{PREVIEW} [data-testid="about-photos"] img');
        _publish(page);
        page.goto(f"{BASE_URL}/c/{owner['slug']}");
        page.wait_for_function(
            "(() => { const i = document.querySelector('[data-testid=about-photos] img'); return i && i.complete && i.naturalWidth > 0; })()"
        );
    } finally {
        close_contexts(browser);
    }
}

test "the home page editor passes the phone checks" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        page = _editor(browser, pw, "mobile", owner);
        for kind in ["hero", "coming_soon", "about", "location", "contact", "faq"] {
            _open_section(page, kind);
        }
        page.click('button:has-text("Add opening hours")');
        page.click('button:has-text("Add question")');
        assert page.evaluate(OVERFLOW_JS) <= 0 , "the editor scrolls sideways";
        assert page.evaluate(SMALL_TARGETS_JS) == [] , page.evaluate(SMALL_TARGETS_JS);
        _tab(page, "preview");
        assert page.evaluate(OVERFLOW_JS) <= 0 , "the preview scrolls sideways";
        assert page.evaluate(SMALL_TARGETS_JS) == [] , page.evaluate(SMALL_TARGETS_JS);
        assert "jac:ignore" not in page.inner_text("body");
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the home page editor" {
    owner = cinema_with_programme();
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for (project, width) in [
                ("mobile", 375),
                ("desktop", 768),
                ("desktop", 1440)
            ] {
                page = _editor(browser, pw, project, owner, scheme);
                page.set_viewport_size({"width": width, "height": 900});
                _open_section(page, "about");
                page.evaluate("document.fonts.ready");
                page.wait_for_timeout(300);
                page.screenshot(
                    path=artifact(f"home-editor-{width}-{scheme}.png"), full_page=True
                );
                _tab(page, "preview");
                for device in ["Phone", "Desktop"] {
                    page.click(
                        f'[aria-label="Preview size"] button:has-text("{device}")'
                    );
                    page.wait_for_timeout(300);
                    page.screenshot(
                        path=artifact(
                            f"home-preview-{device.lower()}-{width}-{scheme}.png"
                        ),
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
