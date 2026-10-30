"""Seats kept for the counter, E2E (2026-10-30): on phone and desktop.

The owner opens a screen's page, Counter seats, ticks B5 and B6 and saves. On the
storefront those show as sold at the box office, and others can still be chosen. The
box office sees them marked and can choose them. On the Screenings page one showtime
keeps B4 as well, and the storefront shows that. Settings → Box office shows the
release time (2 hours). The rules themselves: tests/integration/counter_seats_tests.jac.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    store_url
}
import from e2e.support.api { PASSWORD, add_staff, call }
import from e2e.support.catalog { cinema_selling_tickets }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _sign_in(browser: any, pw: any, project: str, email: str) -> any {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, "light")).new_page();
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app**");
    return page;
}

def _seat(page: any, label: str) -> any {  # jac:ignore[W1037]
    return page.locator(f'[data-testid="seat"][data-seat="{label}"]');
}

def _storefront_state(  # jac:ignore[W3030] the browser, its kind, the cinema and the seat
    browser: any,  # jac:ignore[W1037]
    pw: any,  # jac:ignore[W1037]
    project: str,
    owner: dict[str, str],
    label: str
) -> str {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, "light")).new_page();
    page.goto(f"{store_url(owner['slug'])}/s/{owner['show']}");
    _seat(page, "A1").wait_for();
    state = _seat(page, label).get_attribute("data-state");
    words = _seat(page, label).get_attribute("aria-label");
    page.context.close();
    return f"{state}|{words}";
}

test "counter seats are chosen per screen and per showtime, and kept from online sale" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            agent = add_staff(owner, "box_office_agent", owner["venue"]);
            assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
            # The screen keeps B5 and B6 for the counter.
            page = _sign_in(browser, pw, project, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/screens/{owner['screen']}");
            page.click('[data-testid="screen-tab-counter"]');
            editor = page.locator('[data-testid="screen-counter-seats"]');
            editor.wait_for();
            for label in ["B5", "B6"] {
                editor.locator(f'[data-testid="seat"][data-seat="{label}"]').click();
            }
            editor.locator('button:has-text("Save counter seats")').click();
            page.wait_for_selector(
                '[role="status"]:has-text("2 seats kept for the counter")'
            );
            assert "B5, B6" in page.inner_text('[data-testid="counter-seats-count"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # Online: sold at the box office; the rest as before.
            said = _storefront_state(browser, pw, project, owner, "B5");
            assert said.startswith("not_for_sale|")
                and "sold at the box office" in said , said;
            assert _storefront_state(browser, pw, project, owner, "B3").startswith(
                "available|"
            );
            # One showtime keeps B4 too.
            page.goto(f"{BASE_URL}/app/{owner['slug']}/screenings");
            # The board shows a day at a time: the showtime's (this browser is in UTC).
            starts = call(
                owner["token"],
                "get_screening",
                {"tenant": owner["slug"], "screening_id": owner["show"]}
            )["screening"]["starts_at"];
            page.click(f'button[data-day="{starts[:10]}"]');
            page.locator('[data-testid="showtime-counter-seats"]').first.click();
            mine = page.locator('[data-testid="showtime-counter-editor"]');
            mine.wait_for();
            assert "B5, B6" in mine.inner_text();
            mine.locator('[data-testid="seat"][data-seat="B4"]').click();
            mine.locator('button:has-text("Save counter seats")').click();
            page.wait_for_selector(
                '[role="status"]:has-text("3 seats kept for the counter")'
            );
            assert _storefront_state(browser, pw, project, owner, "B4").startswith(
                "not_for_sale|"
            );
            # Settings → Box office: the release time.
            page.goto(f"{BASE_URL}/app/{owner['slug']}/settings/box-office");
            page.wait_for_selector("#counter-release");
            assert page.input_value("#counter-release") == "2";
            page.context.close();
            # The box office sees them marked, and can choose them.
            desk = _sign_in(browser, pw, project, agent["email"]);
            desk.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
            desk.wait_for_selector('[data-testid="counter-showtime"]');
            desk.click('[data-testid="counter-showtime"]');
            _seat(desk, "B5").wait_for();
            assert _seat(desk, "B5").get_attribute("data-counter") == "true";
            assert _seat(desk, "B5").get_attribute("data-state") == "available";
            assert "counter seat" in _seat(desk, "B5").get_attribute("aria-label");
            _seat(desk, "B5").click();
            desk.click('[data-testid="hold-seats"]');
            desk.wait_for_selector('[data-testid="checkout-total"]');
            desk.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
