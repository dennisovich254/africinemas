"""P15.3 E2E: connecting a cinema's own M-Pesa, testing it, and a change that waits.

A verified cinema's owner opens Settings → Payments: not connected yet, with the
verified business's name filled in. They connect their Paybill with its Daraja keys and
their password, send the KES 1 test payment, and say they've paid it: payments go to
their Paybill, and the keys appear nowhere on the page. They then change to a Till: its
test goes through, but the change waits its 24 hours while the Paybill stays in use,
and they cancel it. Phone and desktop, no sideways scrolling. The 24 hours passing,
and customers' payments reaching each account, are in
tests/integration/mpesa_account_tests.jac (they need a test-only clock).
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }
import from e2e.support.verification { verified }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     # Made-up keys, built so no secret-looking text is in the source.
     KEYS: dict[str, str] = {
         "#mpesa-consumer-key": "e" * 14 + "7QRS",
         "#mpesa-consumer-secret": "f" * 21,
         "#mpesa-passkey": "g" * 64
     };

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _keys_and_password(page: any) {  # jac:ignore[W1037]
    for (selector, value) in KEYS.items() {
        _type(page, selector, value);
    }
    _type(page, "#mpesa-password", PASSWORD);
    page.click('[data-testid="mpesa-form"] button[type="submit"]');
    page.wait_for_selector('[data-testid="mpesa-pending"]');
}

def _tested(page: any) {  # jac:ignore[W1037]
    _type(page, "#mpesa-test-phone", "0712345678");
    page.click('button:has-text("Send KES 1 test")');
    page.wait_for_selector('[data-testid="mpesa-pending"] [role="status"]');
    page.click('button:has-text("I\'ve paid it")');
}

test "an owner connects M-Pesa, tests it, and cancels a change that waits" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets(live=False);
            verified(owner);
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(BASE_URL + "/login");
            _type(page, "#email", owner["email"]);
            _type(page, "#password", PASSWORD);
            page.click('button[type="submit"]');
            page.wait_for_url("**/app**");
            page.goto(f"{BASE_URL}/app/{owner['slug']}/settings/payments");
            page.wait_for_selector('[data-testid="mpesa-form"]');
            assert "Not connected yet"
                in page.inner_text('[data-testid="mpesa-active"]');
            assert page.input_value("#mpesa-name") == "Nova Cinemas Ltd";
            page.click('[data-testid="mpesa-guide"] summary');
            page.wait_for_selector('[data-testid="mpesa-guide"] li >> visible=true');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            _type(page, "#mpesa-shortcode", "600100");
            _keys_and_password(page);
            _tested(page);
            page.wait_for_function(
                "document.querySelector('[data-testid=mpesa-active]').innerText.includes('Paybill 600100')"
            );
            assert "7QRS" in page.inner_text('[data-testid="mpesa-active"]');
            html = page.content();
            for value in KEYS.values() {
                assert value not in html , f"{project}: a key is on the page";
            }
            # A change to a Till waits its 24 hours, and is cancelled.
            page.click('button:has-text("Change M-Pesa")');
            page.check('input[name="mpesa-kind"][value="till"]');
            _type(page, "#mpesa-shortcode", "700200");
            _type(page, "#mpesa-till", "800300");
            _keys_and_password(page);
            _tested(page);
            page.wait_for_selector('[data-testid="mpesa-waiting"]');
            assert "Till 800300" in page.inner_text('[data-testid="mpesa-pending"]');
            assert "Paybill 600100" in page.inner_text('[data-testid="mpesa-active"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.click('button:has-text("Cancel this change")');
            page.wait_for_selector('[data-testid="mpesa-pending"]', state="detached");
            assert "Paybill 600100" in page.inner_text('[data-testid="mpesa-active"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
