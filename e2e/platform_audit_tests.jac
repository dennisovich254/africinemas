"""P13.3 E2E: the platform's own audit log.

The platform's super admin signs in, which goes on record, and opens the Audit log from
the console's navigation: their sign-in is there, with their email, in words. The search
narrows it to them; from a cinema's page, its own events (its approval) are a click away,
and the cinema filter clears. Phone and desktop, with the usual phone checks.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    PLATFORM_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { owner_with_cinema, platform_admin, PASSWORD }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _go(page: any, project: str, section: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.click('[data-testid="shell-menu-button"]');
        page.wait_for_selector('[data-testid="shell-drawer"]', state="visible");
        page.click(f'[data-testid="shell-drawer"] nav a:has-text("{section}")');
    } else {
        page.click(f'[data-testid="shell-sidebar"] nav a:has-text("{section}")');
    }
}

test "a super admin's sign-in is in the platform's audit log" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema("Mombasa Screens");
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(PLATFORM_URL + "/sign-in");
            page.fill("#email", admin);  # jac:ignore[W6002]
            page.fill("#password", PASSWORD);  # jac:ignore[W6002]
            page.click('[data-testid="platform-sign-in"] button[type="submit"]');
            page.wait_for_selector('[data-testid="platform-overview"]');
            _go(page, project, "Audit log");
            page.wait_for_selector('[data-testid="platform-audit-log"]');
            shown = page.inner_text('[data-testid="platform-audit-log"]');
            assert "Signed in" in shown and admin in shown and "Done" in shown , shown;
            page.fill('[data-testid="platform-audit-search"]', admin);  # jac:ignore[W6002]
            page.wait_for_selector(
                '[data-testid="platform-audit-log"]:has-text("Signed in")'
            );
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: audit log scrolls sideways";
            page.screenshot(
                path=artifact(f"platform-audit-{project}.png"), full_page=True
            );
            # A cinema's own events, on its page's Logs tab: its approval (P14.1).
            page.goto(f"{PLATFORM_URL}/cinemas/{owner['slug']}");
            page.click('[data-testid="cinema-tab-logs"]');
            page.wait_for_selector(
                '[data-testid="platform-audit-log"]:has-text("Approved a cinema")'
            );
            # Fixed to this cinema there; the audit log's own filter can be cleared.
            assert page.locator('[data-testid="platform-audit-cinema"]').count() == 0;
            page.goto(f"{PLATFORM_URL}/audit?cinema={owner['slug']}");
            page.wait_for_selector('[data-testid="platform-audit-cinema"]');
            page.wait_for_selector(
                '[data-testid="platform-audit-log"]:has-text("Approved a cinema")'
            );
            page.click('a:has-text("Show every cinema")');
            page.wait_for_selector('[data-testid="platform-audit-log"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
