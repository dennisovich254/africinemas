"""P15.0b E2E: AfriCinemas' legal pages, the links to them, and the registrations
checklist.

A visitor opens the terms of use from the main site's footer and sees the version, the
review note and the text; the wide tables of the cinema agreement and the privacy policy
never make the phone page scroll sideways; an unknown document says so. The sign-up page
links the terms and privacy policy, and a cinema's storefront footer links all three
customer documents on the main site. A super admin ticks a registration in the console
and sees who ticked it. Phone and desktop.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    MAIN_URL,
    PLATFORM_URL,
    PROJECTS,
    context_options,
    store_url
}
import from e2e.support.api { owner_with_cinema, platform_admin, PASSWORD }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     VERSION: str = '[data-testid="legal-version"]',
     TEXT: str = '[data-testid="legal-text"]';

def _go(page: any, project: str, section: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.click('[data-testid="shell-menu-button"]');
        page.wait_for_selector('[data-testid="shell-drawer"]', state="visible");
        page.click(f'[data-testid="shell-drawer"] nav a:has-text("{section}")');
    } else {
        page.click(f'[data-testid="shell-sidebar"] nav a:has-text("{section}")');
    }
}

test "the legal pages are linked from the main site, sign-up and every storefront" {
    owner = owner_with_cinema("Eldoret Screens");
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(BASE_URL + "/");
            page.click('[data-testid="landing-legal"] a:has-text("Terms of use")');
            page.wait_for_selector(VERSION);
            assert "reviewed by our lawyers" in page.inner_text(VERSION) , project;
            assert "AfriCinemas terms of use" in page.inner_text(f"{TEXT} h1");
            for name in ["cinema-agreement", "privacy"] {
                page.goto(f"{BASE_URL}/legal/{name}");
                page.wait_for_selector(f"{TEXT} table");
                assert page.evaluate(WIDE_JS) <= 1 , f"{project}: {name} scrolls sideways";
            }
            page.goto(BASE_URL + "/legal/nothing-here");
            page.wait_for_selector('[data-testid="legal-missing"]');
            page.goto(BASE_URL + "/signup");
            page.wait_for_selector('[data-testid="signup-legal"]');
            assert page.get_attribute(
                '[data-testid="signup-legal"] a:has-text("terms of use")', "href"
            )
                == "/legal/terms";
            # A storefront's footer links the documents on the main site.
            page.goto(store_url(owner["slug"]));
            page.wait_for_selector('[data-testid="info-legal"]');
            cookies = page.get_attribute(
                '[data-testid="info-legal"] a:has-text("Cookies and storage")', "href"
            );
            assert cookies == f"{MAIN_URL}/legal/cookies" , cookies;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a super admin ticks a registration in the console" {
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
            _go(page, project, "Registrations");
            page.wait_for_selector('[data-testid="registrations"]');
            row = page.locator(
                '[data-testid="registration"]', has_text="Domain africinemas.co.ke"
            );
            if "Done"
                in row.locator('[data-testid="registration-state"]').inner_text() {
                row.locator('button:has-text("Untick")').click();
                row.locator('button:has-text("Mark as done")').wait_for();
            }
            row.locator("input").fill(f"Renews 2027 ({project})");  # jac:ignore[W6002]
            row.locator('button:has-text("Mark as done")').click();
            row.locator(f'text=/Ticked by {admin}/').wait_for();
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: checklist scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
