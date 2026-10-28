"""P15.4 E2E: a month's statement and invoice, in the console and the back office.

A cinema selling tickets sells A1 and A2 for cash at the box office: KES 1,660, on
which AfriCinemas' fee is 3%, KES 49.80. Before anything is issued the owner's Billing
page is empty and says invoices are paid within 5 days. A super admin's console
Billing page says the paybill is a placeholder, issues what's due (test runs bill the
month so far, AFRICINEMAS_BILLING_EARLY) and shows the cinema's invoice, whose PDF
downloads; issuing again makes nothing new. The owner's statement shows the invoice
number, its issue and due dates, KES 49.80 due to the placeholder paybill with the
invoice number as the account, every figure exactly (no VAT, no credits), and
downloads as a PDF. A box office agent has no Billing in the menu, and the page
says it isn't theirs. Phone and desktop, no sideways scrolling.
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

def _day(iso: str) -> str {
    # "2026-11-07" -> "7 Nov 2026", as the Billing page writes it.
    months = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec"
    ];
    (year, month, day) = iso.split("-");
    return f"{int(day)} {months[int(month) - 1]} {year}";
}

glob ROWS_JS: str = "Object.fromEntries([...document.querySelectorAll('[data-testid=statement] dl dt')].map(d => [d.innerText.trim(), d.nextElementSibling.innerText.trim()]))";

test "a month of sales gives the expected invoice, in the console and the back office" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = _cinema_with_a_sale();
            agent = add_staff(owner, "box_office_agent", owner["venue"]);
            # Before it's issued, the owner's Billing page is empty, with its terms.
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/billing");
            page.wait_for_selector('[data-testid="no-statements"]');
            assert "within 5 days" in page.inner_text('[data-testid="billing"]');
            # A super admin issues what's due from the console.
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
            assert "Paybill 000000 (a placeholder"
                in us.inner_text('[data-testid="platform-billing"]');
            us.click('button:has-text("Issue what\'s due now")');
            us.wait_for_selector(
                '[data-testid="platform-billing"] [role="status"]:has-text("Issued")',
                timeout=120000
            );
            listed = call(owner["token"], "billing", {"tenant": owner["slug"]});
            assert len(listed["statements"]) == 1 , listed;
            shown = listed["statements"][0];
            number = shown["number"];
            mine = us.locator('[data-testid="statement"]').filter(has_text=number);
            mine.wait_for();
            assert "KES 49.80" in mine.inner_text();
            assert owner["name"] in mine.inner_text();
            with us.expect_download() as got {
                mine.locator('button:has-text("Download PDF")').click();
            }
            assert got.value.suggested_filename.startswith(f"AfriCinemas-{number}");
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
            page.reload();
            page.wait_for_selector('[data-testid="statement"]');
            assert page.locator('[data-testid="statement"]').count() == 1;
            card = page.inner_text('[data-testid="statement"]');
            assert f"Invoice {number}" in card , card;
            assert f"issued {_day(shown['issued_on'])}" in card , card;
            assert f"due {_day(shown['due_on'])}" in card , card;
            assert page.inner_text('[data-testid="statement-due"]') == "KES 49.80";
            pay = page.inner_text('[data-testid="statement-pay"]');
            assert "Paybill 000000" in pay and f"account number {number}" in pay , pay;
            assert "isn't live yet" in pay;
            page.click('[data-testid="statement"] summary');
            page.wait_for_selector('[data-testid="statement"] dl >> visible=true');
            # Every row, exactly: no VAT, no credits.
            assert page.evaluate(ROWS_JS)
                == {
                    "Online": "KES 0",
                    "Box office, M-Pesa": "KES 0",
                    "Box office, cash": "KES 1,660",
                    "Gross takings": "KES 1,660",
                    "Refunds": "KES 0",
                    "Net takings": "KES 1,660",
                    "AfriCinemas' fees": "KES 49.80",
                    "Fees credited on refunds": "KES 0",
                    "Fees this month": "KES 49.80",
                    "Amount due": "KES 49.80"
                } , page.evaluate(ROWS_JS);
            # One sale of two seats is one booking.
            assert "The figures (1 booking)" in card , card;
            assert "No VAT" in page.inner_text('[data-testid="statement"]');
            with page.expect_download() as saved {
                page.click('[data-testid="statement"] button:has-text("Download PDF")');
            }
            assert saved.value.suggested_filename.startswith(f"AfriCinemas-{number}");
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.context.close();
            # The box office: no Billing in its menu, and the page says it isn't theirs.
            desk = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(desk, agent["email"]);
            desk.goto(f"{BASE_URL}/app/{owner['slug']}");
            desk.wait_for_load_state("networkidle");
            assert desk.locator(f'a[href="/app/{owner["slug"]}/billing"]').count() == 0;
            desk.goto(f"{BASE_URL}/app/{owner['slug']}/billing");
            desk.wait_for_selector('[data-testid="no-access"]');
            assert desk.locator('[data-testid="statement"]').count() == 0;
            desk.context.close();
            assert not call(agent["token"], "billing", {"tenant": owner["slug"]})["ok"];
        }
    } finally {
        close_contexts(browser);
    }
}
