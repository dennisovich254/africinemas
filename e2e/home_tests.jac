"""P7.4 E2E: the back office's Overview, the first page staff see, on phone and desktop.

A brand-new cinema's owner sees the setup checklist (nothing done yet), quick actions
and no showtimes today. A cinema showing Rafiki in 90 minutes sells A1 and A2 for cash
(KES 1,660): its owner sees today's figures, the showtime with "2 of 11 sold" and the
sale in recent activity; an usher sees the showtime with Scan, and no figures or
setup. Off shift, the page says what starting one shows. Review screenshots.
"""

import uuid;
import from datetime { datetime, timedelta, timezone }
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { owner_with_cinema, add_staff, call, PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }

glob SALE: str = "KES 1,660";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_function("!!localStorage.getItem('jac_token')");
    page.wait_for_url(lambda (url: str) -> bool { return "/login" not in url; });
}

def _minutes_today -> int {
    # 90 minutes ahead, or less so the showtime stays on Nairobi's today (the home page
    # lists today's showtimes); in the day's last quarter hour it can't.
    nairobi = datetime.now(timezone.utc).astimezone(timezone(timedelta(hours=3)));
    left = (24 * 60) - (nairobi.hour * 60 + nairobi.minute);
    return max(5, min(90, left - 10));
}

def _showing_soon_with_a_sale -> dict[str, str] {
    # Rafiki later today, A1 and A2 sold for cash by the owner.
    owner = cinema_selling_tickets(starts_in_minutes=_minutes_today());
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

def _no_side_scroll(page: any) -> bool {  # jac:ignore[W1037]
    return page.evaluate(
        "document.documentElement.scrollWidth <= document.documentElement.clientWidth"
    );
}

test "a new cinema's owner sees the setup checklist, quick actions and no showtimes" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema();
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}");
            page.wait_for_selector('[data-testid="setup-checklist"]');
            assert _text(page, "setup-progress") == "0 of 7 done";
            assert page.locator('a[data-testid^="setup-"]').count() == 7;
            assert page.locator('[data-testid="home-no-showtimes"]').count() == 1;
            assert page.locator('[data-testid="quick-sell"]').count() == 1;
            assert "On shift" in _text(page, "shift-status");
            # The first step leads to Venues.
            page.click('[data-testid="setup-venue"]');
            page.wait_for_url(f"**/app/{owner['slug']}/venues");
            assert _no_side_scroll(page) , f"{project}: the page scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "after a sale, the owner sees today's figures, the showtime and the sale" {
    (pw, browser) = shared_browser();
    try {
        owner = _showing_soon_with_a_sale();
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}");
            page.wait_for_selector('[data-testid="home-showtime"]');
            assert _text(page, "today-net") == SALE;
            assert _text(page, "home-showtime-seats") == "2 of 11 sold";
            assert page.locator('[data-testid="home-sell"]').count() == 1;
            assert page.locator('[data-testid="home-scan"]').count() == 1;
            assert "Cash sale" in _text(page, "recent-activity");
            assert _no_side_scroll(page) , f"{project}: the page scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "an usher sees today's showtime with Scan, and no figures or setup" {
    (pw, browser) = shared_browser();
    try {
        owner = _showing_soon_with_a_sale();
        usher = add_staff(owner, "usher", owner["venue"]);
        assert call(usher["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_in(page, usher["email"]);
        page.goto(f"{BASE_URL}/app/{owner['slug']}");
        page.wait_for_selector('[data-testid="home-showtime"]');
        assert page.locator('[data-testid="home-scan"]').count() == 1;
        assert page.locator('[data-testid="home-sell"]').count() == 0;
        assert page.locator('[data-testid="today-net"]').count() == 0;
        assert page.locator('[data-testid="setup-checklist"]').count() == 0;
        assert page.locator('[data-testid="recent-activity"]').count() == 0;
    } finally {
        close_contexts(browser);
    }
}

test "off shift, the Overview says what starting a shift shows" {
    (pw, browser) = shared_browser();
    try {
        owner = owner_with_cinema();
        assert call(owner["token"], "end_shift", {"tenant": owner["slug"]})["ok"];
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"]);
        page.goto(f"{BASE_URL}/app/{owner['slug']}");
        page.wait_for_selector('[data-testid="home-off-shift"]');
        page.wait_for_selector('[data-testid="shift-banner"]');
        page.click('[data-testid="shift-banner"] button:has-text("Start shift")');
        page.wait_for_selector('[data-testid="setup-checklist"]');
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the Overview" {
    (pw, browser) = shared_browser();
    try {
        fresh = owner_with_cinema();
        busy = _showing_soon_with_a_sale();
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                for (name, owner, ready) in [
                    ("new", fresh, "setup-checklist"),
                    ("busy", busy, "home-showtime")
                ] {
                    page = browser.new_context(
                        **context_options(pw, project, scheme), reduced_motion="reduce"
                    ).new_page();
                    _sign_in(page, owner["email"]);
                    page.goto(f"{BASE_URL}/app/{owner['slug']}");
                    page.wait_for_selector(f'[data-testid="{ready}"]');
                    page.evaluate("document.fonts.ready");
                    page.screenshot(
                        path=artifact(f"home-{name}-{project}-{scheme}.png"),
                        full_page=True
                    );
                    page.context.close();
                }
            }
        }
    } finally {
        close_contexts(browser);
    }
}
