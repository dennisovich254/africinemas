"""P12.8 E2E: "Add snacks" on the storefront, between the tickets and paying.

The snacks show as posters by category; a poster opens its choices in place.
A cinema selling tickets (Adult KES 800 + KES 30 fee) sells Popcorn (Small KES 200,
Large KES 400, with Butter for KES 30) and Coca-Cola, which tracks stock and has none,
so it isn't offered. A visitor holds A1, continues to the snack step, opens Popcorn,
picks Large with Butter and adds it: the cart says so and the total is KES 1,260. They
pay with M-Pesa for KES 1,260 and "You're booked" lists the popcorn. Another skips the
step: the order is the ticket alone. Under a cinema's AI-written design (ADR-0048 to
ADR-0050, e2e/support/designs.jac), whose header, footer and styles wrap the showtime
page, the posters, the snack's choices and the bar stay on screen and work: a design
once pushed a floating sheet out of sight. Phone and desktop; screenshots for review.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { PASSWORD }
import from e2e.support.snacks { with_snacks }
import from e2e.support.designs { ai_designed }

glob SETTLE_MS: int = 30000,
     # "ok" when the element is on screen, has a size and nothing covers its middle (it
     # takes clicks there); otherwise what's wrong.
     ON_SCREEN_JS: str = """s => { const e = document.querySelector(s); if (!e) return 'missing';
  e.scrollIntoView({block: 'center'}); const r = e.getBoundingClientRect();
  if (r.width === 0 || r.height === 0) return 'no size';
  if (r.bottom <= 0 || r.top >= innerHeight || r.right <= 0 || r.left >= innerWidth) return 'off screen';
  const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
  return hit && (hit === e || e.contains(hit)) ? 'ok' : 'covered by ' + (hit ? hit.outerHTML.slice(0, 80) : 'nothing'); }""",
     WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _press(page: any, project: str, selector: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.locator(selector).first.tap();
    } else {
        page.locator(selector).first.click();
    }
}

def _total(page: any, text: str) {  # jac:ignore[W1037]
    page.wait_for_function(
        f"document.querySelector('[data-testid=checkout-total]')?.innerText === {repr(
            text
        )}"
    );
}

def _to_snacks(page: any, project: str, owner: dict[str, str], seat: str) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/c/{owner['slug']}/s/{owner['show']}");
    page.wait_for_selector(f'[data-testid="seat"][data-seat="{seat}"]');
    _press(page, project, f'[data-testid="seat"][data-seat="{seat}"]');
    _press(page, project, '[data-testid="hold-seats"]');
    _total(page, "KES 830");
    page.wait_for_selector('[data-testid="pay"]:has-text("Continue"):not([disabled])');
    _press(page, project, '[data-testid="pay"]');
    page.wait_for_selector('[data-testid="snack-step"]');
}

test "a visitor adds popcorn with butter, pays for it all, and sees it booked" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = with_snacks();
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _to_snacks(page, project, owner, "A1");
            # The snacks are posters on one grid, each with its category.
            assert page.locator(
                '[data-testid="snack-grid"] [data-testid="snack-product"]'
            ).count()
                == 1;
            # Coca-Cola has no stock, so Beverages isn't offered.
            chips = page.locator('[data-testid="snack-category"]').all_inner_texts();
            assert chips == ["Popcorn"] , chips;
            _press(page, project, '[data-testid="snack-product"]:has-text("Popcorn")');
            page.wait_for_selector('[data-testid="snack-options"]');
            # The choices show in place of the posters, with a way back.
            assert page.locator('[data-testid="snack-product"]').count() == 0;
            assert page.locator('[data-testid="snack-options"]').is_visible();
            _press(page, project, '[data-testid="snack-variant"]:has-text("Large")');
            page.locator('[data-testid="snack-addon"]').first.check();
            assert "KES 430" in page.inner_text('[data-testid="snack-add"]');
            _press(page, project, '[data-testid="snack-add"]');
            page.wait_for_selector(
                '[data-testid="snack-cart"]:has-text("Popcorn · Large")'
            );
            assert "Butter" in page.inner_text('[data-testid="snack-cart"]');
            _total(page, "KES 1,260");
            _press(page, project, '[data-testid="snacks-continue"]');
            page.wait_for_selector('[data-testid="pay-panel"]');
            assert "1 × Popcorn · Large"
                in page.inner_text('[data-testid="order-snack"]');
            assert "KES 1,260" in page.inner_text('[data-testid="order-total"]');
            page.fill("#mpesa-phone", "0712 345 678");  # jac:ignore[W6002]
            page.fill("#tickets-email", "anna@example.com");  # jac:ignore[W6002]
            _press(page, project, '[data-testid="pay-mpesa"]');
            page.wait_for_selector('[data-testid="booked"]', timeout=SETTLE_MS);
            assert "Popcorn · Large"
                in page.inner_text('[data-testid="booked-snacks"]');
            # Their pickup code (P12.9): a QR the snack counter scans, and its reference.
            assert page.get_attribute(
                '[data-testid="pickup-qr"]', "data-payload"
            ).startswith(
                "SNK1."
            );
            assert len(page.inner_text('[data-testid="pickup-reference"]').strip())
                == 19;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the snack counter hands a paid order's snacks over once, by its pickup code" {
    # A showtime starting in 30 minutes, so pickup is open (from two hours before).
    owner = with_snacks(30);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _to_snacks(page, "desktop", owner, "A5");
        _press(page, "desktop", '[data-testid="snack-product"]');
        _press(page, "desktop", '[data-testid="snack-add"]');
        page.wait_for_selector('[data-testid="snack-cart"]');
        _press(page, "desktop", '[data-testid="snacks-continue"]');
        page.wait_for_selector('[data-testid="pay-panel"]');
        page.fill("#mpesa-phone", "0712 345 678");  # jac:ignore[W6002]
        page.fill("#tickets-email", "ben@example.com");  # jac:ignore[W6002]
        _press(page, "desktop", '[data-testid="pay-mpesa"]');
        page.wait_for_selector('[data-testid="pickup-reference"]', timeout=SETTLE_MS);
        code = page.inner_text('[data-testid="pickup-reference"]').strip();
        # Staff at the snack counter: the code typed, the snacks shown, handed over.
        staff = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        staff.goto(BASE_URL + "/login");
        staff.fill("#email", owner["email"]);  # jac:ignore[W6002]
        staff.fill("#password", PASSWORD);  # jac:ignore[W6002]
        staff.click('button[type="submit"]');
        staff.wait_for_url("**/app");
        staff.goto(f"{BASE_URL}/app/{owner['slug']}/snack-counter");
        staff.wait_for_selector('[data-testid="snack-counter"]');
        staff.fill('[data-testid="pickup-code"]', code.lower());  # jac:ignore[W6002]
        staff.click('[data-testid="look-up"]');
        staff.wait_for_selector(
            '[data-testid="pickup-snacks"]:has-text("Popcorn · Small")'
        );
        assert staff.inner_text('[data-testid="pickup-state"]') == "Ready to hand over";
        staff.click('[data-testid="hand-over"]');
        staff.wait_for_selector('[data-testid="counter-done"]:has-text("Handed over")');
        assert staff.inner_text('[data-testid="pickup-state"]') == "Handed over";
        assert staff.locator('[data-testid="hand-over"]').count() == 0;
        # The same code again: already handed over, and when.
        staff.click('[data-testid="next-order"]');
        staff.fill('[data-testid="pickup-code"]', code);  # jac:ignore[W6002]
        staff.click('[data-testid="look-up"]');
        staff.wait_for_selector('[data-testid="pickup-collected"]');
        assert staff.inner_text('[data-testid="pickup-state"]') == "Handed over";
    } finally {
        close_contexts(browser);
    }
}

test "skipping the snacks orders the ticket alone" {
    (pw, browser) = shared_browser();
    try {
        owner = with_snacks();
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _to_snacks(page, "mobile", owner, "A2");
        skipper = page.locator('[data-testid="skip-snacks"]');
        go_on = page.locator('[data-testid="snacks-continue"]');
        assert skipper.is_visible() and go_on.is_visible();
        assert skipper.bounding_box()["height"] == go_on.bounding_box()["height"];
        skipper.tap();
        page.wait_for_selector('[data-testid="pay-panel"]');
        assert page.locator('[data-testid="order-snack"]').count() == 0;
        assert "KES 830" in page.inner_text('[data-testid="order-total"]');
    } finally {
        close_contexts(browser);
    }
}

test "under a cinema's AI-written design the snack step stays on screen and works" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = with_snacks();
            ai_designed(owner);
            page = browser.new_context(
                **context_options(pw, project, "light"), reduced_motion="reduce"
            ).new_page();
            _to_snacks(page, project, owner, "A4");
            # The written design wraps the page, or this test proves nothing.
            assert page.locator('[data-testid="ai-header"]').count() == 1;
            assert page.locator('[data-testid="storefront-header"]').count() == 0;
            where = f"{project}: ";
            for part in [
                '[data-testid="snack-product"]',
                '[data-testid="skip-snacks"]'
            ] {
                assert page.evaluate(ON_SCREEN_JS, part) == "ok" , where + part;
            }
            _press(page, project, '[data-testid="snack-product"]');
            page.wait_for_selector('[data-testid="snack-options"]');
            for part in [
                '[data-testid="snack-variant"]',
                '[data-testid="snack-add"]',
                '[data-testid="snack-back"]'
            ] {
                assert page.evaluate(ON_SCREEN_JS, part) == "ok" , where + part;
            }
            _press(page, project, '[data-testid="snack-add"]');
            page.wait_for_selector('[data-testid="snack-cart"]');
            _total(page, "KES 1,030");
            assert page.evaluate(ON_SCREEN_JS, '[data-testid="snacks-continue"]')
                == "ok" , where + "continue";
            assert page.evaluate(WIDE_JS) <= 1 , where + "scrolls sideways";
            page.screenshot(
                path=artifact(f"snack-step-ai-design-{project}.png"), full_page=True
            );
            _press(page, project, '[data-testid="snacks-continue"]');
            page.wait_for_selector('[data-testid="pay-panel"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the snack step" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = with_snacks();
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _to_snacks(page, project, owner, "A3");
                page.screenshot(
                    path=artifact(f"snack-step-{project}-{scheme}.png"), full_page=True
                );
                _press(page, project, '[data-testid="snack-product"]');
                page.wait_for_selector('[data-testid="snack-options"]');
                page.screenshot(path=artifact(f"snack-options-{project}-{scheme}.png"));
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
