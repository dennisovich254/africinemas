"""P13.4 E2E: the platform overview on the console's home.

The platform's super admin signs in to the overview: the welcome and their role, then
the platform's figures (cinemas, sign-ups this week, bookings and takings over 14 days),
the takings chart with its table view (or a line saying nothing was sold), and cinemas
by state, which links to the
directory. Phone and desktop, with the usual phone checks.
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

test "a super admin sees the platform's figures on the overview" {
    admin = platform_admin();
    owner_with_cinema("Nakuru Nights");
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
            page.wait_for_selector('[data-testid="platform-figures"]');
            assert int(page.inner_text('[data-testid="overview-cinemas"]')) >= 1;
            assert page.inner_text('[data-testid="overview-takings"]').startswith(
                "KES"
            );
            # The chart, or, with nothing sold in 14 days, a line saying so.
            assert page.locator(
                '[data-testid="takings-chart"], [data-testid="overview-no-sales"]'
            ).count()
                == 1;
            assert "Setting up" in page.inner_text('[data-testid="overview-states"]');
            # Cinemas with technical problems (P13.5c): none in a fresh test run's.
            assert "Cinemas with technical problems"
                in page.inner_text('[data-testid="overview-problems"]');
            assert page.evaluate(WIDE_JS) <= 1 , f"{project}: overview scrolls sideways";
            page.screenshot(
                path=artifact(f"platform-overview-{project}.png"), full_page=True
            );
            page.click('[data-testid="overview-states"] a:has-text("All cinemas")');
            page.wait_for_selector('[data-testid="platform-cinemas"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
