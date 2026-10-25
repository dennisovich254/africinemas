"""P6.5 E2E: selling to a walk-in customer at the box office (simulated M-Pesa).

A box office agent of the cinema's venue signs in and opens Box office: picks the
showtime, chooses two seats on the storefront's own seat map, and takes the money in
cash (Cash received, then Confirm) or with M-Pesa on the customer's phone. Either way
the tickets show with their QR codes, ready to print, and New sale starts over. Review
screenshots of taking payment and of a sale.
"""

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
import from e2e.support.snacks { with_snacks }

glob SETTLE_MS: int = 30000;

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _press(page: any, project: str, selector: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.locator(selector).tap();
    } else {
        page.locator(selector).click();
    }
}

def _agent_at_counter(page: any, project: str) -> dict[str, str] {  # jac:ignore[W1037]
    # A cinema selling tickets, its box office agent signed in at Box office with the
    # showtime chosen and A1 and A2 ordered (KES 1,660). Returns the owner.
    owner = cinema_selling_tickets();
    agent = add_staff(owner, "box_office_agent", owner["venue"]);
    # Staff work on shift (ADR-0006): the agent starts theirs, as at the start of work.
    assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
    page.goto(BASE_URL + "/login");
    _type(page, "#email", agent["email"]);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_function("!!localStorage.getItem('jac_token')");
    page.wait_for_url(lambda (url: str) -> bool { return "/login" not in url; });
    page.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
    page.wait_for_selector('[data-testid="counter-showtime"]');
    _press(page, project, '[data-testid="counter-showtime"]');
    page.wait_for_selector('[data-testid="seat"][data-seat="A1"]');
    _press(page, project, '[data-testid="seat"][data-seat="A1"]');
    _press(page, project, '[data-testid="seat"][data-seat="A2"]');
    _press(page, project, '[data-testid="hold-seats"]');
    page.wait_for_function(
        "document.querySelector('[data-testid=checkout-total]')?.innerText === 'KES 1,660'"
    );
    _press(page, project, '[data-testid="pay"]');
    page.wait_for_selector('[data-testid="counter-pay"]');
    return owner;
}

test "a cash sale: Cash received, Confirm, and the tickets are ready" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _agent_at_counter(page, project);
            assert page.inner_text('[data-testid="counter-total"]') == "KES 1,660";
            _press(page, project, '[data-testid="cash-received"]');
            assert "KES 1,660" in page.inner_text('[data-testid="confirm-cash"]');
            _press(page, project, '[data-testid="confirm-cash"]');
            page.wait_for_selector('[data-testid="counter-done"]');
            assert page.locator('[data-testid="ticket"]').count() == 2;
            assert page.locator('[data-testid="ticket-qr"]').count() == 2;
            # The customer's tickets panel never shows: it would save them to the
            # agent's account.
            assert page.locator('[data-testid="ticket-delivery"]').count() == 0;
            _press(page, project, '[data-testid="new-sale"]');
            page.wait_for_selector('[data-testid="seat"][data-seat="A3"]');
            assert page.locator('[data-testid="counter-done"]').count() == 0;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "an M-Pesa sale at the counter: the customer's prompt, then the tickets" {
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _agent_at_counter(page, "desktop");
        _type(page, "#counter-phone", "0712 345 678");
        page.click('[data-testid="counter-mpesa"]');
        page.wait_for_selector(
            '[data-testid="counter-waiting"], [data-testid="counter-done"]'
        );
        page.wait_for_selector('[data-testid="counter-done"]', timeout=SETTLE_MS);
        assert page.locator('[data-testid="ticket"]').count() == 2;
    } finally {
        close_contexts(browser);
    }
}

test "a mixed counter sale shows the snack code and records immediate handover" {
    (pw, browser) = shared_browser();
    try {
        owner = with_snacks();
        agent = add_staff(owner, "box_office_agent", owner["venue"]);
        assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        page.goto(BASE_URL + "/login");
        _type(page, "#email", agent["email"]);
        _type(page, "#password", PASSWORD);
        page.click('button[type="submit"]');
        page.wait_for_function("!!localStorage.getItem('jac_token')");
        page.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
        page.wait_for_selector('[data-testid="counter-showtime"]');
        page.click('[data-testid="counter-showtime"]');
        page.wait_for_selector('[data-testid="seat"][data-seat="A1"]');
        page.click('[data-testid="seat"][data-seat="A1"]');
        page.click('[data-testid="hold-seats"]');
        page.wait_for_selector('[data-testid="pay"]:has-text("Continue")');
        page.click('[data-testid="pay"]');
        page.wait_for_selector('[data-testid="snack-step"]');
        page.click('[data-testid="snack-product"]:has-text("Popcorn")');
        page.click('[data-testid="snack-variant"]:has-text("Large")');
        page.click('[data-testid="snack-add"]');
        page.wait_for_selector(
            '[data-testid="snack-cart"]:has-text("Popcorn · Large")'
        );
        page.wait_for_function(
            "document.querySelector('[data-testid=checkout-total]')?.innerText === 'KES 1,230'"
        );
        page.wait_for_selector('[data-testid="snacks-continue"]:not([disabled])');
        page.click('[data-testid="snacks-continue"]');
        page.wait_for_selector('[data-testid="counter-pay"]');
        page.click('[data-testid="cash-received"]');
        page.click('[data-testid="confirm-cash"]');
        page.wait_for_selector('[data-testid="counter-done"]');
        assert page.locator('[data-testid="ticket-qr"]').count() == 1;
        assert page.get_attribute(
            '[data-testid="pickup-qr"]', "data-payload"
        ).startswith(
            "SNK1."
        );
        assert "Popcorn · Large" in page.inner_text('[data-testid="booked-snacks"]');
        page.click('[data-testid="counter-hand-over-snacks"]');
        page.wait_for_selector('[data-testid="counter-snacks-handed"]');
        assert page.locator('[data-testid="counter-hand-over-snacks"]').count() == 0;
    } finally {
        close_contexts(browser);
    }
}

test "snacks only: a walk-in buys a Large Popcorn for cash, and it's handed over" {
    # P12.10 (improvements #21, #26).
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = with_snacks();
            agent = add_staff(owner, "box_office_agent", owner["venue"]);
            assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(BASE_URL + "/login");
            _type(page, "#email", agent["email"]);
            _type(page, "#password", PASSWORD);
            page.click('button[type="submit"]');
            page.wait_for_function("!!localStorage.getItem('jac_token')");
            page.wait_for_url(
                lambda (url: str) -> bool { return "/login" not in url; }
            );
            page.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
            _press(page, project, '[data-testid="sale-kind-snacks"]');
            page.wait_for_selector(
                '[data-testid="snack-sale"] [data-testid="snack-product"]'
            );
            assert page.inner_text('[data-testid="snack-sale-total"]') == "KES 0";
            assert page.locator('[data-testid="snack-sale-pay"]').is_disabled();
            _press(page, project, '[data-testid="snack-product"]:has-text("Popcorn")');
            _press(page, project, '[data-testid="snack-variant"]:has-text("Large")');
            _press(page, project, '[data-testid="snack-add"]');
            page.wait_for_function(
                "document.querySelector('[data-testid=snack-sale-total]')?.innerText === 'KES 400'"
            );
            _press(page, project, '[data-testid="snack-sale-pay"]');
            page.wait_for_selector('[data-testid="snack-sale-payment"]');
            assert "KES 400" in page.inner_text('[data-testid="snack-sale-amount"]');
            _press(page, project, '[data-testid="snack-sale-cash"]');
            _press(page, project, '[data-testid="snack-sale-confirm-cash"]');
            page.wait_for_selector('[data-testid="snack-sale-done"]');
            assert page.inner_text('[data-testid="snack-sale-code"]').strip();
            _press(page, project, '[data-testid="snack-sale-hand-over"]');
            page.wait_for_selector('[data-testid="snack-sale-handed"]');
            _press(page, project, '[data-testid="snack-sale-new"]');
            page.wait_for_selector('[data-testid="snack-sale-pay"]');
            assert page.inner_text('[data-testid="snack-sale-total"]') == "KES 0";
            assert page.locator('[data-testid="snack-sale-pay"]').is_disabled();
            assert page.evaluate(
                "document.documentElement.scrollWidth - document.documentElement.clientWidth"
            )
                <= 0 , f"{project}: scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the box office" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _agent_at_counter(page, project);
                _press(page, project, '[data-testid="cash-received"]');
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"box-office-pay-{project}-{scheme}.png"),
                    full_page=True
                );
                _press(page, project, '[data-testid="confirm-cash"]');
                page.wait_for_selector('[data-testid="counter-done"]');
                page.screenshot(
                    path=artifact(f"box-office-sold-{project}-{scheme}.png"),
                    full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
