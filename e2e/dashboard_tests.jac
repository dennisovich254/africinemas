"""P7.3 E2E: the owner's dashboard (Reports) and the audit log, on phone and desktop.

A cinema selling tickets (Rafiki in two days; 11 seats on sale, Adult KES 800 + KES 30
fee) sells A1 and A2 for cash at the box office: KES 1,660, taken today. Reports shows
it on the day the money came in ("Today") and on the showtime's day ("Next 7 days":
2 tickets, 18.2% full); on a phone the tiles stack and nothing scrolls sideways; the
chart answers a tap or hover. The audit log lists the sale, pages with Previous and
Next, and narrows by action (a list that filters as you type) and by search. A box
office agent sees neither. Review screenshots of both pages.
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
import from e2e.support.snacks { with_snacks, made_by }

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
            # The money splits: one cash sale at the box office, tickets only.
            assert "100%" in _text(page, "split-method-right") , project;
            assert "Cash" in _text(page, "split-method-right");
            assert "100%" in _text(page, "split-channel-right");
            assert "100%" in _text(page, "split-items-left");
            # The donut: all the ticket revenue is Rafiki's.
            assert "Rafiki" in _text(page, "movie-share")
                and "100%" in _text(page, "movie-share");
            assert "Snacks" in _text(page, "takings-legend");
            # The occupancy meter leads the showtimes: 18.2% shows as 18%.
            assert "18%" in _text(page, "occupancy-meter") , project;
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

test "the audit log lists the sale, pages, and narrows by action and search" {
    (pw, browser) = shared_browser();
    try {
        owner = _cinema_with_a_sale();
        # Enough events for three pages (25 each): restarting a shift is recorded.
        for _ in range(50) {
            assert call(owner["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
        }
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"]);
        page.goto(f"{BASE_URL}/app/{owner['slug']}/audit");
        page.wait_for_selector('[data-testid="audit-log"]');
        rows = page.locator('[data-testid="responsive-table"] tbody tr');
        assert rows.count() == 25;
        pages = _text(page, "audit-page");
        assert pages.startswith("Page 1 of ")
            and int(pages.split(" of ")[1]) >= 3 , pages;
        assert page.locator('[data-testid="audit-prev"]').is_disabled();
        # Pages (improvements #12).
        page.click('[data-testid="audit-next"]');
        page.wait_for_selector('[data-testid="audit-page"]:has-text("Page 2 of")');
        # (The shift restarts read alike, so the count tells the pages apart.)
        assert _text(page, "audit-count").startswith("26–50 of ");
        total = int(pages.split(" of ")[1]);
        for n in range(3, total + 1) {
            page.click('[data-testid="audit-next"]');
            page.wait_for_selector(
                f'[data-testid="audit-page"]:has-text("Page {n} of")'
            );
        }
        assert page.locator('[data-testid="audit-next"]').is_disabled() , "the last page";
        for n in range(total - 1, 0, -1) {
            page.click('[data-testid="audit-prev"]');
            page.wait_for_selector(
                f'[data-testid="audit-page"]:has-text("Page {n} of")'
            );
        }
        # The action list narrows as you type.
        page.click('[data-testid="audit-action"]');
        page.keyboard.type("cash s");
        page.click('[role="option"]:has-text("Cash sale")');
        page.wait_for_function(
            "document.querySelectorAll('[data-testid=responsive-table] tbody tr').length === 1"
        );
        sale = _text(page, "responsive-table");
        assert "Cash sale" in sale and "Done" in sale , sale;
        assert _text(page, "audit-page") == "Page 1 of 1";
        # A search with no match says so.
        page.fill('[data-testid="audit-search"]', "no such person");  # jac:ignore[W6002]
        page.wait_for_selector(
            '[data-testid="audit-empty"]:has-text("Nothing matches")'
        );
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


test "snack reports show paid totals, rankings and current stock on phone and desktop" {
    (pw, browser) = shared_browser();
    try {
        owner = with_snacks();
        kiosk = made_by(
            owner,
            "create_venue",
            {"name": "Snack kiosk", "city": "Nairobi", "address": ""}
        )["venue"]["venue_id"];
        for (venue, size) in [(owner["venue"], "Large"), (kiosk, "Small")] {
            menu = made_by(owner, "counter_snack_menu", {"venue_id": venue})[
                "categories"
            ];
            popcorn = [
                p for c in menu
                for p in c["products"]
                if p["name"] == "Popcorn"
            ][0];
            variant = [
                v
                for v in popcorn["variants"]
                if v["option_values"] == [size]
            ][0];
            holder = f"counter-{uuid.uuid4().hex}";
            made_by(
                owner,
                "place_snack_order",
                {
                    "venue_id": venue,
                    "holder": holder,
                    "idempotency_key": f"snack-{uuid.uuid4().hex}",
                    "snacks": [{"variant_id": variant["variant_id"], "quantity": 1}]
                }
            );
            made_by(
                owner, "sell_snacks_for_cash", {"venue_id": venue, "holder": holder}
            );
        }
        for project in PROJECTS {
            for scheme in ["light", "dark"] {
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _sign_in(page, owner["email"]);
                page.goto(f"{BASE_URL}/app/{owner['slug']}/reports");
                _wait_text(page, "kpi-net", "KES 600");
                assert _text(page, "kpi-snack-net") == "KES 600";
                assert _text(page, "kpi-ticket-net") == "KES 0";
                assert "2 units sold" in _text(page, "snack-sales-summary");
                assert "KES 600" in _text(page, "top-snack-products");
                assert "Large" in _text(page, "top-snack-variants");
                assert "Small" in _text(page, "top-snack-variants");
                assert "Coca-Cola" in _text(page, "snack-low-stock");
                assert "Out of stock" in _text(page, "snack-low-stock");
                assert _no_side_scroll(page);
                assert page.locator("#report-venue").bounding_box()["height"] >= 44;
                page.screenshot(
                    path=artifact(f"snack-reports-{project}-{scheme}.png"),
                    full_page=True
                );
                if project == "mobile" {
                    for width in [375, 768] {
                        page.set_viewport_size({"width": width, "height": 900});
                        assert _no_side_scroll(page) , f"reports overflow at {width}px";
                        assert page.locator("#report-venue").bounding_box()["height"]
                            >= 44;
                        page.screenshot(
                            path=artifact(f"snack-reports-{width}-{scheme}.png"),
                            full_page=True
                        );
                    }
                    page.set_viewport_size({"width": 412, "height": 915});
                }
                page.select_option("#report-venue", kiosk);
                _wait_text(page, "kpi-net", "KES 200");
                assert _text(page, "kpi-snack-net") == "KES 200";
                assert "Large" not in _text(page, "top-snack-variants");
                assert "Snack kiosk" in _text(page, "snack-low-stock");
                _press(page, project, '[data-testid="preset-custom"]');
                _type(page, "#report-from", "2020-01-01");
                _type(page, "#report-to", "2020-01-01");
                _press(page, project, '[data-testid="custom-show"]');
                _wait_text(page, "kpi-net", "KES 0");
                assert "No snacks sold" in _text(page, "top-snack-products");
                assert "Out of stock" in _text(page, "snack-low-stock");
                assert _no_side_scroll(page);
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
