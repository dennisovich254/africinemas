"""P13.1b.c E2E: each cinema's storefront on its own address.

Under the test server's domain (localhost, scripts/e2e_env.sh) a cinema's storefront is
<slug>.localhost, its pages at "/", "/movies", "/s/<showtime>"... A link in the old form
on the main address (/c/<slug>/...) lands on the same page at the cinema's address. A
customer books and pays there, signs up and finds the booking in My tickets, and is
signed out on another cinema's address. An address that's no cinema's isn't found.
Phone and desktop.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    MAIN_URL,
    PROJECTS,
    context_options,
    artifact,
    store_url
}
import from e2e.support.api { unique, email_for, PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }

glob SETTLE_MS: int = 30000,
     WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

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

test "old links land on the same page at the cinema's own address" {
    owner = cinema_selling_tickets();
    store = store_url(owner["slug"]);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        page.goto(f"{MAIN_URL}/c/{owner['slug']}/movies");
        page.wait_for_url(f"{store}/movies");
        page.goto(f"{MAIN_URL}/c/{owner['slug']}/s/{owner['show']}?from=mail#seats");
        page.wait_for_url(f"{store}/s/{owner['show']}?from=mail#seats");
        page.wait_for_selector('[data-testid="seat"][data-seat="A1"]');
        page.goto(f"{MAIN_URL}/c/{owner['slug']}");
        page.wait_for_url(f"{store}/");
        # The storefront's own links stay on its address.
        page.click('a[href="/movies"]');
        page.wait_for_url(f"{store}/movies");
        # An address that's no cinema's.
        page.goto(store_url("no-such-cinema-here") + "/");
        page.wait_for_selector('[data-testid="not-found"]');
    } finally {
        close_contexts(browser);
    }
}

test "a customer books and pays on a cinema's own address, and it's in My tickets there" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            store = store_url(owner["slug"]);
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            # Signs up on the cinema's address, back to the showtime.
            page.goto(f"{store}/sign-up?next=/s/{owner['show']}");
            page.wait_for_selector('[data-testid="customer-sign-up"]');
            _type(page, "#name", "Kim");
            _type(page, "#email", email_for(unique("kim")));
            _type(page, "#password", PASSWORD);
            page.check('[data-testid="customer-sign-up"] #adult');  # "I'm 18 or over" (P15.0)
            _press(
                page, project, '[data-testid="customer-sign-up"] button[type="submit"]'
            );
            page.wait_for_url(f"{store}/s/{owner['show']}");
            page.wait_for_selector('[data-testid="seat"][data-seat="A1"]');
            _press(page, project, '[data-testid="seat"][data-seat="A1"]');
            _press(page, project, '[data-testid="seat"][data-seat="A2"]');
            _press(page, project, '[data-testid="hold-seats"]');
            page.wait_for_selector('[data-testid="pay"]');
            _press(page, project, '[data-testid="pay"]');
            page.wait_for_selector('[data-testid="pay-panel"]');
            _type(page, "#mpesa-phone", "0712 345 678");
            _type(page, "#tickets-email", "kim@example.com");
            page.check("#adult");  # "I'm 18 or over" (P15.0)
            _press(page, project, '[data-testid="pay-mpesa"]');
            page.wait_for_selector('[data-testid="booked"]', timeout=SETTLE_MS);
            page.wait_for_selector(
                '[data-testid="saved-to-account"]', timeout=SETTLE_MS
            );
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: scrolls sideways";
            page.screenshot(
                path=artifact(f"storefront-address-booked-{project}.png"),
                full_page=True
            );
            _press(page, project, '[data-testid="my-tickets-link"]');
            page.wait_for_url(f"{store}/my-tickets");
            page.wait_for_selector('[data-testid="saved-booking"]');
            _press(page, project, '[data-testid="open-saved-booking"]');
            page.wait_for_url(f"{store}/tickets/**");
            page.wait_for_selector('[data-testid="tickets-page"]');
            assert page.locator('[data-testid="ticket"]').count() == 2;
            # Another cinema's address knows nothing of this sign-in.
            other = cinema_selling_tickets();
            page.goto(store_url(other["slug"]) + "/my-tickets");
            page.wait_for_selector('[data-testid="my-tickets-signed-out"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
