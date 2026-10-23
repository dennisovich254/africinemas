"""P13.1 E2E: the AfriCinemas platform console and its staff.

The platform's super admin (AFRICINEMAS_PLATFORM_ADMINS, scripts/e2e_env.sh) finds the
console from Your cinemas, sees their role, and on Platform staff adds a reviewer by
email; the reviewer signs in and reaches the console but not Platform staff. Removed,
the reviewer is told the area is for AfriCinemas staff, as a cinema owner always is.
Signing in as a customer on a storefront in the same browser doesn't lock a super admin
out of the console. Phone and desktop, with the usual phone checks.
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
    owner_with_cinema,
    register,
    unique,
    email_for,
    platform_admin,
    PASSWORD
}

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    page.fill("#email", email);  # jac:ignore[W6002]
    page.fill("#password", PASSWORD);  # jac:ignore[W6002]
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
}

def _go(page: any, project: str, section: str) {  # jac:ignore[W1037]
    # A console section from its navigation: the drawer on a phone, the sidebar on desktop.
    if project == "mobile" {
        page.click('[data-testid="shell-menu-button"]');
        page.wait_for_selector('[data-testid="shell-drawer"]', state="visible");
        page.click(f'[data-testid="shell-drawer"] nav a:has-text("{section}")');
    } else {
        page.click(f'[data-testid="shell-sidebar"] nav a:has-text("{section}")');
    }
}

test "a super admin adds a reviewer, who reaches the console but not its staff page" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            reviewer = email_for(unique("reviewer"));
            register(reviewer);
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, admin);
            page.click('[data-testid="open-platform"]');
            page.wait_for_selector('[data-testid="platform-overview"]');
            assert page.inner_text('[data-testid="platform-role"]') == "Super admin";
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: overview scrolls sideways";
            _go(page, project, "Platform staff");
            page.wait_for_selector('[data-testid="platform-staff"]');
            assert admin in page.inner_text('[data-testid="platform-staff"]');
            page.fill("#platform-email", reviewer);  # jac:ignore[W6002]
            page.select_option("#platform-role", "reviewer");
            page.click('[data-testid="add-platform-member"] button[type="submit"]');
            page.wait_for_selector(
                f'[data-testid="platform-member"]:has-text("{reviewer}")'
            );
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: staff page scrolls sideways";
            page.screenshot(
                path=artifact(f"platform-staff-{project}.png"), full_page=True
            );
            # The reviewer: the console, without Platform staff.
            other = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(other, reviewer);
            other.goto(BASE_URL + "/platform");
            other.wait_for_selector('[data-testid="platform-overview"]');
            assert other.inner_text('[data-testid="platform-role"]') == "Reviewer";
            other.goto(BASE_URL + "/platform/staff");
            other.wait_for_selector('[data-testid="platform-no-access"]');
            # Removed: the area is closed to them.
            row = page.locator('[data-testid="platform-member"]', has_text=reviewer);
            row.locator('button:has-text("Remove")').click();
            row.locator('button:has-text("Remove")').last.click();
            page.wait_for_selector(
                '[data-testid="platform-message"]:has-text("Removed")'
            );
            other.goto(BASE_URL + "/platform");
            other.wait_for_selector('[data-testid="not-platform"]');
            page.context.close();
            other.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a cinema owner is told the platform console is for AfriCinemas staff" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_in(page, owner["email"]);
        assert page.locator('[data-testid="open-platform"]').count() == 0;
        page.goto(BASE_URL + "/platform");
        page.wait_for_selector('[data-testid="not-platform"]');
        assert "AfriCinemas staff" in page.inner_text('[data-testid="not-platform"]');
    } finally {
        close_contexts(browser);
    }
}

test "a customer sign-in in the same browser keeps a super admin's console" {
    # The customer sign-in once erased the staff email the console checks (2026-10-23).
    admin = platform_admin();
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, admin);
        page.goto(f"{BASE_URL}/c/{owner['slug']}/sign-up");
        page.wait_for_selector('[data-testid="customer-sign-up"]');
        page.fill("#name", "Kim");  # jac:ignore[W6002]
        page.fill("#email", email_for(unique("customer")));  # jac:ignore[W6002]
        page.fill("#password", PASSWORD);  # jac:ignore[W6002]
        page.click('[data-testid="customer-sign-up"] button[type="submit"]');
        page.wait_for_url(f"**/c/{owner['slug']}**");
        page.wait_for_selector('[data-testid="customer-sign-up"]', state="detached");
        page.goto(BASE_URL + "/platform");
        page.wait_for_selector('[data-testid="platform-overview"]');
        assert page.inner_text('[data-testid="platform-role"]') == "Super admin";
    } finally {
        close_contexts(browser);
    }
}
