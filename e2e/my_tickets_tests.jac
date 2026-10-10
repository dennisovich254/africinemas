"""P6.3b E2E: "My tickets", a signed-in customer's saved bookings (simulated M-Pesa).

Customers have accounts at the cinema, made and used on its storefront (P8.6c:
/c/<slug>/sign-up and /sign-in, apart from the back office). A customer who is
signed in when they pay finds the booking in My tickets without a click: "You're
booked" saves it to their account by itself. A guest who pays creates an account from
the tickets, comes back to them, and they're saved then. A customer who signed out
signs in again from My tickets, and a back-office account is told it isn't this
cinema's. Review screenshots of the account pages and My tickets.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { register, unique, email_for, PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }

glob CONSOLE: list[str] = [],
     SETTLE_MS: int = 30000,
     ACCOUNT_STATES: str = '[data-testid="saved-to-account"], [data-testid="save-booking"], [data-testid="sign-in-to-save"]';

def _saved(page: any) {  # jac:ignore[W1037]
    # Waits for the tickets to be saved to the account; if they aren't, says what the
    # page shows instead (the Save button, the sign-in link, or "Saving..." stuck) and
    # what the browser logged.
    waited = "";
    try {
        page.wait_for_selector(ACCOUNT_STATES, timeout=SETTLE_MS);
    } except Exception as e {
        waited = str(e)[:200];
    }
    shown = page.inner_text('[data-testid="ticket-delivery"]');
    assert page.locator('[data-testid="saved-to-account"]').count() == 1 , (
        shown,
        waited,
        CONSOLE[-10:]
    );
}

def _press(page: any, project: str, selector: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.locator(selector).tap();
    } else {
        page.locator(selector).click();
    }
}

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _came_back(page: any, back_to: str) {  # jac:ignore[W1037]
    # Signed in, and back at `back_to`. Not a glob on `back_to`: the account page's own
    # URL (?next=...) matches one.
    page.wait_for_function("!!localStorage.getItem('jac_token')");
    page.wait_for_url(
        lambda (url: str) -> bool { return "/sign-" not in url
            and url.endswith(back_to); }
    );
}

def _fill_sign_up(page: any, email: str) {  # jac:ignore[W1037]
    page.wait_for_selector('[data-testid="customer-sign-up"]');
    _type(page, "#name", "Kim");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('[data-testid="customer-sign-up"] button[type="submit"]');
}

def _sign_up(page: any, slug: str, email: str, back_to: str) {  # jac:ignore[W1037]
    # Creates the customer's account at the cinema, which returns to `back_to`.
    page.goto(f"{BASE_URL}/c/{slug}/sign-up?next={back_to}");
    _fill_sign_up(page, email);
    _came_back(page, back_to);
}

def _book_and_pay(page: any, project: str, owner: dict[str, str]) {  # jac:ignore[W1037]
    # Holds A1 and A2, orders them, pays and waits for "You're booked".
    page.on("console", lambda (m: any) { CONSOLE.append(f"{m.type}: {m.text}"); });  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/c/{owner['slug']}/s/{owner['show']}");
    page.wait_for_selector('[data-testid="seat"][data-seat="A1"]');
    _press(page, project, '[data-testid="seat"][data-seat="A1"]');
    _press(page, project, '[data-testid="seat"][data-seat="A2"]');
    _press(page, project, '[data-testid="hold-seats"]');
    page.wait_for_function(
        "document.querySelector('[data-testid=checkout-total]')?.innerText === 'KES 1,660'"
    );
    _press(page, project, '[data-testid="pay"]');
    page.wait_for_selector('[data-testid="pay-panel"]');
    _type(page, "#mpesa-phone", "0712 345 678");
    _type(page, "#tickets-email", "kim@example.com");
    _press(page, project, '[data-testid="pay-mpesa"]');
    page.wait_for_selector('[data-testid="booked"]', timeout=SETTLE_MS);
}

test "a signed-in customer's booking is in My tickets without a click" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            email = email_for(unique("kim"));
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_up(
                page, owner["slug"], email, f"/c/{owner['slug']}/s/{owner['show']}"
            );
            _book_and_pay(page, project, owner);
            _saved(page);
            _press(page, project, '[data-testid="my-tickets-link"]');
            page.wait_for_selector('[data-testid="my-tickets"]');
            rows = page.locator('[data-testid="saved-booking"]');
            assert rows.count() == 1;
            row = rows.first.inner_text();
            assert "Rafiki" in row and "A1, A2" in row , row;
            _press(page, project, '[data-testid="open-saved-booking"]');
            page.wait_for_selector('[data-testid="tickets-page"]');
            assert page.locator('[data-testid="ticket"]').count() == 2;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a guest creates an account from the tickets, and they're saved on the way back" {
    owner = cinema_selling_tickets();
    email = email_for(unique("lee"));
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _book_and_pay(page, "mobile", owner);
        page.locator('[data-testid="open-tickets"]').tap();
        page.wait_for_selector('[data-testid="tickets-page"]');
        tickets_path = page.url.replace(BASE_URL, "");
        page.locator('[data-testid="sign-up-to-save"]').tap();
        page.wait_for_url(
            lambda (url: str) -> bool { return f"/c/{owner['slug']}/sign-up?next="
                in url; }
        );
        _fill_sign_up(page, email);
        _came_back(page, tickets_path);
        _saved(page);
        page.goto(f"{BASE_URL}/c/{owner['slug']}/my-tickets");
        page.wait_for_selector('[data-testid="saved-booking"]');
        assert page.locator('[data-testid="saved-booking"]').count() == 1;
    } finally {
        close_contexts(browser);
    }
}

test "a customer who signed out signs in again from My tickets" {
    owner = cinema_selling_tickets();
    slug = owner["slug"];
    email = email_for(unique("ada"));
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_up(page, slug, email, f"/c/{slug}");
        page.wait_for_selector('[data-testid="account-my-tickets"]');
        page.click('[data-testid="account-sign-out"]');
        page.wait_for_selector('[data-testid="account-sign-in"]');
        page.goto(f"{BASE_URL}/c/{slug}/my-tickets");
        page.wait_for_selector('[data-testid="my-tickets-signed-out"]');
        page.click('[data-testid="sign-in-for-tickets"]');
        page.wait_for_url(f"**/c/{slug}/sign-in?next=/c/{slug}/my-tickets");
        # A wrong password says so, and stays.
        _type(page, "#email", email);
        _type(page, "#password", "not-the-password");
        page.click('[data-testid="customer-sign-in"] button[type="submit"]');
        page.wait_for_selector('[role="alert"]');
        _type(page, "#password", PASSWORD);
        page.click('[data-testid="customer-sign-in"] button[type="submit"]');
        _came_back(page, f"/c/{slug}/my-tickets");
        page.wait_for_selector('[data-testid="no-saved-tickets"]');
    } finally {
        close_contexts(browser);
    }
}

test "a back-office account isn't a customer of the storefront" {
    owner = cinema_selling_tickets();
    slug = owner["slug"];
    email = email_for(unique("staff"));
    register(email);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        page.goto(f"{BASE_URL}/login");
        _type(page, "#email", email);
        _type(page, "#password", PASSWORD);
        page.click('button[type="submit"]');
        page.wait_for_url("**/app**");
        page.goto(f"{BASE_URL}/c/{slug}/my-tickets");
        signed_out = page.wait_for_selector('[data-testid="my-tickets-signed-out"]');
        assert "isn't for this cinema" in signed_out.inner_text();
        # The header offers this cinema's sign-in, not the staff account.
        page.wait_for_selector('[data-testid="account-sign-in"]');
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of My tickets" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = cinema_selling_tickets();
                email = email_for(unique("shot"));
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                for which in ["sign-in", "sign-up"] {
                    page.goto(f"{BASE_URL}/c/{owner['slug']}/{which}");
                    page.wait_for_selector(f'[data-testid="customer-{which}"]');
                    page.evaluate("document.fonts.ready");
                    page.screenshot(
                        path=artifact(f"customer-{which}-{project}-{scheme}.png"),
                        full_page=True
                    );
                }
                _sign_up(
                    page, owner["slug"], email, f"/c/{owner['slug']}/s/{owner['show']}"
                );
                _book_and_pay(page, project, owner);
                _saved(page);
                page.screenshot(
                    path=artifact(f"booked-saved-{project}-{scheme}.png"),
                    full_page=True
                );
                page.goto(f"{BASE_URL}/c/{owner['slug']}/my-tickets");
                page.wait_for_selector('[data-testid="saved-booking"]');
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"my-tickets-{project}-{scheme}.png"), full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
