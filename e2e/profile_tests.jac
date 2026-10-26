"""P12.15 E2E: Your profile, for every member of staff.

An usher (who sees neither Staff nor Settings) opens Your profile from the navigation,
sees the email they sign in with, saves their name and changes their password: a wrong
current password is refused in words, the right one changes it, and the new password
signs in. On a phone and on a desktop.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { PASSWORD, owner_with_cinema, add_staff }

glob PROFILE: str = '[data-testid="profile"]',
     NEW_PASSWORD: str = "Another-horse-43";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _sign_in(page: any, email: str, password: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", password);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app**");
}

def _change(page: any, current: str) {  # jac:ignore[W1037]
    _type(page, "#current-password", current);
    _type(page, "#new-password", NEW_PASSWORD);
    _type(page, "#new-password-again", NEW_PASSWORD);
    page.click('[data-testid="password-form"] button[type="submit"]');
}

test "an usher names themself and changes their password" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            usher = add_staff(owner, "usher");
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, usher["email"], PASSWORD);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/profile");
            page.wait_for_selector(PROFILE);
            assert usher["email"]
                in page.inner_text('[data-testid="profile-email"]') , project;
            _type(page, "#profile-name", "Wanjiru Usher");
            page.click('[data-testid="name-form"] button[type="submit"]');
            page.wait_for_selector('text="Your name is saved."');
            _change(page, "not-my-password");
            page.wait_for_selector('[data-testid="password-note"][role="alert"]');
            assert "current password"
                in page.inner_text('[data-testid="password-note"]') , project;
            _change(page, PASSWORD);
            page.wait_for_selector('text=/Your password is changed/');
            page.context.close();
            fresh = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(fresh, usher["email"], NEW_PASSWORD);
            fresh.goto(f"{BASE_URL}/app/{owner['slug']}/profile");
            fresh.wait_for_selector(PROFILE);
            assert fresh.input_value("#profile-name") == "Wanjiru Usher" , project;
            fresh.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
