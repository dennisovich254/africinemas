"""P15.5 E2E: paying an invoice in full, and querying one, on phone and desktop.

A cinema's cash sale (KES 1,660, a KES 49.80 fee) is invoiced (test runs bill the month
so far). Its owner's Billing page says it's due; Pay now shows the amount, KES 50 (M-Pesa
takes whole shillings), in a field that can't be changed, and asks only for the M-Pesa
number. The simulated M-Pesa pays: the page says so, the invoice reads Paid with its
receipt, and Pay now is gone.

Before that, a number that isn't one is refused, and payments that fail or are
cancelled say so and leave it Due; typing into the amount changes nothing, and the
number field brings up the phone keypad.

Another cinema's owner says what's wrong with their invoice (too short is refused):
the page says AfriCinemas is looking at it, it can still be paid, and the conversation
opens in Help. A reviewer sees it in the console with nothing to press; the super
admin must give an answer, then answers that it stands, and the owner sees it. A third
invoice is waived: the owner's reads Waived, with nothing to pay. Overdue invoices,
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

def _console(browser: any, pw: any, project: str, email: str) -> any {  # jac:ignore[W1037]
    us = browser.new_context(**context_options(pw, project, "light")).new_page();
    us.goto(PLATFORM_URL + "/sign-in");
    _type(us, "#email", email);
    _type(us, "#password", PASSWORD);
    us.click('[data-testid="platform-sign-in"] button[type="submit"]');
    us.wait_for_selector('[data-testid="platform-overview"]');
    return us;
}

def _reviewer(admin_token: str, project: str) -> str {
    # A reviewer on the platform's staff, joined with PASSWORD: their email.
    email = f"reviewer-{project}-{uuid.uuid4().hex[:8]}@example.com";
    invited = call(
        admin_token, "invite_platform_member", {"email": email, "role": "reviewer"}
    );
    assert invited["ok"] , invited;
    assert call("", "platform_join", {"token": invited["token"], "password": PASSWORD})[
        "ok"
    ];
    return email;
}

def _close_request(admin_token: str, owner: dict[str, str]) {
    # Answered, so the shared support inbox is as the other tests expect.
    asked = call(owner["token"], "billing", {"tenant": owner["slug"]});
    request_id = asked["statements"][0]["dispute"]["request_id"];
    call(admin_token, "platform_support_seen", {"request_id": request_id});
    call(
        admin_token,
        "platform_support_status",
        {"request_id": request_id, "status": "closed"}
    );
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
            assert f"Pay KES 50 by M-Pesa to Paybill 000000, account number {number}"
                in page.inner_text('[data-testid="statement-pay"]');
            amount = page.locator(f"#pay-amount-{number}");
            assert amount.input_value() == "KES 50";
            assert amount.get_attribute("readonly") is not None;
            assert not amount.is_editable();
            # Typing into it changes nothing.
            amount.click();
            page.keyboard.type("1");
            page.keyboard.press("Backspace");
            assert amount.input_value() == "KES 50";
            assert "paid in full" in page.inner_text('[data-testid="pay-invoice"]');
            phone = page.locator(f"#pay-phone-{number}");
            assert phone.get_attribute("type") == "tel"
                and phone.get_attribute("inputmode") == "tel";
            submit = '[data-testid="pay-invoice"] button[type="submit"]';
            # A number that isn't one.
            _type(page, f"#pay-phone-{number}", "12345");
            page.click(submit);
            page.wait_for_selector(
                '[data-testid="pay-invoice"] [role="alert"]:has-text("Enter an M-Pesa number")'
            );
            # A payment that fails (0700 000 001), then one cancelled (0700 000 002).
            for (bad, said) in [
                ("0700000001", "didn't go through"),
                ("0700000002", "cancelled on the phone")
            ] {
                _type(page, f"#pay-phone-{number}", bad);
                page.click(submit);
                page.wait_for_selector(
                    f'[data-testid="pay-status"]:has-text("{said}")', timeout=60000
                );
                page.wait_for_selector(f"{submit}:not([disabled])");
                assert page.inner_text('[data-testid="statement-status"]') == "Due";
            }
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
            # Too short to say what's wrong.
            _type(page, f"#dispute-{number}", "wrong");
            page.click('[data-testid="dispute"] button[type="submit"]');
            page.wait_for_selector(
                '[data-testid="dispute"] [role="alert"]:has-text("10 to")'
            );
            _type(
                page, f"#dispute-{number}", "The cash sale was refunded the same day."
            );
            page.click('[data-testid="dispute"] button[type="submit"]');
            page.wait_for_selector(
                '[data-testid="dispute"]:has-text("AfriCinemas is looking at it")'
            );
            assert "The cash sale was refunded the same day."
                in page.inner_text('[data-testid="dispute"]');
            # Disputed, it can still be paid.
            assert page.locator('[data-testid="pay-invoice"]').count() == 1;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # The conversation is in Help.
            page.click(
                '[data-testid="dispute"] a:has-text("See the conversation in Help")'
            );
            page.wait_for_function(
                "document.body.innerText.includes('An invoice I disagree with')"
            );
            assert number in page.inner_text("main");
            page.goto(f"{BASE_URL}/app/{owner['slug']}/billing");
            page.wait_for_selector('[data-testid="dispute"]');
            # A reviewer sees it in the console, with nothing to press.
            rev = _console(browser, pw, project, _reviewer(token, project));
            rev.goto(PLATFORM_URL + "/billing");
            seen = rev.locator('[data-testid="disputed"]').filter(has_text=number);
            seen.wait_for();
            assert seen.locator("button").count() == 0;
            rev.context.close();
            # The super admin answers it, and must say why.
            us = _console(browser, pw, project, admin);
            us.goto(PLATFORM_URL + "/billing");
            item = us.locator('[data-testid="disputed"]').filter(has_text=number);
            item.wait_for();
            assert "The cash sale was refunded the same day." in item.inner_text();
            item.locator('button:has-text("It stands")').click();
            item.locator('[role="alert"]:has-text("Say why")').wait_for();
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
            _close_request(token, owner);
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a super admin waives a disputed invoice, and the owner has nothing to pay" {
    admin = platform_admin();
    (_, token) = platform_session(admin);
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            (owner, number) = _invoiced(token);
            assert call(
                owner["token"],
                "dispute_invoice",
                {
                    "tenant": owner["slug"],
                    "number": number,
                    "text": "Every sale this month was refunded."
                }
            )["ok"];
            us = _console(browser, pw, project, admin);
            us.goto(PLATFORM_URL + "/billing");
            item = us.locator('[data-testid="disputed"]').filter(has_text=number);
            item.wait_for();
            _type(us, f"#decide-{number}", "Agreed: we waive it.");
            item.locator('button:has-text("Waive it")').click();
            item.wait_for(state="detached");
            us.context.close();
            page = _owner_billing(browser, pw, project, owner);
            assert page.inner_text('[data-testid="statement-status"]') == "Waived";
            dispute = page.inner_text('[data-testid="dispute"]');
            assert "nothing to pay on this invoice" in dispute , dispute;
            assert "Agreed: we waive it." in dispute;
            assert page.locator('[data-testid="pay-invoice"]').count() == 0;
            assert page.locator('[data-testid="statement-pay"]').count() == 0;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            _close_request(token, owner);
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
