"""P7.3 E2E: the owner's dashboard (Reports) and the audit log, on phone and desktop.

A cinema selling tickets (Rafiki in two days; 11 seats on sale, Adult KES 800 + KES 30
fee) sells A1 and A2 for cash at the box office: KES 1,660, taken today. Reports shows
it on the day the money came in ("Today") and on the showtime's day ("Next 7 days":
2 tickets, 18.2% full); on a phone the tiles stack and nothing scrolls sideways; the
chart answers a tap or hover. The audit log lists the sale, filters by action and pages
with "Load more". A box office agent sees neither. Review screenshots of both pages.
"""

import uuid;
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { add_staff, call, PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }

glob SALE: str = "KES 1,660";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _press(page: any, project: str, selector: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.locator(selector).first.tap();
    } else {
        page.locator(selector).first.click();
    }
}

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_function("!!localStorage.getItem('jac_token')");
    page.wait_for_url(lambda (url: str) -> bool { return "/login" not in url; });
}

def _cinema_with_a_sale -> dict[str, str] {
    # The owner sells A1 and A2 (two Adults) for cash at the counter, through the API.
    owner = cinema_selling_tickets();
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": owner["slug"], "screening_id": owner["show"], "holder": holder};
    assert call("", "hold_seats", {** where, "labels": ["A1", "A2"]})["ok"];
    ordered = call(
        "",
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [
                {"seat_label": "A1", "ticket_type": "ADULT"},
                {"seat_label": "A2", "ticket_type": "ADULT"}
            ]
        }
    );
    assert ordered["ok"] , ordered;
    sold = call(
        owner["token"],
        "sell_for_cash",
        {
            "tenant": owner["slug"],
            "screening_id": owner["show"],
            "holder": holder,
            "email": ""
        }
    );
    assert sold["ok"] , sold;
    return owner;
}

def _text(page: any, testid: str) -> str {  # jac:ignore[W1037]
    return page.inner_text(f'[data-testid="{testid}"]').strip();
}

def _wait_text(page: any, testid: str, value: str) {  # jac:ignore[W1037]
    page.wait_for_function(
        f"document.querySelector('[data-testid={testid}]')?.innerText.trim() === '{value}'"
    );
}

def _no_side_scroll(page: any) -> bool {  # jac:ignore[W1037]
    return page.evaluate(
        "document.documentElement.scrollWidth <= document.documentElement.clientWidth"
    );
}

test "after a cash sale, Reports shows matching totals, today and for the showtime" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = _cinema_with_a_sale();
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            # The Overview leads with today's figures.
            page.goto(f"{BASE_URL}/app/{owner['slug']}");
            _wait_text(page, "today-net", SALE);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/reports");
            # Today: the money came in today; the showtime is in two days.
            _wait_text(page, "kpi-net", SALE);
            assert _text(page, "kpi-counter") == SALE;
            assert _text(page, "kpi-tickets") == "0";
            # Next 7 days: the showtime is in it, so are its tickets.
            _press(page, project, '[data-testid="preset-next7"]');
            _wait_text(page, "kpi-tickets", "2");
            assert _text(page, "kpi-net") == SALE;
            assert _text(page, "kpi-occupancy") == "18.2%";
            assert "Rafiki" in _text(page, "top-movies");
            assert page.locator('[data-testid="chart-bar"]').count() == 7;
            # The chart answers a tap or a hover with the day's figures.
            _press(page, project, '[data-testid="chart-bar"]');
            assert SALE in _text(page, "chart-readout");
            assert _no_side_scroll(page) , f"{project}: the page scrolls sideways";
            if project == "mobile" {
                # Tiles stack: the first two start at the same left edge.
                first = page.locator('[data-testid="kpi-net"]').bounding_box();
                second = page.locator('[data-testid="kpi-gross"]').bounding_box();
                assert abs(first["x"] - second["x"]) < 2 and second["y"] > first["y"];
            }
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the audit log lists the sale, filters by action and pages with Load more" {
    (pw, browser) = shared_browser();
    try {
        owner = _cinema_with_a_sale();
        # Enough events for two pages (50 each): restarting a shift is recorded.
        for _ in range(50) {
            assert call(owner["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
        }
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"]);
        page.goto(f"{BASE_URL}/app/{owner['slug']}/audit");
        page.wait_for_selector('[data-testid="audit-log"]');
        page.wait_for_selector('[data-testid="audit-more"]');
        rows = page.locator('[data-testid="responsive-table"] tbody tr');
        assert rows.count() == 50;
        page.click('[data-testid="audit-more"]');
        page.wait_for_function(
            "document.querySelectorAll('[data-testid=responsive-table] tbody tr').length > 50"
        );
        assert page.locator('[data-testid="audit-more"]').count() == 0;
        page.select_option('[data-testid="audit-action"]', "sale.cash");
        page.wait_for_function(
            "document.querySelectorAll('[data-testid=responsive-table] tbody tr').length === 1"
        );
        sale = _text(page, "responsive-table");
        assert "Cash sale" in sale and "Done" in sale , sale;
    } finally {
        close_contexts(browser);
    }
}

test "a box office agent sees neither Reports nor the audit log" {
    (pw, browser) = shared_browser();
    try {
        owner = cinema_selling_tickets();
        agent = add_staff(owner, "box_office_agent", owner["venue"]);
        assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, agent["email"]);
        page.goto(f"{BASE_URL}/app/{owner['slug']}");
        page.wait_for_selector('nav a');
        links = page.locator("nav").inner_text();
        assert "Reports" not in links and "Audit log" not in links , links;
        assert page.locator('[data-testid="today-net"]').count() == 0;
        for section in ["reports", "audit"] {
            page.goto(f"{BASE_URL}/app/{owner['slug']}/{section}");
            page.wait_for_selector('[data-testid="no-access"]');
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of Reports and the audit log" {
    (pw, browser) = shared_browser();
    try {
        owner = _cinema_with_a_sale();
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _sign_in(page, owner["email"]);
                page.goto(f"{BASE_URL}/app/{owner['slug']}/reports");
                _wait_text(page, "kpi-net", SALE);
                _press(page, project, '[data-testid="preset-next7"]');
                _wait_text(page, "kpi-tickets", "2");
                _press(page, project, '[data-testid="chart-bar"]');
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"reports-{project}-{scheme}.png"), full_page=True
                );
                page.goto(f"{BASE_URL}/app/{owner['slug']}/audit");
                page.wait_for_selector('[data-testid="audit-log"]');
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"audit-{project}-{scheme}.png"), full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
