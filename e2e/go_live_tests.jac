"""P14.1 E2E: only an active cinema is public.

An owner's new cinema, not yet approved: a visitor to its address finds nothing. The
owner opens "View storefront" from the back office: their storefront, under a banner
saying only their team can see it. A reviewer approves it in the platform console, and
the visitor's page is the storefront, with no banner. Phone and desktop.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PLATFORM_URL,
    PROJECTS,
    context_options,
    artifact,
    store_url
}
import from e2e.support.api { owner_with_cinema, platform_admin, PASSWORD }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

test "a new cinema is its team's to preview until a reviewer makes it public" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema("Nyeri Nights", live=False);
            store = store_url(owner["slug"]);
            # A visitor: nothing there.
            visitor = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            visitor.goto(store + "/");
            visitor.wait_for_selector('[data-testid="not-found"]');
            # The owner, from the back office: the preview, under its banner.
            staff = browser.new_context(**context_options(pw, project, "light"));
            page = staff.new_page();
            page.goto(BASE_URL + "/login");
            page.fill("#email", owner["email"]);  # jac:ignore[W6002]
            page.fill("#password", PASSWORD);  # jac:ignore[W6002]
            page.click('button[type="submit"]');
            page.wait_for_url("**/app");
            page.goto(f"{BASE_URL}/app/{owner['slug']}");
            link = page.locator('[data-testid="view-storefront"]');
            page.wait_for_function(
                "document.querySelector('[data-testid=view-storefront]')?.href.includes('#preview=')"
            );
            with staff.expect_page() as opened {
                link.click();
            }
            preview = opened.value;
            preview.wait_for_selector('[data-testid="preview-banner"]');
            assert "#preview=" not in preview.url , preview.url;
            try {
                preview.wait_for_function(
                    "document.body.innerText.includes('Nyeri Nights')", timeout=15000
                );
            } except Exception as e {
                preview.screenshot(
                    path=artifact(f"preview-failed-{project}.png"), full_page=True
                );
                raise e;
            }
            assert preview.evaluate(WIDE_JS) <= 1 , f"{project}: preview scrolls sideways";
            preview.screenshot(path=artifact(f"preview-{project}.png"), full_page=True);
            # A reviewer approves it.
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            us.fill("#email", admin);  # jac:ignore[W6002]
            us.fill("#password", PASSWORD);  # jac:ignore[W6002]
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.goto(f"{PLATFORM_URL}/cinemas/{owner['slug']}");
            us.click('[data-testid="approve-cinema"]');
            us.wait_for_selector(
                '[data-testid="cinema-state-label"]:has-text("Active")'
            );
            # Public now: the visitor sees it, with no banner.
            visitor.reload();
            visitor.wait_for_function(
                "document.body.innerText.includes('Nyeri Nights')"
            );
            assert visitor.locator('[data-testid="not-found"]').count() == 0;
            assert visitor.locator('[data-testid="preview-banner"]').count() == 0;
            visitor.context.close();
            staff.close();
            us.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
