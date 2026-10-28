"""P15.4 E2E: a month's statement and invoice, in the console and the back office.

A cinema selling tickets sells A1 and A2 for cash at the box office: KES 1,660, on
which AfriCinemas' fee is 3%, KES 49.80. A super admin issues what's due from the
console's Billing page (test runs bill the month so far, AFRICINEMAS_BILLING_EARLY), and
sees the cinema's invoice. The owner's Billing page shows it: the invoice number,
KES 49.80 due within 5 days, to pay to AfriCinemas' placeholder paybill with the
invoice number as the account, and, opened, the takings and fees; Download PDF saves
it. Issuing again makes nothing new. A box office agent has no Billing page. Phone and
desktop, no sideways scrolling.
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
import from e2e.support.api { PASSWORD, platform_admin, add_staff, call }
import from e2e.support.catalog { cinema_selling_tickets }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _cinema_with_a_sale -> dict[str, str] {
    # The owner sells A1 and A2 (two Adults) for cash at the counter, through the API.
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

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app**");
}

test "a month of sales gives the expected invoice, in the console and the back office" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = _cinema_with_a_sale();
            agent = add_staff(owner, "box_office_agent", owner["venue"]);
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            _type(us, "#email", admin);
            _type(us, "#password", PASSWORD);
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.goto(PLATFORM_URL + "/billing");
            us.wait_for_selector('[data-testid="platform-billing"]');
            us.click('button:has-text("Issue what\'s due now")');
            us.wait_for_selector(
                '[data-testid="platform-billing"] [role="status"]:has-text("Issued")',
                timeout=120000
            );
            listed = call(owner["token"], "billing", {"tenant": owner["slug"]});
            assert len(listed["statements"]) == 1 , listed;
            number = listed["statements"][0]["number"];
            mine = us.locator('[data-testid="statement"]').filter(has_text=number);
            mine.wait_for();
            assert "KES 49.80" in mine.inner_text();
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # Again: nothing new.
            us.click('button:has-text("Issue what\'s due now")');
            us.wait_for_selector(
                '[data-testid="platform-billing"] [role="status"]:has-text("Nothing to issue")',
                timeout=120000
            );
            assert mine.count() == 1;
            us.context.close();
            # The owner's Billing page.
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/billing");
            page.wait_for_selector('[data-testid="statement"]');
            assert page.locator('[data-testid="statement"]').count() == 1;
            card = page.inner_text('[data-testid="statement"]');
            assert f"Invoice {number}" in card and "due" in card , card;
            assert page.inner_text('[data-testid="statement-due"]') == "KES 49.80";
            pay = page.inner_text('[data-testid="statement-pay"]');
            assert "Paybill 000000" in pay and f"account number {number}" in pay , pay;
            assert "isn't live yet" in pay;
            page.click('[data-testid="statement"] summary');
            figures = page.inner_text('[data-testid="statement"] dl');
            assert "KES 1,660" in figures and "Box office, cash" in figures , figures;
            assert "No VAT" in page.inner_text('[data-testid="statement"]');
            with page.expect_download() as got {
                page.click('[data-testid="statement"] button:has-text("Download PDF")');
            }
            assert got.value.suggested_filename.startswith(f"AfriCinemas-{number}");
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.context.close();
            # The box office has no Billing page, and can't read it.
            assert not call(agent["token"], "billing", {"tenant": owner["slug"]})["ok"];
        }
    } finally {
        close_contexts(browser);
    }
}
