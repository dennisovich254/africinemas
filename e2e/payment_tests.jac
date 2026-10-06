"""P5.6 E2E: paying with M-Pesa on a phone and a desktop (simulated M-Pesa).

The e2e server runs the simulator, and the resolver settles payments every 2 seconds
(scripts/e2e.sh). After placing an order the visitor enters their M-Pesa number (a tel
keypad, checked inline), pays, is told to check their phone, and sees their tickets
once the payment settles, also after a reload. A failed payment says so and lets them
try again. Review screenshots of each step.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.catalog { cinema_selling_tickets }

glob PHONE: str = '#mpesa-phone',
     SETTLE_MS: int = 30000;

def _seat(label: str) -> str {
    return f'[data-testid="seat"][data-seat="{label}"]';
}

def _press(page: any, project: str, selector: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.locator(selector).tap();
    } else {
        page.locator(selector).click();
    }
}

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _ordered(page: any, project: str, owner: dict[str, str]) {  # jac:ignore[W1037]
    # Hold A1 and A2, keep the Adult tickets, and place the order (KES 1,660).
    page.goto(f"{BASE_URL}/c/{owner['slug']}/s/{owner['show']}");
    page.wait_for_selector(_seat("A1"));
    _press(page, project, _seat("A1"));
    _press(page, project, _seat("A2"));
    _press(page, project, '[data-testid="hold-seats"]');
    page.wait_for_function(
        "document.querySelector('[data-testid=checkout-total]')?.innerText === 'KES 1,660'"
    );
    _press(page, project, '[data-testid="pay"]');
    page.wait_for_selector('[data-testid="pay-panel"]');
}

test "pay with M-Pesa: check your phone, then the tickets, also after a reload" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _ordered(page, project, owner);
            assert page.get_attribute(PHONE, "inputmode") == "tel";
            assert page.get_attribute(PHONE, "type") == "tel";
            assert "KES 1,660" in page.inner_text('[data-testid="pay-mpesa"]');
            _type(page, PHONE, "0712 345 678");
            _press(page, project, '[data-testid="pay-mpesa"]');
            page.wait_for_selector(
                '[data-testid="payment-status"], [data-testid="booked"]'
            );
            page.wait_for_selector('[data-testid="booked"]', timeout=SETTLE_MS);
            assert page.locator('[data-testid="ticket"]').count() == 2;
            first = page.inner_text('[data-testid="ticket"] >> nth=0');
            assert "Seat A1" in first , first;
            page.reload();
            page.wait_for_selector('[data-testid="booked"]');
            assert page.locator('[data-testid="ticket"]').count() == 2;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the M-Pesa number is checked inline, next to the field" {
    owner = cinema_selling_tickets();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _ordered(page, "mobile", owner);
        _type(page, PHONE, "12345");
        page.locator(PHONE).blur();
        page.wait_for_selector('[data-testid="phone-error"]');
        assert "0712 345 678" in page.inner_text('[data-testid="phone-error"]');
        assert page.get_attribute(PHONE, "aria-invalid") == "true";
        assert page.get_attribute(PHONE, "aria-describedby") == "mpesa-phone-error";
        page.locator('[data-testid="pay-mpesa"]').tap();
        assert page.locator('[data-testid="payment-status"]').count() == 0;
        _type(page, PHONE, "+254 712 345 678");
        page.locator(PHONE).blur();
        page.wait_for_selector('[data-testid="phone-error"]', state="detached");
        assert page.get_attribute(PHONE, "aria-invalid") == "false";
    } finally {
        close_contexts(browser);
    }
}

test "a failed payment says so, and paying again works" {
    owner = cinema_selling_tickets();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _ordered(page, "desktop", owner);
        # The simulator's test number for a payment that fails.
        _type(page, PHONE, "0700 000 001");
        page.click('[data-testid="pay-mpesa"]');
        page.wait_for_selector(
            '[data-testid="payment-status"][data-state="failed"]', timeout=SETTLE_MS
        );
        assert "didn't go through"
            in page.inner_text('[data-testid="payment-message"]');
        assert page.inner_text('[data-testid="pay-mpesa"]').strip() == "Try again";
        _type(page, PHONE, "0712 345 678");
        page.click('[data-testid="pay-mpesa"]');
        page.wait_for_selector('[data-testid="booked"]', timeout=SETTLE_MS);
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of paying" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = cinema_selling_tickets();
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _ordered(page, project, owner);
                _type(page, PHONE, "07");
                page.locator(PHONE).blur();
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"pay-form-{project}-{scheme}.png"), full_page=True
                );
                _type(page, PHONE, "0712 345 678");
                _press(page, project, '[data-testid="pay-mpesa"]');
                page.wait_for_selector('[data-testid="booked"]', timeout=SETTLE_MS);
                page.screenshot(
                    path=artifact(f"pay-booked-{project}-{scheme}.png"), full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
