"""P15.1 E2E: accepting the cinema agreement, and the fee rule in the console.

A new cinema's owner sees the notice above the back office, opens the agreement, sees
the fee stated, ticks that they've read it and accepts it; the notice goes and the
page says who accepted which version. A super admin sees the rates in force on the
console's Fees page. Phone and desktop. A new version asking again is checked in
tests/integration/fee_agreement_tests.jac, since publishing one needs a test-only call.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PLATFORM_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { owner_with_cinema, platform_admin, PASSWORD }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     NOTICE: str = '[data-testid="agreement-notice"]';

def _go(page: any, project: str, section: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.click('[data-testid="shell-menu-button"]');
        page.wait_for_selector('[data-testid="shell-drawer"]', state="visible");
        page.click(f'[data-testid="shell-drawer"] nav a:has-text("{section}")');
    } else {
        page.click(f'[data-testid="shell-sidebar"] nav a:has-text("{section}")');
    }
}

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    page.fill("#email", email);  # jac:ignore[W6002]
    page.fill("#password", PASSWORD);  # jac:ignore[W6002]
    page.click('button[type="submit"]');
    page.wait_for_url("**/app**");
}

test "a new cinema's owner reads and accepts the cinema agreement" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema("Rupa Screens", live=False, agreed=False);
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}");
            page.wait_for_selector(NOTICE);
            page.click(f'{NOTICE} a:has-text("Read the agreement")');
            page.wait_for_selector(
                '[data-testid="agreement"] [data-testid="legal-text"]'
            );
            text = page.inner_text('[data-testid="legal-text"]');
            assert "7%" in text and "20%" in text and "3%" in text , project;
            assert "Not accepted yet"
                in page.inner_text('[data-testid="agreement-accepted"]');
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: agreement scrolls sideways";
            assert page.is_disabled('[data-testid="agreement-accept"] button');
            page.check("#agreement-read");
            page.click('[data-testid="agreement-accept"] button');
            page.wait_for_selector(
                '[data-testid="agreement-accepted"]:has-text("version 0.1")'
            );
            assert owner["email"]
                in page.inner_text('[data-testid="agreement-accepted"]');
            assert page.locator('[data-testid="agreement-accept"]').count() == 0;
            page.goto(f"{BASE_URL}/app/{owner['slug']}");
            # The phone shows the menu button; the desktop, the sidebar.
            page.wait_for_selector(
                '[data-testid="shell-menu-button"]'
                    if project == "mobile"
                    else '[data-testid="shell-sidebar"]'
            );
            page.wait_for_timeout(500);
            assert page.locator(NOTICE).count() == 0 , project;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "platform staff see the fee rule in force" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(PLATFORM_URL + "/sign-in");
            page.fill("#email", admin);  # jac:ignore[W6002]
            page.fill("#password", PASSWORD);  # jac:ignore[W6002]
            page.click('[data-testid="platform-sign-in"] button[type="submit"]');
            page.wait_for_selector('[data-testid="platform-overview"]');
            _go(page, project, "Fees");
            page.wait_for_selector('[data-testid="fees-current"]');
            shown = page.inner_text('[data-testid="fees-current"]');
            assert "7%" in shown and "20%" in shown and "3%" in shown , shown;
            assert page.locator('[data-testid="fee-form"]').count() == 1;
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: fees scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
