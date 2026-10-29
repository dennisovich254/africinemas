"""P15.0 E2E: a customer downloads their data, asks to delete the account, and keeps it.

A customer signs up on the storefront and opens Your account. Download my data saves a
JSON file with their account in it. Delete my account asks for the password: a wrong
one is refused; the right one says when it'll be deleted and what's kept, and the page
shows only that (the account is locked). Keep my account brings the page back. Phone
and PC, no sideways scrolling. The deletion itself, a week on: the integration test.
"""

import json;
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { unique, email_for, PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

test "a customer downloads their data, asks to delete the account, and keeps it" {
    owner = cinema_selling_tickets();
    slug = owner["slug"];
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            email = email_for(unique("kim"));
            page.goto(f"{BASE_URL}/c/{slug}/sign-up?next=/c/{slug}/account");
            page.wait_for_selector('[data-testid="customer-sign-up"]');
            _type(page, "#name", "Kim");
            _type(page, "#email", email);
            _type(page, "#password", PASSWORD);
            page.check('[data-testid="customer-sign-up"] #adult');
            page.click('[data-testid="customer-sign-up"] button[type="submit"]');
            page.wait_for_selector('[data-testid="your-data"]');
            # Download: a JSON file of what the cinema holds about them.
            with page.expect_download() as got {
                page.click('[data-testid="download-data"]');
            }
            assert got.value.suggested_filename == f"my-data-{slug}.json";
            with open(got.value.path(), encoding="utf-8") as f {
                data = json.load(f);
            }
            assert data["account"]["email"] == email and data["bookings"] == [] , data;
            assert len(data["kept_after_deletion"]) > 0;
            # Delete: the password first.
            page.click('[data-testid="delete-account"]');
            form = page.locator('[data-testid="delete-account-form"]');
            form.wait_for();
            assert "seven days" in form.inner_text();
            _type(page, "#delete-password", "not-my-password");
            form.locator('button[type="submit"]').click();
            page.wait_for_selector(
                '[data-testid="your-data"] [role="alert"]:has-text("isn\'t your password")'
            );
            _type(page, "#delete-password", PASSWORD);
            form.locator('button[type="submit"]').click();
            # Asked: when, and what's kept; the rest of the page is locked away.
            waiting = page.locator('[data-testid="account-deleting"]');
            waiting.wait_for();
            assert "will be deleted on" in waiting.inner_text();
            assert page.locator('[data-testid="account-kept"] li').count() > 0;
            assert page.locator('[data-testid="account-email"]').count() == 0;
            assert page.locator('[data-testid="delete-account"]').count() == 0;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # Still asked after a reload.
            page.reload();
            waiting.wait_for();
            # Kept: the page is back.
            page.click('[data-testid="keep-account"]');
            page.wait_for_selector('[data-testid="account-email"]');
            assert page.locator('[data-testid="account-deleting"]').count() == 0;
            assert page.locator('[data-testid="delete-account"]').count() == 1;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
