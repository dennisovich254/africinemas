"""P15.6 E2E: reconciliation in the back office and the console, on phone and desktop.

A cinema sells A1 and A2 for cash at the box office (KES 1,660). Its box office agent
counts KES 1,600 on Count cash: the page says they're KES 60 short, and the owner's
Reconciliation page lists it, with both amounts; the owner marks it resolved with a
note. The owner uploads an M-Pesa statement with a payment no order took: the page
says what it found and lists it. The console's Reconciliation page shows that cinema's
open exception, and its overview shows AfriCinemas' takings with the cinema in them.
The daily M-Pesa check needs M-Pesa to change its mind:
tests/integration/reconcile_tests.jac.
"""

import uuid;
import from datetime { datetime, timedelta, timezone }
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

def _sign_in(browser: any, pw: any, project: str, email: str) -> any {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, "light")).new_page();
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app**");
    return page;
}

def _sale_by(owner: dict[str, str], agent: dict[str, str]) {
    # The agent sells A1 and A2 for cash: KES 1,660.
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
    assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
    sold = call(
        agent["token"],
        "sell_for_cash",
        {
            "tenant": owner["slug"],
            "screening_id": owner["show"],
            "holder": holder,
            "email": ""
        }
    );
    assert sold["ok"] , sold;
}

def _statement -> str {
    # The M-Pesa portal's CSV with one payment no order took.
    at = (datetime.now(timezone.utc) + timedelta(hours=3)).strftime(
        "%Y-%m-%d %H:%M:%S"
    );
    return "\n".join(
        [
            "Organisation Name,Test Cinema Ltd",
            "",
            "Receipt No.,Completion Time,Initiation Time,Details,Transaction Status,Paid In,Withdrawn,Balance,A/C No.",
            f"QZZ{uuid.uuid4().hex[:7].upper()},{at},{at},Pay Bill,Completed,500.00,,,SEAT A9"
        ]
    )
        + "\n";
}

test "a cash count that's short, and a statement with a stranger's payment, are listed and resolved" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            agent = add_staff(owner, "box_office_agent", owner["venue"]);
            _sale_by(owner, agent);
            # The agent counts KES 1,600.
            desk = _sign_in(browser, pw, project, agent["email"]);
            desk.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
            desk.click('[data-testid="sale-kind-cash"]');
            desk.wait_for_selector('[data-testid="cash-up"]');
            assert "KES 1,660" not in desk.inner_text('[data-testid="cash-up"]');
            _type(desk, "#cash-counted", "1600");
            desk.click('[data-testid="cash-up"] button[type="submit"]');
            desk.wait_for_selector('[data-testid="cash-up-result"]');
            said = desk.inner_text('[data-testid="cash-up-result"]');
            assert "You counted KES 1,600; you recorded KES 1,660" in said , said;
            assert "KES 60 short" in said , said;
            assert desk.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # The box office has no Reconciliation page.
            assert desk.locator(
                f'a[href="/app/{owner["slug"]}/reconciliation"]'
            ).count()
                == 0;
            desk.context.close();
            # The owner sees it, and resolves it.
            page = _sign_in(browser, pw, project, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/reconciliation");
            page.wait_for_selector('[data-testid="exception"]');
            assert page.inner_text('[data-testid="open-exceptions"]') == "1 to look at";
            row = page.locator('[data-testid="exception"]').filter(
                has_text="Cash short at a cash-up"
            );
            assert "ours KES 1,660, theirs KES 1,600" in row.inner_text();
            row.locator("input").fill("Counted again: KES 60 was in the float.");  # jac:ignore[W6002]
            row.locator('button:has-text("Mark resolved")').click();
            page.wait_for_selector(
                '[data-testid="open-exceptions"]:has-text("Nothing to look at")'
            );
            assert "Counted again: KES 60 was in the float."
                in page.inner_text('[data-testid="exception"]');
            # The cash count is listed.
            assert "counted KES 1,600, recorded KES 1,660"
                in page.inner_text('[data-testid="cash-ups"]');
            # A statement with a payment no order took.
            page.set_input_files(
                "#statement-file",
                files=[
                    {
                        "name": "statement.csv",
                        "mimeType": "text/csv",
                        "buffer": _statement().encode()
                    }
                ]
            );
            page.wait_for_selector(
                '[data-testid="statement-result"]:has-text("1 new exception")'
            );
            assert "1 payments in, 0 matched"
                in page.inner_text('[data-testid="statement-result"]');
            stranger = page.locator('[data-testid="exception"]').filter(
                has_text="On the M-Pesa statement, but no order took it"
            );
            stranger.wait_for();
            assert "theirs KES 500" in stranger.inner_text();
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.context.close();
            # The console: the open exception, and AfriCinemas' takings.
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            _type(us, "#email", admin);
            _type(us, "#password", PASSWORD);
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.wait_for_selector('[data-testid="platform-takings"] table');
            assert owner["name"] in us.inner_text('[data-testid="platform-takings"]');
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: overview scrolls sideways";
            us.goto(PLATFORM_URL + "/reconciliation");
            us.wait_for_selector('[data-testid="platform-reconciliation"]');
            shown = us.locator('[data-testid="platform-exception"]').filter(
                has_text="On the M-Pesa statement, but no order took it"
            );
            assert shown.count() >= 1;
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            us.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
