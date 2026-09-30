"""P3.8b E2E: a cinema's Branding page and its themed storefront.

Settings › Branding edits the cinema's draft theme (presets, colours, fonts, logo) with a
live preview, and publishes it; the storefront (/c/{slug}) then wears it, and every other
cinema's storefront keeps its own look. Unreadable colours are repaired on save and the
page says which. Restoring an earlier version asks first. The cinema's logo also shows in
its back-office.
"""

import io;
import base64;
import from PIL { Image }
import from core.theming.tokens { DEFAULT_THEME }
import from core.theming.branding { PRESETS }
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { PASSWORD, call, owner_with_cinema }

glob BRANDING: str = '[data-testid="branding"]',
     PREVIEW: str = '[data-testid="theme-preview"]',
     STATUS: str = '[data-testid="branding-status"]',
     MESSAGE: str = '[data-testid="branding-message"]',
     ADJUSTED: str = '[data-testid="adjusted-colours"]',
     HISTORY: str = '[data-testid="version-history"]',
     CONFIRM: str = '[data-testid="restore-confirm"]',
     STOREFRONT: str = '[data-testid="storefront"]',
     SAVE: str = 'button:has-text("Save draft")',
     PUBLISH: str = 'button:has-text("Publish")',
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    'a[href], button, [role=button], input, select, textarea')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1
      && getComputedStyle(e).visibility !== 'hidden'; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.id || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""",
     UNLABELLED_JS: str = """() => [...document.querySelectorAll('input:not([type=hidden]), textarea, select')]
  .filter(e => !(e.labels && e.labels.length) && !e.getAttribute('aria-label')
      && !e.getAttribute('aria-labelledby'))
  .map(e => e.id || e.name || e.outerHTML.slice(0, 60))""",
     HEADINGS_JS: str = "[...document.querySelectorAll('h1,h2,h3,h4')].map(h => +h.tagName[1])",
     # The storefront's live theme value for a CSS variable.
     VAR_JS: str = "v => getComputedStyle(document.querySelector('[data-surface=storefront]')).getPropertyValue(v).trim()";

def _preset(name: str) -> dict[str, any] {  # jac:ignore[W1037]
    return [
        p
        for p in PRESETS
        if p.name == name
    ][0].as_dict();
}

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _page(browser: any, pw: any, project: str, scheme: str = "light") -> any {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, scheme)).new_page();
    return page;
}

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
}

def _open_branding(page: any, owner: dict[str, str]) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/app/{owner['slug']}/settings");
    page.wait_for_selector(BRANDING);
}

def _storefront(page: any, slug: str) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/c/{slug}");
    page.wait_for_selector(STOREFRONT);
}

def _var(page: any, name: str) -> str {  # jac:ignore[W1037]
    return page.evaluate(VAR_JS, name).upper();
}

def _publish_api(owner: dict[str, str], theme: dict[str, any]) -> int {  # jac:ignore[W1037]
    assert call(owner["token"], "save_theme", {"tenant": owner["slug"], "theme": theme})[
        "ok"
    ];
    answer = call(owner["token"], "publish_theme", {"tenant": owner["slug"]});
    assert answer["ok"] , answer;
    return answer["version"];
}

def _logo_png -> bytes {
    out = io.BytesIO();
    Image.new("RGBA", (240, 96), (225, 29, 72, 255)).save(out, format="PNG");
    return out.getvalue();
}

test "an owner picks a preset, publishes it, and only their storefront changes" {
    other = owner_with_cinema("Rift Cinemas");
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema();
            page = _page(browser, pw, project);
            _sign_in(page, owner["email"]);
            _open_branding(page, owner);
            assert "default" in page.inner_text(STATUS).lower() , page.inner_text(
                STATUS
            );
            page.click('label:has-text("Blackout Crimson")');
            crimson = _preset("Blackout Crimson");
            assert page.get_attribute(
                f"{PREVIEW} [data-testid=preview-button]", "style"
            )
                is not None;
            preview_accent = page.evaluate(
                "getComputedStyle(document.querySelector('[data-testid=preview-button]')).backgroundColor"
            );
            r = int(crimson["light"]["accent"][1:3], 16);
            assert preview_accent.startswith(f"rgb({r},") , preview_accent;
            page.click(PUBLISH);
            page.wait_for_selector(f"{STATUS}:has-text('Version 1')");
            _open_branding(page, owner);
            assert page.is_checked('input[name="preset"][value="Blackout Crimson"]') , "the live preset isn't marked";
            _storefront(page, owner["slug"]);
            assert _var(page, "--primary") == crimson["light"]["accent"];
            _storefront(page, other["slug"]);
            assert _var(page, "--primary") == DEFAULT_THEME.light.accent , "another cinema changed";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the storefront wears the cinema's dark theme on a dark device" {
    owner = owner_with_cinema();
    velvet = _preset("Velvet Curtain");
    _publish_api(owner, velvet);
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile", "dark");
        _storefront(page, owner["slug"]);
        assert _var(page, "--background") == velvet["dark"]["background"];
        assert page.inner_text('[data-testid="storefront-name"]') == owner["name"];
    } finally {
        close_contexts(browser);
    }
}

test "an unreadable colour is repaired on save, and a malformed one is flagged" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _sign_in(page, owner["email"]);
        _open_branding(page, owner);
        _type(page, "#hex-light-ink", "#12");
        page.locator("#hex-light-ink").blur();
        page.wait_for_selector('#hex-light-ink-error[role="alert"]');
        assert page.is_disabled(SAVE) , "a malformed colour can't be saved";
        _type(page, "#hex-light-ink", "#F5F2EA");  # nearly the page colour
        page.locator("#hex-light-ink").blur();
        page.click(SAVE);
        page.wait_for_selector(ADJUSTED);
        text = page.inner_text(ADJUSTED);
        assert "Text" in text and "#F5F2EA" in text , text;
        fixed = page.input_value("#hex-light-ink");
        assert fixed.upper() != "#F5F2EA" , fixed;
        assert "saved" in page.inner_text(MESSAGE).lower();
    } finally {
        close_contexts(browser);
    }
}

test "restoring an earlier version asks first, then republishes it" {
    owner = owner_with_cinema();
    _publish_api(owner, _preset("Blackout Crimson"));
    _publish_api(owner, _preset("Projector Black"));
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            _sign_in(page, owner["email"]);
            _open_branding(page, owner);
            items = page.locator(f"{HISTORY} li").all_inner_texts();
            assert "Version 2" in items[0] and "Projector Black" in items[0] , items;
            page.click('button:has-text("Restore version 1")');
            page.wait_for_selector(CONFIRM);
            page.click(f'{CONFIRM} button:has-text("Cancel")');
            page.wait_for_selector(CONFIRM, state="detached");
            if project == "desktop" {
                page.click('button:has-text("Restore version 1")');
                page.click(f'{CONFIRM} button:has-text("Restore version 1")');
                page.wait_for_selector(f"{STATUS}:has-text('Version 3')");
                _storefront(page, owner["slug"]);
                assert _var(page, "--primary")
                    == _preset("Blackout Crimson")["light"]["accent"];
            }
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a logo uploaded here shows on the storefront and in the back-office" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _sign_in(page, owner["email"]);
        _open_branding(page, owner);
        page.set_input_files(
            "#logo-file",
            files=[{"name": "logo.png", "mimeType": "image/png", "buffer": _logo_png()}]
        );
        page.wait_for_selector('[data-testid="logo-preview"]');
        page.click(PUBLISH);
        page.wait_for_selector(f"{STATUS}:has-text('Version 1')");
        _storefront(page, owner["slug"]);
        logo = page.locator(f'{STOREFRONT} img[alt="{owner["name"]}"]');
        assert logo.is_visible();
        assert logo.get_attribute("src").startswith("data:image/webp;base64,");
        page.goto(f"{BASE_URL}/app/{owner['slug']}");
        page.wait_for_selector(
            '[data-testid="shell-sidebar"] [data-testid="brand-logo"]'
        );
    } finally {
        close_contexts(browser);
    }
}

test "the Branding page and the storefront pass the phone checks" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
        ).new_page();
        _publish_api(owner, _preset("Projector Black"));
        _sign_in(page, owner["email"]);
        _open_branding(page, owner);
        _storefront_path = f"/c/{owner['slug']}";
        for (path, ready) in [
            (f"/app/{owner['slug']}/settings", BRANDING),
            (_storefront_path, STOREFRONT)
        ] {
            page.goto(BASE_URL + path);
            page.wait_for_selector(ready);
            assert page.evaluate(OVERFLOW_JS) <= 0 , f"{path} scrolls sideways";
            assert page.evaluate(SMALL_TARGETS_JS) == [] , f"{path}: {page.evaluate(
                SMALL_TARGETS_JS
            )}";
            assert page.evaluate(UNLABELLED_JS) == [] , f"{path}: {page.evaluate(
                UNLABELLED_JS
            )}";
            assert "jac:ignore" not in page.inner_text("body") , f"{path}: a code comment shows";
            levels = page.evaluate(HEADINGS_JS);
            assert levels.count(1) == 1 , f"{path}: {levels}";
            assert all(b - a <= 1 for (a, b) in zip(levels, levels[1:])) , f"{path}: {levels}";
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the Branding page and the storefront" {
    owner = owner_with_cinema();
    call(
        owner["token"],
        "upload_logo",
        {
            "tenant": owner["slug"],
            "content_type": "image/png",
            "data_base64": base64.b64encode(_logo_png()).decode()
        }
    );
    _publish_api(owner, _preset("Velvet Curtain"));
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for width in [375, 768, 1440] {
                page = browser.new_context(
                    viewport={"width": width, "height": 900}, color_scheme=scheme
                ).new_page();
                _sign_in(page, owner["email"]);
                _open_branding(page, owner);
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"branding-{width}-{scheme}.png"), full_page=True
                );
                _storefront(page, owner["slug"]);
                page.evaluate("document.fonts.ready");
                page.screenshot(path=artifact(f"storefront-{width}-{scheme}.png"));
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
