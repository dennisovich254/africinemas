"""P14.5 E2E: a reviewer asks for changes, then approves; the cinema goes public, verified.

An owner submits their cinema's verification. The platform's super admin opens Reviews,
finds it, opens the ID photo, and asks for a change with a reason. The owner resubmits;
the reviewer ticks the checklist and approves. A visitor then finds the storefront, with
"Verified cinema" in its footer. Phone and desktop, no sideways scrolling.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    PLATFORM_URL,
    BASE_URL,
    MAIN_URL,
    PROJECTS,
    context_options,
    store_url,
    artifact
}
import from e2e.support.api { platform_admin, PASSWORD, call }
import from e2e.support.catalog { cinema_selling_tickets }
import from e2e.support.verification { submitted }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

test "changes are asked, then the cinema is approved and public with its badge" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets(live=False);
            submitted(owner);
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            _type(us, "#email", admin);
            _type(us, "#password", PASSWORD);
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.goto(PLATFORM_URL + "/reviews");
            row = f'[data-testid="review-row"][href="/reviews/{owner["slug"]}"]';
            us.wait_for_selector(row);
            us.click(row);
            us.wait_for_selector('[data-testid="review-page"]');
            assert "P051234567Q" in us.inner_text('[data-testid="review-page"]');
            us.click('[data-testid="open-id_front"]');
            us.wait_for_selector('[data-testid="shown-id_front"]');
            assert us.is_disabled('[data-testid="approve-verification"]');
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            _type(
                us,
                "#review-reasons",
                "The ID photo is blurred. Take it again in good light."
            );
            us.click('[data-testid="ask-changes"]');
            us.wait_for_function(
                "document.querySelector('[data-testid=review-status]').innerText === 'Changes asked'"
            );
            mine = call(owner["token"], "verification", {"tenant": owner["slug"]});
            assert mine["editable"] and "blurred" in mine["reasons"][0] , mine;
            # The owner resubmits, and the reviewer approves.
            assert call(
                owner["token"], "submit_verification", {"tenant": owner["slug"]}
            )["ok"];
            us.reload();
            us.wait_for_selector('[data-testid="review-decision"]');
            checks = us.locator('[data-testid="review-check"]');
            for n in range(checks.count()) {
                checks.nth(n).check();
            }
            us.click('[data-testid="approve-verification"]');
            us.wait_for_function(
                "document.querySelector('[data-testid=review-status]').innerText === 'Approved'"
            );
            us.context.close();
            # The owner's back office shows it.
            office = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            office.goto(BASE_URL + "/login");
            _type(office, "#email", owner["email"]);
            _type(office, "#password", PASSWORD);
            office.click('button[type="submit"]');
            office.wait_for_url("**/app");
            office.goto(f"{BASE_URL}/app/{owner['slug']}");
            # Beside the name in the sidebar (desktop) or the top bar (phone): one of the
            # two is hidden.
            office.wait_for_selector(
                '[data-testid="backoffice-verified"] >> visible=true'
            );
            # Its Verification page asks the owner to share the real link.
            office.goto(f"{BASE_URL}/app/{owner['slug']}/verification");
            office.wait_for_selector('[data-testid="share-link"]');
            assert owner["slug"] in office.inner_text('[data-testid="share-address"]');
            # And on Your cinemas.
            office.goto(f"{BASE_URL}/app");
            office.wait_for_selector('[data-testid="cinema-list"]');
            try {
                office.wait_for_selector(
                    f'[data-testid="cinema-list"] a[href="/app/{owner[
                        "slug"
                    ]}"] [data-testid="cinema-verified"]'
                );
            } except Exception as e {
                office.screenshot(
                    path=artifact(f"your-cinemas-{project}.png"), full_page=True
                );
                raise e;
            }
            office.context.close();
            visitor = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            visitor.goto(store_url(owner["slug"]) + "/");
            visitor.wait_for_selector('footer [data-testid="verified-badge"]');
            # And at the top, beside the logo. Neither is a link: a fake site could
            # link to a copy of any page.
            visitor.wait_for_selector('[data-testid="verified-pill"]');
            assert "Verified cinema"
                in visitor.inner_text('[data-testid="verified-badge"]');
            assert visitor.locator(
                'a[data-testid="verified-badge"], a[data-testid="verified-pill"]'
            ).count()
                == 0;
            # The check on AfriCinemas' own site, opened directly.
            visitor.goto(f"{MAIN_URL}/verified/{owner['slug']}");
            visitor.wait_for_selector('[data-testid="verified-yes"]');
            visitor.goto(f"{MAIN_URL}/verified/no-such-cinema-here");
            visitor.wait_for_selector('[data-testid="verified-no"]');
            visitor.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
