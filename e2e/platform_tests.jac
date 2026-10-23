"""P13.1 and P13.1b.a E2E: the AfriCinemas platform console, its staff and their accounts.

The platform's super admin (AFRICINEMAS_PLATFORM_ADMINS, scripts/e2e_env.sh) signs in
on the platform's own sign-in page, with a platform account (e2e/support/api.jac,
platform_admin), sees their role, and on Platform staff invites a reviewer by email.
The reviewer opens the invitation link, chooses a password and reaches the console but
not Platform staff. Removed, the reviewer is told the area is for AfriCinemas staff. A
cinema owner's account can't sign in to the platform, a back-office sign-in doesn't
open the console, and signing in to a storefront or the back office in the same browser
leaves the console signed in. Phone and desktop, with the usual phone checks.
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
    unique,
    email_for,
    platform_admin,
    PASSWORD
}

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _platform_sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/platform/sign-in");
    page.fill("#email", email);  # jac:ignore[W6002]
    page.fill("#password", PASSWORD);  # jac:ignore[W6002]
    page.click('[data-testid="platform-sign-in"] button[type="submit"]');
    page.wait_for_selector('[data-testid="platform-overview"]');
}

def _staff_sign_in(page: any, email: str) {  # jac:ignore[W1037]
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

test "a super admin invites a reviewer, who joins and reaches the console but not its staff page" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            reviewer = email_for(unique("reviewer"));
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(BASE_URL + "/platform");
            page.wait_for_url("**/platform/sign-in");
            # No sign-up on the platform: joining is by invitation only.
            assert page.locator('a[href*="signup"], a[href*="sign-up"]').count() == 0;
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: sign-in scrolls sideways";
            page.screenshot(
                path=artifact(f"platform-sign-in-{project}.png"), full_page=True
            );
            _platform_sign_in(page, admin);
            assert page.inner_text('[data-testid="platform-role"]') == "Super admin";
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: overview scrolls sideways";
            _go(page, project, "Platform staff");
            page.wait_for_selector('[data-testid="platform-staff"]');
            assert admin in page.inner_text('[data-testid="platform-staff"]');
            page.fill("#platform-email", reviewer);  # jac:ignore[W6002]
            page.select_option("#platform-role", "reviewer");
            page.click('[data-testid="add-platform-member"] button[type="submit"]');
            page.wait_for_selector('[data-testid="platform-invite-link"]');
            link = page.input_value('[data-testid="platform-invite-address"]');
            assert "/platform/join#" in link , link;
            row = page.locator('[data-testid="platform-member"]', has_text=reviewer);
            assert row.locator('[data-testid="member-invited"]').count() == 1;
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: staff page scrolls sideways";
            page.screenshot(
                path=artifact(f"platform-staff-{project}.png"), full_page=True
            );
            # The reviewer: chooses a password from the link, then the console without
            # Platform staff.
            other = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            other.goto(link);
            other.wait_for_selector('[data-testid="platform-join"]');
            assert other.evaluate(WIDE_JS) <= 1 , f"{project}: join page scrolls sideways";
            other.screenshot(
                path=artifact(f"platform-join-{project}.png"), full_page=True
            );
            other.fill("#password", PASSWORD);  # jac:ignore[W6002]
            other.fill("#password-again", PASSWORD);  # jac:ignore[W6002]
            other.click('[data-testid="platform-join"] button[type="submit"]');
            other.wait_for_selector('[data-testid="platform-overview"]');
            assert "#" not in other.url , other.url;
            assert other.inner_text('[data-testid="platform-role"]') == "Reviewer";
            other.goto(BASE_URL + "/platform/staff");
            other.wait_for_selector('[data-testid="platform-no-access"]');
            # The link is spent.
            spent = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            spent.goto(link);
            spent.fill("#password", PASSWORD);  # jac:ignore[W6002]
            spent.fill("#password-again", PASSWORD);  # jac:ignore[W6002]
            spent.click('[data-testid="platform-join"] button[type="submit"]');
            spent.wait_for_selector(
                '[data-testid="auth-error"]:has-text("expired or was already used")'
            );
            # Removed: the area is closed to them.
            page.reload();
            page.wait_for_selector(
                f'[data-testid="platform-member"]:has-text("{reviewer}")'
            );
            row = page.locator('[data-testid="platform-member"]', has_text=reviewer);
            assert row.locator('[data-testid="member-invited"]').count() == 0;
            row.locator('button:has-text("Remove")').click();
            row.locator('button:has-text("Remove")').last.click();
            page.wait_for_selector(
                '[data-testid="platform-message"]:has-text("Removed")'
            );
            other.goto(BASE_URL + "/platform");
            other.wait_for_selector('[data-testid="not-platform"]');
            page.context.close();
            other.context.close();
            spent.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a cinema account can't sign in to the platform, and a back-office sign-in doesn't open it" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _staff_sign_in(page, owner["email"]);
        page.goto(BASE_URL + "/platform");
        page.wait_for_url("**/platform/sign-in");
        page.fill("#email", owner["email"]);  # jac:ignore[W6002]
        page.fill("#password", PASSWORD);  # jac:ignore[W6002]
        page.click('[data-testid="platform-sign-in"] button[type="submit"]');
        page.wait_for_selector(
            '[data-testid="auth-error"]:has-text("Email or password is incorrect")'
        );
        # Still signed in to the back office.
        page.goto(BASE_URL + "/app");
        page.wait_for_selector('text="Your cinemas"');
        assert page.url.endswith("/app") , page.url;
    } finally {
        close_contexts(browser);
    }
}

test "signing in to a storefront or the back office in the same browser keeps the console" {
    # A customer sign-in once erased what the console checked (2026-10-23); now each
    # part of the site keeps its own sign-in.
    admin = platform_admin();
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _platform_sign_in(page, admin);
        page.goto(f"{BASE_URL}/c/{owner['slug']}/sign-up");
        page.wait_for_selector('[data-testid="customer-sign-up"]');
        page.fill("#name", "Kim");  # jac:ignore[W6002]
        page.fill("#email", email_for(unique("customer")));  # jac:ignore[W6002]
        page.fill("#password", PASSWORD);  # jac:ignore[W6002]
        page.click('[data-testid="customer-sign-up"] button[type="submit"]');
        page.wait_for_url(f"**/c/{owner['slug']}**");
        page.wait_for_selector('[data-testid="customer-sign-up"]', state="detached");
        _staff_sign_in(page, owner["email"]);
        page.goto(BASE_URL + "/platform");
        page.wait_for_selector('[data-testid="platform-overview"]');
        assert page.inner_text('[data-testid="platform-role"]') == "Super admin";
        # Signing out of the platform leaves the back office signed in.
        page.click('[data-testid="platform-sign-out"]');
        page.wait_for_url("**/platform/sign-in");
        page.goto(BASE_URL + "/app");
        page.wait_for_selector('text="Your cinemas"');
    } finally {
        close_contexts(browser);
    }
}
