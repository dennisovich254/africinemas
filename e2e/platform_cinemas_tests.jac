"""P13.2 E2E: the platform's cinemas directory.

The platform's super admin opens Cinemas from the console's navigation, finds a cinema
by its owner's email (the search runs once typing pauses), opens its page and sees its
venue and screen, its owner and its figures; a state with no cinemas says so. Phone and
desktop, with the usual phone checks.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    PLATFORM_URL,
    PROJECTS,
    store_url,
    context_options,
    artifact
}
import from e2e.support.api {
    owner_with_cinema,
    add_venue,
    add_screen,
    platform_admin,
    PASSWORD
}

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

test "a super admin finds a cinema by its owner and opens its page" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema("Kisumu Lights");
            add_screen(owner, add_venue(owner, "Mega Plaza"), "Hall A");
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(PLATFORM_URL + "/sign-in");
            page.fill("#email", admin);  # jac:ignore[W6002]
            page.fill("#password", PASSWORD);  # jac:ignore[W6002]
            page.click('[data-testid="platform-sign-in"] button[type="submit"]');
            page.wait_for_selector('[data-testid="platform-overview"]');
            _go(page, project, "Cinemas");
            page.wait_for_selector('[data-testid="platform-cinemas"]');
            page.fill('[data-testid="cinema-search"]', owner["email"]);  # jac:ignore[W6002]
            row = page.locator(
                '[data-testid="platform-cinema"]', has_text=owner["slug"]
            );
            # The search runs once typing pauses: only this cinema then.
            page.wait_for_function(
                "document.querySelectorAll('[data-testid=platform-cinema]').length === 1"
            );
            row.wait_for();
            # Live: the browser tests' cinemas are approved (P14.1).
            assert "Active" in row.inner_text();
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: directory scrolls sideways";
            page.screenshot(
                path=artifact(f"platform-cinemas-{project}.png"), full_page=True
            );
            row.locator("a").click();
            page.wait_for_url(f"**/cinemas/{owner['slug']}");
            page.wait_for_selector('[data-testid="platform-cinema-page"]');
            shown = page.inner_text('[data-testid="platform-cinema-page"]');
            assert "Kisumu Lights" in shown and owner["email"] in shown , shown;
            assert "Mega Plaza" in page.inner_text('[data-testid="cinema-venues"]');
            assert "Hall A" in page.inner_text('[data-testid="cinema-venues"]');
            assert page.inner_text('[data-testid="cinema-tickets"]') == "0";
            assert "Signed up" in page.inner_text('[data-testid="cinema-history"]');
            # A new cinema's technical health: nothing to look at (P13.5c).
            assert "All clear" in page.inner_text('[data-testid="health-panel"]');
            # Its storefront on its own address, never through a tunnel.
            assert page.get_attribute('a:has-text("Open its storefront")', "href")
                == store_url(owner["slug"]) + "/";
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: cinema page scrolls sideways";
            page.screenshot(
                path=artifact(f"platform-cinema-page-{project}.png"), full_page=True
            );
            # Back to the directory; a state no cinema is in says so.
            page.click('a:has-text("All cinemas")');
            page.wait_for_selector('[data-testid="platform-cinemas"]');
            page.select_option('[data-testid="cinema-state"]', "suspended");
            page.wait_for_selector('[data-testid="cinemas-empty"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
