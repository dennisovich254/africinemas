"""P14.3b E2E: a cinema's policies, written in the back office and linked from its footer.

The owner opens Settings › Policies, starts the terms from our template, is asked to
tick they've read it, and publishes. On the cinema's own address a visitor finds the
link in the footer and reads the page; a policy that isn't published isn't found.
Phone and desktop, no sideways scrolling.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    store_url
}
import from e2e.support.api { PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SAVED_JS: str = "document.querySelector('[data-testid=policy-saved]').innerText.includes('Published')";

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

test "the owner publishes the terms from our template, and a visitor reads them" {
    owner = cinema_selling_tickets();
    store = store_url(owner["slug"]);
    (pw, browser) = shared_browser();
    try {
        for (n, project) in enumerate(PROJECTS) {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/settings/policies");
            page.wait_for_selector('[data-testid="policies"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.click('[data-testid="policy-terms"]');
            if n == 0 {
                page.click('[data-testid="use-template"]');
                assert "Your booking" in page.input_value("#policy-text");
                # Not without the tick.
                page.click('[data-testid="publish-policy"]');
                page.wait_for_selector('[data-testid="policy-editor"] [role="alert"]');
            }
            page.check("#policy-reviewed");
            page.click('[data-testid="publish-policy"]');
            page.wait_for_function(SAVED_JS);
            assert "Published" in page.inner_text('[data-testid="policy-terms"]');
            # A visitor, on the cinema's own address.
            page.goto(store + "/");
            link = 'footer [data-testid="info-policies"] a';
            page.wait_for_selector(link);
            assert page.inner_text(link) == "Terms of ticket sale";
            page.click(link);
            page.wait_for_selector('[data-testid="policy-page"]');
            assert page.url == f"{store}/policies/terms";
            body = page.inner_text('[data-testid="policy-page"]');
            assert "Terms of ticket sale" in body and "Your booking" in body;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: the policy scrolls sideways";
            page.goto(store + "/policies/privacy");
            page.wait_for_selector('[data-testid="policy-missing"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
