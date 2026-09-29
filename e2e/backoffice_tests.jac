"""P2.7b E2E: sign-up, sign-in, the new-cinema wizard and the role-aware back-office, on a
phone (navigation through the drawer) and a desktop (the sidebar).

Accounts and cinemas are made through the public API (e2e/support/api.jac) or the UI
itself, each with a random suffix, so tests never depend on each other's data.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api {
    PASSWORD,
    unique,
    email_for,
    register,
    call,
    owner_with_cinema,
    add_venue,
    add_staff
}

glob SIDEBAR: str = '[data-testid="shell-sidebar"]',
     MENU: str = '[data-testid="shell-menu-button"]',
     DRAWER: str = '[data-testid="shell-drawer"]',
     TITLE: str = '[data-testid="shell-title"]',
     BANNER: str = '[data-testid="shift-banner"]',
     SHIFT_STATUS: str = '[data-testid="shift-status"]',
     SLUG_STATUS: str = "#cinema-slug-status",
     AUTH_ERROR: str = '[data-testid="auth-error"]',
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     # Visible controls smaller than 44 x 44 px (as in shell_tests).
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    'a[href], button, [role=button], input, select, textarea')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1
      && getComputedStyle(e).visibility !== 'hidden'; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.id || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""",
     # Form fields with no accessible name from a <label> or aria-label(ledby).
     UNLABELLED_JS: str = """() => [...document.querySelectorAll('input:not([type=hidden]), textarea, select')]
  .filter(e => !(e.labels && e.labels.length) && !e.getAttribute('aria-label')
      && !e.getAttribute('aria-labelledby'))
  .map(e => e.id || e.name || e.outerHTML.slice(0, 60))""";

def _page(browser: any, pw: any, project: str, scheme: str = "light") -> any {  # jac:ignore[W1037]
    return browser.new_context(**context_options(pw, project, scheme)).new_page();
}

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
}

def _open_cinema(page: any, owner: dict[str, str]) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/app/{owner['slug']}");
    page.wait_for_selector(TITLE);
}

def _shot(page: any, name: str, width: int, scheme: str) {  # jac:ignore[W1037]
    page.evaluate("document.fonts.ready");
    page.screenshot(path=artifact(f"{name}-{width}-{scheme}.png"));
}

def _nav_labels(page: any, project: str) -> list[str] {  # jac:ignore[W1037]
    # The navigation as the user reaches it: the drawer on a phone, the sidebar on desktop.
    if project == "mobile" {
        page.click(MENU);
        page.wait_for_selector(DRAWER, state="visible");
        labels = page.locator(f"{DRAWER} nav a").all_inner_texts();
        page.keyboard.press("Escape");
        page.wait_for_selector(DRAWER, state="hidden");
    } else {
        labels = page.locator(f"{SIDEBAR} nav a").all_inner_texts();
    }
    return [l.strip() for l in labels];
}

def _sign_out(page: any, project: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.click(MENU);
        page.wait_for_selector(DRAWER, state="visible");
        page.click(f'{DRAWER} button:has-text("Sign out")');
    } else {
        page.click(f'{SIDEBAR} button:has-text("Sign out")');
    }
    page.wait_for_url("**/login");
}

test "an owner signs up, creates a cinema and lands on its back-office" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            page.goto(BASE_URL + "/signup");
            _type(page, "#email", email_for(unique("signup")));
            _type(page, "#password", PASSWORD);
            page.click('button[type="submit"]');
            page.wait_for_url("**/app/new");
            slug = unique("wizard");
            _type(page, "#cinema-name", "Westgate Cinemas");
            _type(page, "#cinema-slug", slug);
            page.locator("#cinema-slug").blur();
            page.wait_for_selector(f'{SLUG_STATUS}:has-text("available")');
            page.click('button[type="submit"]');
            page.wait_for_selector('h2:has-text("Brand your cinema")');
            assert page.locator(
                '[aria-current="step"]'
            ).inner_text().strip().startswith(
                "2"
            ) , f"{project}: the progress marks step 2";
            page.click('a:has-text("Skip for now")');
            page.wait_for_url(f"**/app/{slug}");
            assert page.locator(TITLE).inner_text().strip() == "Overview";
            assert _nav_labels(page, project)
                == [
                    "Overview",
                    "Screenings",
                    "Box office",
                    "Scanner",
                    "Staff",
                    "Settings"
                ] , f"{project}: owner nav";
            page.goto(BASE_URL + "/app");
            # Waits for the list to load; fails if the new cinema never appears.
            page.wait_for_selector(
                f'[data-testid="cinema-list"] a[href="/app/{slug}"]'
            );
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the slug field flags an invalid or taken address before submitting" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        _sign_in(page, owner["email"]);
        page.goto(BASE_URL + "/app/new");
        _type(page, "#cinema-name", "Rift");
        slug_input = page.locator("#cinema-slug");
        for (value, words) in [
            ("no--va", "hyphen"),
            (owner["slug"], "already taken")
        ] {
            _type(page, "#cinema-slug", value);
            slug_input.blur();
            page.wait_for_selector(f"{SLUG_STATUS}:has-text('{words}')");
            assert slug_input.get_attribute("aria-invalid") == "true" , value;
            assert "cinema-slug-status"
                in (slug_input.get_attribute("aria-describedby") or "") , value;
        }
        page.click('button[type="submit"]');
        # Submitting a taken address stays on step 1 and puts focus on the field.
        page.wait_for_function(
            "document.activeElement && document.activeElement.id === 'cinema-slug'"
        );
        assert page.locator('h2:has-text("Brand your cinema")').count() == 0;
    } finally {
        close_contexts(browser);
    }
}

test "an account made in the browser can sign out and sign back in" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            email = email_for(unique("again"));
            page = _page(browser, pw, project);
            page.goto(BASE_URL + "/signup");
            _type(page, "#email", email);
            _type(page, "#password", PASSWORD);
            page.click('button[type="submit"]');
            page.wait_for_url("**/app/new");
            _type(page, "#cinema-name", "Round Trip Cinema");
            _type(page, "#cinema-slug", unique("again"));
            page.click('button[type="submit"]');
            page.click('a:has-text("Skip for now")');
            page.wait_for_selector(TITLE);
            _sign_out(page, project);
            # Sign back in with the same details, typed the way people do.
            _type(page, "#email", " " + email.upper() + " ");
            _type(page, "#password", PASSWORD);
            page.click('button[type="submit"]');
            page.wait_for_url("**/app");
            page.wait_for_selector('[data-testid="cinema-list"]');
            assert page.locator(AUTH_ERROR).count() == 0;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a wrong password shows an error and keeps the user on the sign-in page" {
    email = email_for(unique("wrongpw"));
    register(email);
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            page.goto(BASE_URL + "/login");
            _type(page, "#email", email);
            _type(page, "#password", "not-the-password");
            page.click('button[type="submit"]');
            page.wait_for_selector(AUTH_ERROR);
            assert page.locator(AUTH_ERROR).get_attribute("role") == "alert";
            assert "incorrect" in page.locator(AUTH_ERROR).inner_text().lower();
            assert page.url.endswith("/login") , page.url;
            assert page.evaluate("localStorage.getItem('jac_token')") is None;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the password field can be shown and hidden without submitting the form" {
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        # Both forms use the same field. On sign-up, a submit would create the account
        # with a half-typed password, so neither page may submit on the toggle.
        for path in ["/login", "/signup"] {
            page.goto(BASE_URL + path);
            field = page.locator("#password");
            toggle = page.locator('button[aria-controls="password"]');
            # A plain button: inside the form, a missing type would make it submit (JI-030).
            assert toggle.get_attribute("type") == "button" , path;
            _type(page, "#email", email_for(unique("toggle")));
            _type(page, "#password", "half-typed-pass");
            assert field.get_attribute("type") == "password";
            assert toggle.get_attribute("aria-pressed") == "false";
            toggle.click();
            assert field.get_attribute("type") == "text";
            assert toggle.get_attribute("aria-pressed") == "true";
            page.wait_for_timeout(1000);
            assert page.url.endswith(path) , f"{path}: the toggle submitted the form ({page.url})";
            assert page.locator(AUTH_ERROR).count() == 0 , f"{path}: the toggle submitted the form";
        }
    } finally {
        close_contexts(browser);
    }
}

test "sign-in says when the server can't be reached, not that the password is wrong" {
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        page.goto(BASE_URL + "/login");
        page.route("**/user/login", lambda (route: any) { route.abort(); });
        _type(page, "#email", email_for(unique("offline")));
        _type(page, "#password", PASSWORD);
        page.click('button[type="submit"]');
        page.wait_for_selector(AUTH_ERROR);
        message = page.locator(AUTH_ERROR).inner_text();
        assert "couldn't reach" in message , message;
        assert "incorrect" not in message.lower() , message;
    } finally {
        close_contexts(browser);
    }
}

test "signed-out visitors are sent to sign in" {
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        for path in ["/app", "/app/new", "/app/some-cinema"] {
            page.goto(BASE_URL + path);
            page.wait_for_url("**/login");
        }
    } finally {
        close_contexts(browser);
    }
}

test "an usher sees only the overview and the scanner" {
    owner = owner_with_cinema();
    usher = add_staff(owner, "usher", add_venue(owner));
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = _page(browser, pw, project);
            _sign_in(page, usher["email"]);
            page.click(f'[data-testid="cinema-list"] a[href="/app/{owner["slug"]}"]');
            page.wait_for_selector(TITLE);
            assert _nav_labels(page, project) == ["Overview", "Scanner"] , project;
            page.goto(f"{BASE_URL}/app/{owner['slug']}/staff");
            page.wait_for_selector('[data-testid="no-access"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a person with no cinemas is offered to create one" {
    email = email_for(unique("empty"));
    register(email);
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        _sign_in(page, email);
        page.wait_for_selector('[data-testid="no-cinemas"]');
        page.click('[data-testid="no-cinemas"] a:has-text("Create a cinema")');
        page.wait_for_url("**/app/new");
    } finally {
        close_contexts(browser);
    }
}

test "the shift banner starts a shift, and signing out ends it" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema();
            call(owner["token"], "end_shift", {"tenant": owner["slug"]});
            page = _page(browser, pw, project);
            _sign_in(page, owner["email"]);
            _open_cinema(page, owner);
            page.wait_for_selector(BANNER);
            page.click(f'{BANNER} button:has-text("Start shift")');
            page.wait_for_selector(BANNER, state="detached");
            assert "On shift" in page.locator(SHIFT_STATUS).inner_text();
            token = page.evaluate("localStorage.getItem('jac_token')");
            assert call(
                token, "rename_cinema", {"tenant": owner["slug"], "name": "Nova Two"}
            )["ok"] , f"{project}: the shift is open";
            _sign_out(page, project);
            assert page.evaluate("localStorage.getItem('jac_token')") is None;
            refused = call(
                token, "rename_cinema", {"tenant": owner["slug"], "name": "Nova Three"}
            );
            assert refused["error"]["code"] == "no_shift" , f"{project}: {refused}";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the sign-in, sign-up, wizard and back-office screens pass the phone checks" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
        ).new_page();
        screens = [("/signup", "#email"), ("/login", "#email")];
        for (path, ready) in screens {
            page.goto(BASE_URL + path);
            page.wait_for_selector(ready);
            assert page.evaluate(OVERFLOW_JS) <= 0 , f"{path} scrolls sideways";
            assert page.evaluate(SMALL_TARGETS_JS) == [] , f"{path}: {page.evaluate(
                SMALL_TARGETS_JS
            )}";
            assert page.evaluate(UNLABELLED_JS) == [] , f"{path}: {page.evaluate(
                UNLABELLED_JS
            )}";
        }
        _sign_in(page, owner["email"]);
        for (path, ready) in [
            ("/app", '[data-testid="cinema-list"]'),
            ("/app/new", "#cinema-slug"),
            (f"/app/{owner['slug']}", TITLE)
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
        }
        # One h1 per page, and headings never skip a level.
        levels = page.evaluate(
            "[...document.querySelectorAll('h1,h2,h3,h4')].map(h => +h.tagName[1])"
        );
        assert levels.count(1) == 1 , levels;
        assert all(b - a <= 1 for (a, b) in zip(levels, levels[1:])) , levels;
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the auth, wizard and back-office screens" {
    owner = owner_with_cinema();
    call(owner["token"], "end_shift", {"tenant": owner["slug"]});
    empty = email_for(unique("shots"));
    register(empty);
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for width in [375, 768, 1440] {
                page = browser.new_context(
                    viewport={"width": width, "height": 900}, color_scheme=scheme
                ).new_page();
                page.goto(BASE_URL + "/login");
                page.wait_for_selector("#email");
                _shot(page, "login", width, scheme);
                page.goto(BASE_URL + "/signup");
                page.wait_for_selector("#email");
                _shot(page, "signup", width, scheme);
                _sign_in(page, empty);
                page.wait_for_selector('[data-testid="no-cinemas"]');
                _shot(page, "picker-empty", width, scheme);
                page.goto(BASE_URL + "/app/new");
                _type(page, "#cinema-name", "Westgate Cinemas");
                _type(page, "#cinema-slug", "no--pe");
                page.locator("#cinema-slug").blur();
                page.wait_for_selector(f"{SLUG_STATUS}:has-text('hyphen')");
                _shot(page, "wizard-step1-error", width, scheme);
                page.evaluate("localStorage.removeItem('jac_token')");
                _sign_in(page, owner["email"]);
                page.wait_for_selector('[data-testid="cinema-list"]');
                _shot(page, "picker", width, scheme);
                _open_cinema(page, owner);
                page.wait_for_selector(BANNER);
                _shot(page, "backoffice-no-shift", width, scheme);
                page.evaluate("localStorage.removeItem('jac_token')");
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
