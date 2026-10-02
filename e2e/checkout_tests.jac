"""P4.6 E2E: the seat map and checkout, on a phone and a desktop.

Pick a showtime, choose two seats (tap on a phone, click on a desktop), hold them and
see the timer, choose tickets and see the server's total, then proceed to pay: the
order waits for payment (Phase 5), and a reload comes back to it. On a phone the seat
map fits the width and zooms inside its own box, and the bar with the seats and total
stays on screen. Seats can be chosen with the keyboard alone. A seat someone else holds
can't be chosen. Review screenshots of each step.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call }
import from e2e.support.catalog { cinema_selling_tickets }

glob CHECKOUT: str = '[data-testid="checkout"]',
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    'a[href], button, summary, select, input')]
  .filter(e => e.dataset.testid !== 'seat')
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""",
     SEAT_WIDTH_JS: str = "document.querySelector('[data-seat=\"A1\"]').getBoundingClientRect().width",
     SCROLLER_JS: str = "(() => { const s = document.querySelector('[data-testid=seat-scroller]'); return s.scrollWidth - s.clientWidth; })()",
     BAR_ON_SCREEN_JS: str = "(() => { const r = document.querySelector('[data-testid=checkout-bar]').getBoundingClientRect(); return r.top >= 0 && r.bottom <= window.innerHeight + 1; })()";

def _seat(label: str) -> str {
    return f'[data-testid="seat"][data-seat="{label}"]';
}

def _open(page: any, owner: dict[str, str]) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/c/{owner['slug']}/s/{owner['show']}");
    page.wait_for_selector(_seat("A1"));
}

def _press(page: any, project: str, selector: str) {  # jac:ignore[W1037]
    # A tap on a phone, a click on a desktop.
    if project == "mobile" {
        page.locator(selector).tap();
    } else {
        page.locator(selector).click();
    }
}

test "choose two seats, hold them, choose tickets and proceed to pay" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _open(page, owner);
            _press(page, project, _seat("A1"));
            _press(page, project, _seat("A2"));
            assert page.get_attribute(_seat("A2"), "aria-pressed") == "true";
            assert page.inner_text('[data-testid="chosen-seats"]') == "2 seats: A1, A2";
            _press(page, project, '[data-testid="hold-seats"]');
            page.wait_for_selector('[data-testid="hold-timer"]');
            timer = page.inner_text('[data-testid="hold-timer"]');
            assert "Seats held for 7:" in timer or "Seats held for 8:" in timer , timer;
            page.select_option('#ticket-A2', "CHILD");
            page.wait_for_function(
                "document.querySelector('[data-testid=checkout-total]').innerText === 'KES 1,360'"
            );
            _press(page, project, '[data-testid="pay"]');
            page.wait_for_selector('[data-testid="order-placed"]');
            reference = page.inner_text('[data-testid="order-reference"]');
            assert len(reference) == 8 , reference;
            assert page.inner_text('[data-testid="order-total"]') == "KES 1,360";
            # A reload comes back to the same order.
            page.reload();
            page.wait_for_selector('[data-testid="order-placed"]');
            assert page.inner_text('[data-testid="order-reference"]') == reference;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "seats can be chosen and held with the keyboard alone" {
    owner = cinema_selling_tickets();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _open(page, owner);
        page.focus(_seat("A1"));
        page.keyboard.press("ArrowRight");
        page.keyboard.press("Enter");
        page.keyboard.press("ArrowDown");
        page.keyboard.press("Space");
        assert page.evaluate("document.activeElement.dataset.seat") == "B2";
        assert page.inner_text('[data-testid="chosen-seats"]') == "2 seats: A2, B2";
        # Only one seat is in the tab order, so Tab leaves the map.
        page.keyboard.press("Tab");
        assert page.evaluate("document.activeElement.dataset.seat") is None;
        page.focus('[data-testid="hold-seats"]');
        page.keyboard.press("Enter");
        page.wait_for_selector('[data-testid="hold-timer"]');
    } finally {
        close_contexts(browser);
    }
}

test "on a phone the seat map fits, zooms in its own box, and the bar stays on screen" {
    owner = cinema_selling_tickets(cols=14);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _open(page, owner);
        assert page.evaluate(OVERFLOW_JS) <= 0;
        assert page.evaluate(SCROLLER_JS) <= 0 , "the map should fit at first";
        assert page.evaluate(SMALL_TARGETS_JS) == [] , page.evaluate(SMALL_TARGETS_JS);
        small = page.evaluate(SEAT_WIDTH_JS);
        assert small >= 16 , small;
        page.locator('[data-testid="zoom-in"]').tap();
        page.locator('[data-testid="zoom-in"]').tap();
        assert page.evaluate(SEAT_WIDTH_JS) >= 44;
        assert page.evaluate(SCROLLER_JS) > 0 , "zoomed, the map scrolls in its box";
        assert page.evaluate(OVERFLOW_JS) <= 0 , "but the page never scrolls sideways";
        page.locator(_seat("A1")).tap();
        page.evaluate("window.scrollTo(0, 0)");
        assert page.evaluate(BAR_ON_SCREEN_JS);
        page.evaluate("window.scrollTo(0, document.body.scrollHeight)");
        assert page.evaluate(BAR_ON_SCREEN_JS);
    } finally {
        close_contexts(browser);
    }
}

test "a seat someone else holds shows as held and can't be chosen" {
    owner = cinema_selling_tickets();
    held = call(
        "",
        "hold_seats",
        {
            "slug": owner["slug"],
            "screening_id": owner["show"],
            "holder": "someone-else-0123456789",
            "labels": ["B1"]
        }
    );
    assert held["ok"] , held;
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _open(page, owner);
        assert page.get_attribute(_seat("B1"), "data-state") == "held";
        assert "held by another customer"
            in page.get_attribute(_seat("B1"), "aria-label");
        assert page.get_attribute(_seat("B6"), "data-state") == "not_for_sale";
        page.click(_seat("B1"));
        assert page.get_attribute(_seat("B1"), "data-state") == "held";
        assert page.inner_text('[data-testid="chosen-seats"]')
            == "Tap the seats you'd like.";
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of checkout" {
    owner = cinema_selling_tickets();
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _open(page, owner);
                _press(page, project, _seat("A3"));
                _press(page, project, _seat("A4"));
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"checkout-seats-{project}-{scheme}.png"),
                    full_page=True
                );
                _press(page, project, '[data-testid="hold-seats"]');
                page.wait_for_function(
                    "document.querySelector('[data-testid=checkout-total]')?.innerText.startsWith('KES')"
                );
                page.screenshot(
                    path=artifact(f"checkout-tickets-{project}-{scheme}.png"),
                    full_page=True
                );
                _press(page, project, '[data-testid="change-seats"]');
                page.wait_for_selector('[data-testid="hold-seats"]');
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
