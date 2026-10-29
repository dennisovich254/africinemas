"""P15.6 E2E: reconciliation in the back office and the console, on phone and desktop.

A cinema's box office agent sells A1 and A2 for cash (KES 1,660). On Count cash, what
they sold isn't shown first; "abc" is refused; KES 1,600 is KES 60 short; counting
again at once matches (nothing since); after one more sale (KES 830), KES 1,000 is
KES 170 over. The agent has no Reconciliation page, and no count on its sidebar. The
owner's sidebar counts 2; both are on the Cash tab, in words ("Cash sales recorded",
"Cash counted", "short"/"over", no "ours" or "theirs"), at the cinema's time; M-Pesa has
nothing. A note is needed to resolve the short one, which then moves to Resolved with
its note, and the sidebar counts 1; the three counts are listed. There's no statement
upload. In the console, the overview's takings tables (by month and by cinema) include
the cinema, and Reconciliation lists the open cash over, not the resolved short one.
The daily M-Pesa check needs M-Pesa to change its mind:
tests/integration/reconcile_tests.jac.
"""

import uuid;
import from datetime { datetime, timezone }
import from zoneinfo { ZoneInfo }
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

def _sale_by(owner: dict[str, str], agent: dict[str, str], seats: list[str]) {
    # The agent sells `seats` (Adults, KES 830 each) for cash.
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": owner["slug"], "screening_id": owner["show"], "holder": holder};
    assert call("", "hold_seats", {** where, "labels": seats})["ok"];
    assert call(
        "",
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": s, "ticket_type": "ADULT"} for s in seats]
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

def _count(desk: any, amount: str) -> str {  # jac:ignore[W1037]
    # Saves a count; what the page says.
    _type(desk, "#cash-counted", amount);
    desk.click('[data-testid="cash-up"] button[type="submit"]');
    desk.wait_for_function(
        f"document.querySelector('[data-testid=cash-up-result]')?.innerText.includes('You counted KES {amount};')"
    );
    return desk.inner_text('[data-testid="cash-up-result"]');
}

def _tab(page: any, key: str) -> any {  # jac:ignore[W1037]
    # Opens a tab: what's listed in it.
    page.click(f'[data-testid="recon-tab-{key}"]');
    page.wait_for_selector(f'[data-testid="recon-tab-{key}"][aria-pressed="true"]');
    return page.locator('[data-testid="exception"]');
}

test "cash counts are listed in tabs, counted on the sidebar, resolved, and seen in the console" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            agent = add_staff(owner, "box_office_agent", owner["venue"]);
            _sale_by(owner, agent, ["A1", "A2"]);
            # The agent counts: what they sold isn't shown until they have.
            desk = _sign_in(browser, pw, project, agent["email"]);
            desk.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
            desk.click('[data-testid="sale-kind-cash"]');
            desk.wait_for_selector('[data-testid="cash-up"]');
            assert "KES 1,660" not in desk.inner_text('[data-testid="cash-up"]');
            # Not an amount.
            _type(desk, "#cash-counted", "abc");
            desk.click('[data-testid="cash-up"] button[type="submit"]');
            desk.wait_for_selector(
                '[data-testid="cash-up"] [role="alert"]:has-text("Enter the cash you counted")'
            );
            assert desk.locator('[data-testid="cash-up-result"]').count() == 0;
            # KES 60 short.
            said = _count(desk, "1,600");
            assert "You counted KES 1,600; you recorded KES 1,660" in said , said;
            assert "KES 60 short" in said and "your manager will see it" in said , said;
            # Straight away again: nothing since, so it matches.
            said = _count(desk, "0");
            assert "you recorded KES 0" in said and "It matches." in said , said;
            # One more sale (KES 830), and KES 1,000 counted: over.
            _sale_by(owner, agent, ["A3"]);
            said = _count(desk, "1,000");
            assert "you recorded KES 830" in said and "KES 170 over" in said , said;
            assert desk.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # The box office has no Reconciliation page.
            assert desk.locator(
                f'a[href="/app/{owner["slug"]}/reconciliation"]'
            ).count()
                == 0;
            assert desk.locator('[data-testid="nav-count-reconciliation"]').count()
                == 0;
            desk.goto(f"{BASE_URL}/app/{owner['slug']}/reconciliation");
            desk.wait_for_selector('[data-testid="no-access"]');
            desk.context.close();
            # The owner's sidebar counts both; they're on the Cash tab, in words.
            page = _sign_in(browser, pw, project, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/reconciliation");
            page.wait_for_selector('[data-testid="open-exceptions"]');
            assert page.inner_text('[data-testid="open-exceptions"]') == "2 to look at";
            counted = page.locator('[data-testid="nav-count-reconciliation"]').first;
            counted.wait_for(state="attached");
            assert counted.text_content().startswith("2") , counted.text_content();
            assert page.locator('[data-testid="statement-upload"]').count() == 0;
            assert page.locator('#statement-file').count() == 0;
            # M-Pesa is first, with nothing in it.
            assert _tab(page, "mpesa").count() == 0;
            assert "Nothing to look at here."
                in page.inner_text('[data-testid="nothing-here"]');
            assert "2" in page.inner_text('[data-testid="recon-tab-cash"]');
            rows = _tab(page, "cash");
            assert rows.count() == 2;
            short = rows.filter(has_text="Cash short at a cash-up");
            over = rows.filter(has_text="Cash over at a cash-up");
            said = short.inner_text();
            assert "Cash sales recorded: KES 1,660" in said
                and "Cash counted: KES 1,600" in said
                and "KES 60 short" in said , said;
            assert "ours" not in said and "theirs" not in said , said;
            assert agent["email"] in said;
            assert "Cash sales recorded: KES 830" in over.inner_text()
                and "KES 170 over" in over.inner_text();
            # At the cinema's time (Nairobi), whatever the browser is set to.
            local = datetime.now(timezone.utc).astimezone(ZoneInfo("Africa/Nairobi"));
            assert local.strftime("%H:") in said , said;
            # A note is needed.
            short.locator('button:has-text("Mark resolved")').click();
            short.locator(
                '[role="alert"]:has-text("Say how it was sorted out")'
            ).wait_for();
            short.locator("input").fill("Counted again: KES 60 was in the float.");  # jac:ignore[W6002]
            short.locator('button:has-text("Mark resolved")').click();
            page.wait_for_selector(
                '[data-testid="open-exceptions"]:has-text("1 to look at")'
            );
            page.wait_for_function(
                "document.querySelector('[data-testid=nav-count-reconciliation]')?.textContent.startsWith('1')"
            );
            # The over one is still on Cash; the short one is on Resolved, with its note.
            assert _tab(page, "cash").count() == 1;
            assert "Cash over at a cash-up"
                in page.locator('[data-testid="exception"]').nth(0).inner_text();
            # The three counts are listed under Cash.
            counts = page.inner_text('[data-testid="cash-ups"]');
            assert "counted KES 1,600, recorded KES 1,660" in counts , counts;
            assert "counted KES 1,000, recorded KES 830" in counts;
            assert "counted KES 0, recorded KES 0" in counts;
            done = _tab(page, "resolved");
            assert done.count() == 1;
            last = done.nth(0).inner_text();
            assert "Resolved" in last
                and "Counted again: KES 60 was in the float." in last , last;
            assert page.locator('[data-testid="cash-ups"]').count() == 0;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.context.close();
            # The console: AfriCinemas' takings, and the open exceptions only.
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            _type(us, "#email", admin);
            _type(us, "#password", PASSWORD);
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.wait_for_selector('[data-testid="platform-takings"] table');
            takings = us.inner_text('[data-testid="platform-takings"]');
            for heading in [
                "Month",
                "Cinema",
                "Fees earned",
                "Invoiced",
                "Paid",
                "Overdue"
            ] {
                assert heading in takings , heading;
            }
            assert owner["name"] in takings;
            assert us.locator(
                '[data-testid="platform-takings"] table[aria-label="By month"]'
            ).count()
                == 1;
            assert us.locator(
                '[data-testid="platform-takings"] table[aria-label="By cinema"]'
            ).count()
                == 1;
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: overview scrolls sideways";
            us.goto(PLATFORM_URL + "/reconciliation");
            us.wait_for_selector('[data-testid="platform-reconciliation"]');
            listed = us.locator('[data-testid="platform-exception"]');
            # Its open cash over is there; the resolved short one isn't.
            mine = listed.filter(has_text=agent["email"]);
            assert mine.count() == 1 and "Cash over" in mine.inner_text();
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            us.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
