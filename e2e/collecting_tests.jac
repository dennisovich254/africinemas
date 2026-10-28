"""P15.5 E2E: paying an invoice in full, and querying one, on phone and desktop.

A cinema's cash sale (KES 1,660, a KES 49.80 fee) is invoiced (test runs bill the month
so far). Its owner's Billing page says it's due; Pay now shows the amount, KES 50 (M-Pesa
takes whole shillings), in a field that can't be changed, and asks only for the M-Pesa
number. The simulated M-Pesa pays: the page says so, the invoice reads Paid with its
receipt, and Pay now is gone.

Another cinema's owner says what's wrong with their invoice: the page says AfriCinemas
is looking at it. In the console's Billing page the super admin finds it under Disputed
invoices and answers that it stands; the owner then sees the answer. Overdue invoices,
reminders and suspension need days to pass: tests/integration/collecting_tests.jac.
"""

import uuid;
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PLATFORM_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { PASSWORD, platform_admin, platform_session, call }
import from e2e.support.catalog { cinema_selling_tickets }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _invoiced(admin_token: str) -> tuple[dict[str, str], str] {
    # A cinema with a cash sale of A1 and A2, and its invoice issued: (owner, number).
    owner = cinema_selling_tickets();
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": owner["slug"], "screening_id": owner["show"], "holder": holder};
    assert call("", "hold_seats", {** where, "labels": ["A1", "A2"]})["ok"];
    assert call(
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
    )["ok"];
    assert call(
        owner["token"],
        "sell_for_cash",
        {
            "tenant": owner["slug"],
            "screening_id": owner["show"],
            "holder": holder,
            "email": ""
        }
    )["ok"];
    assert call(admin_token, "platform_issue_statements", {})["ok"];
    listed = call(owner["token"], "billing", {"tenant": owner["slug"]});
    assert len(listed["statements"]) == 1 , listed;
    return (owner, listed["statements"][0]["number"]);
}

def _owner_billing(browser: any, pw: any, project: str, owner: dict[str, str]) -> any {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, "light")).new_page();
    page.goto(BASE_URL + "/login");
    _type(page, "#email", owner["email"]);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app**");
    page.goto(f"{BASE_URL}/app/{owner['slug']}/billing");
    page.wait_for_selector('[data-testid="statement"]');
    return page;
}

test "an owner pays an invoice in full with Pay now, the amount fixed" {
    admin = platform_admin();
    (_, token) = platform_session(admin);
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            (owner, number) = _invoiced(token);
            page = _owner_billing(browser, pw, project, owner);
            assert page.inner_text('[data-testid="statement-status"]') == "Due";
            amount = page.locator(f"#pay-amount-{number}");
            assert amount.input_value() == "KES 50";
            assert amount.get_attribute("readonly") is not None;
            assert not amount.is_editable();
            assert "paid in full" in page.inner_text('[data-testid="pay-invoice"]');
            _type(page, f"#pay-phone-{number}", "0712345678");
            page.click('[data-testid="pay-invoice"] button[type="submit"]');
            page.wait_for_selector(
                '[data-testid="pay-status"]:has-text("Paid. Thank you.")', timeout=60000
            );
            page.wait_for_function(
                "document.querySelector('[data-testid=statement-status]')?.innerText.trim() === 'Paid'"
            );
            assert "Paid on" in page.inner_text('[data-testid="statement-paid"]');
            assert page.locator('[data-testid="pay-invoice"]').count() == 0;
            assert page.locator('[data-testid="statement-pay"]').count() == 0;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            got = call(owner["token"], "billing", {"tenant": owner["slug"]});
            assert got["statements"][0]["status"] == "paid"
                and got["statements"][0]["paid_receipt"] , got;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "an owner queries an invoice, and the super admin answers it in the console" {
    admin = platform_admin();
    (_, token) = platform_session(admin);
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            (owner, number) = _invoiced(token);
            page = _owner_billing(browser, pw, project, owner);
            page.click('[data-testid="dispute"] summary');
            _type(
                page, f"#dispute-{number}", "The cash sale was refunded the same day."
            );
            page.click('[data-testid="dispute"] button[type="submit"]');
            page.wait_for_selector(
                '[data-testid="dispute"]:has-text("AfriCinemas is looking at it")'
            );
            assert "The cash sale was refunded the same day."
                in page.inner_text('[data-testid="dispute"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # The super admin answers it from the console.
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            _type(us, "#email", admin);
            _type(us, "#password", PASSWORD);
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.goto(PLATFORM_URL + "/billing");
            item = us.locator('[data-testid="disputed"]').filter(has_text=number);
            item.wait_for();
            assert "The cash sale was refunded the same day." in item.inner_text();
            _type(us, f"#decide-{number}", "The refund was after the month closed.");
            item.locator('button:has-text("It stands")').click();
            item.wait_for(state="detached");
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            us.context.close();
            page.reload();
            page.wait_for_selector(
                '[data-testid="dispute"]:has-text("stands as issued")'
            );
            assert "The refund was after the month closed."
                in page.inner_text('[data-testid="dispute"]');
            assert page.inner_text('[data-testid="statement-status"]') == "Due";
            # Answered, so the shared support inbox is as the other tests expect.
            asked = call(owner["token"], "billing", {"tenant": owner["slug"]});
            request_id = asked["statements"][0]["dispute"]["request_id"];
            call(token, "platform_support_seen", {"request_id": request_id});
            call(
                token,
                "platform_support_status",
                {"request_id": request_id, "status": "closed"}
            );
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
