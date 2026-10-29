"""P15.6, P15.6b E2E: counting cash and reconciliation, on phone and desktop.

The owner sets the box office's rules on Settings → Box office (6 hours, at most
KES 400,000). A box office agent sells A1 and A2 for cash (KES 1,660). On Count cash:
- what they sold isn't shown first; "abc" and KES 450,000 (over the limit) are
  refused;
- KES 1,600 is shown large and in words before saving; Change goes back; saving says
  KES 60 short, and the shift carries on;
- "Count again" corrects it to KES 1,660 (matches; "Corrected from KES 1,600");
- after one more sale (KES 830), KES 1,000 is KES 170 over;
- after another sale, Sign out asks for a count first (Not now stays); Count now opens
  Count cash, and once it's counted, Sign out now signs them out.
The agent has no Reconciliation page. In the console, Reconciliation lists the open
cash over but not the corrected short, and the takings tables include the cinema. The
owner's sidebar counts 1; the Cash tab says what each amount is (no "ours"/"theirs"), at
the cinema's time; resolving with a note clears the count; Resolved has both, the
corrected one "by the count"; the counts are listed, the correction with its first
figure. Last, the agent sells again and leaves without signing out: the next agent at
the venue is shown their cash, counts it on their behalf, and signs out with nothing to
count.
The daily M-Pesa check, and "Cash not counted": tests/integration/reconcile_tests.jac.
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

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SIDEBAR: str = '[data-testid="shell-sidebar"]',
     MENU: str = '[data-testid="shell-menu-button"]',
     DRAWER: str = '[data-testid="shell-drawer"]';

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

def _check(desk: any, amount: str) -> any {  # jac:ignore[W1037]
    # Types an amount and asks to save it: the dialog that shows it back.
    _type(desk, "#cash-counted", amount);
    desk.click('[data-testid="cash-up"] button[type="submit"]');
    return desk.locator('[data-testid="cash-confirm"]');
}

def _count(desk: any, amount: str) -> str {  # jac:ignore[W1037]
    # Saves a count; what the page says.
    shown = _check(desk, amount);
    shown.wait_for();
    shown.locator('button:has-text("Save count")').click();
    desk.wait_for_function(
        f"document.querySelector('[data-testid=cash-up-result]')?.innerText.includes('You counted KES {amount};')"
    );
    return desk.inner_text('[data-testid="cash-up-result"]');
}

def _on_shift(page: any) {  # jac:ignore[W1037]
    # Starts the member's shift if the page asks for one (once it's loaded).
    page.wait_for_selector('[data-testid="shell-title"]');
    page.wait_for_load_state("networkidle");
    banner = page.locator('[data-testid="shift-banner"]');
    if banner.count() > 0 {
        banner.locator("button").first.click();
        banner.wait_for(state="detached");
    }
}

def _sign_out(page: any, project: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        # The menu may still be open (after "Not now").
        if not page.locator(DRAWER).is_visible() {
            page.click(MENU);
        }
        page.wait_for_selector(DRAWER, state="visible");
        page.click(f'{DRAWER} button:has-text("Sign out")');
    } else {
        page.click(f'{SIDEBAR} button:has-text("Sign out")');
    }
}

def _tab(page: any, key: str) -> any {  # jac:ignore[W1037]
    # Opens a tab: what's listed in it.
    page.click(f'[data-testid="recon-tab-{key}"]');
    page.wait_for_selector(f'[data-testid="recon-tab-{key}"][aria-pressed="true"]');
    return page.locator('[data-testid="exception"]');
}

test "cash is counted to end a shift, checked, corrected, reminded, and reconciled in tabs" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            agent = add_staff(owner, "box_office_agent", owner["venue"]);
            # The owner's rules: 6-hour shifts, at most KES 400,000 a count.
            page = _sign_in(browser, pw, project, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/settings/box-office");
            page.wait_for_selector('[data-testid="box-office-rules"]');
            _on_shift(page);
            assert page.input_value("#shift-hours") == "8";
            assert page.input_value("#cash-count-max") == "500000";
            _type(page, "#shift-hours", "13");
            page.click('[data-testid="box-office-rules"] button[type="submit"]');
            page.wait_for_selector(
                '[data-testid="box-office-rules"] [role="alert"]:has-text("from 1 to 12")'
            );
            _type(page, "#shift-hours", "6");
            _type(page, "#cash-count-max", "400,000");
            page.click('[data-testid="box-office-rules"] button[type="submit"]');
            page.wait_for_selector(
                '[data-testid="box-office-rules"] [role="status"]:has-text("Saved")'
            );
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: settings scroll sideways";
            # The agent sells two seats, and counts: what they sold isn't shown.
            _sale_by(owner, agent, ["A1", "A2"]);
            desk = _sign_in(browser, pw, project, agent["email"]);
            desk.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
            desk.click('[data-testid="sale-kind-cash"]');
            desk.wait_for_selector('[data-testid="cash-up"]');
            assert "KES 1,660" not in desk.inner_text('[data-testid="cash-up"]');
            alert = '[data-testid="cash-up"] [role="alert"]';
            # Not an amount; more than the cinema's limit.
            _check(desk, "abc");
            desk.wait_for_selector(f'{alert}:has-text("Enter the cash you counted")');
            _check(desk, "450,000");
            desk.wait_for_selector(f'{alert}:has-text("more than KES 400,000")');
            assert desk.locator('[data-testid="cash-confirm"]').count() == 0;
            # Shown back large and in words; Change goes back without saving.
            shown = _check(desk, "1,600");
            shown.wait_for();
            assert shown.locator('[data-testid="cash-confirm-amount"]').inner_text()
                == "KES 1,600";
            assert shown.locator('[data-testid="cash-confirm-words"]').text_content()
                == "one thousand six hundred shillings";
            shown.locator('button:has-text("Change")').click();
            shown.wait_for(state="detached");
            assert desk.locator('[data-testid="cash-up-result"]').count() == 0;
            # Saved: KES 60 short, and the shift carries on.
            said = _count(desk, "1,600");
            assert "You counted KES 1,600; you recorded KES 1,660" in said , said;
            assert "KES 60 short" in said and "your manager will see it" in said , said;
            assert desk.locator('[data-testid="shift-banner"]').count() == 0;
            # Corrected once: it matches, and says what it was.
            desk.click('[data-testid="count-again"]');
            again = _check(desk, "1,660");
            again.wait_for();
            again.locator('button:has-text("Save count")').click();
            desk.wait_for_selector(
                '[data-testid="cash-up-result"]:has-text("It matches.")'
            );
            assert "Corrected from KES 1,600"
                in desk.inner_text('[data-testid="cash-up"]');
            assert desk.locator('[data-testid="count-again"]').count() == 0;
            # One more sale (KES 830), and KES 1,000: over.
            _sale_by(owner, agent, ["A3"]);
            desk.reload();
            desk.click('[data-testid="sale-kind-cash"]');
            desk.wait_for_selector("#cash-counted");
            said = _count(desk, "1,000");
            assert "you recorded KES 830" in said and "KES 170 over" in said , said;
            assert desk.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # Another sale, then Sign out: a count first, with no way round it.
            _sale_by(owner, agent, ["A4"]);
            desk.goto(f"{BASE_URL}/app/{owner['slug']}");
            desk.wait_for_selector('[data-testid="shell-title"]');
            _sign_out(desk, project);
            reminder = desk.locator('[data-testid="uncounted-cash"]');
            reminder.wait_for();
            assert "Count your cash before you sign out" in reminder.inner_text();
            assert reminder.locator('button:has-text("Sign out anyway")').count() == 0;
            reminder.locator('button:has-text("Not now")').click();
            reminder.wait_for(state="detached");
            assert "/login" not in desk.url;
            _sign_out(desk, project);
            reminder.wait_for();
            reminder.locator('button:has-text("Count now")').click();
            desk.wait_for_url(f"**/app/{owner['slug']}/box-office/sign-out");
            if project == "mobile" {
                desk.keyboard.press("Escape");
                desk.wait_for_selector(DRAWER, state="hidden");
            }
            desk.wait_for_selector(
                '[data-testid="cash-up"] h2:has-text("Count your cash to sign out")'
            );
            shown = _check(desk, "830");
            shown.wait_for();
            assert "Once it's saved, you can sign out." in shown.inner_text();
            shown.locator('button:has-text("Save count")').click();
            desk.wait_for_selector(
                '[data-testid="cash-up-result"]:has-text("It matches.")'
            );
            desk.click('[data-testid="cash-sign-out"]');
            desk.wait_for_url("**/login**");
            # The box office has no Reconciliation page (signed in again).
            desk.context.close();
            desk = _sign_in(browser, pw, project, agent["email"]);
            desk.goto(f"{BASE_URL}/app/{owner['slug']}");
            desk.wait_for_selector('[data-testid="shell-title"]');
            assert desk.locator(
                f'a[href="/app/{owner["slug"]}/reconciliation"]'
            ).count()
                == 0;
            assert desk.locator('[data-testid="nav-count-reconciliation"]').count()
                == 0;
            desk.goto(f"{BASE_URL}/app/{owner['slug']}/reconciliation");
            desk.wait_for_selector('[data-testid="no-access"]');
            # The console: AfriCinemas' takings, and only the open cash over.
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
            mine = us.locator('[data-testid="platform-exception"]').filter(
                has_text=agent["email"]
            );
            mine.first.wait_for();
            assert mine.count() == 1 and "Cash over" in mine.inner_text();
            assert "Cash sales recorded: KES 830" in mine.inner_text();
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            us.context.close();
            # The owner: the sidebar counts 1, on the Cash tab, in words.
            page.goto(f"{BASE_URL}/app/{owner['slug']}/reconciliation");
            page.wait_for_selector('[data-testid="open-exceptions"]');
            assert page.inner_text('[data-testid="open-exceptions"]') == "1 to look at";
            counted = page.locator('[data-testid="nav-count-reconciliation"]').first;
            counted.wait_for(state="attached");
            assert counted.text_content().startswith("1") , counted.text_content();
            assert page.locator('#statement-file').count() == 0;
            assert _tab(page, "mpesa").count() == 0;
            assert "Nothing to look at here."
                in page.inner_text('[data-testid="nothing-here"]');
            rows = _tab(page, "cash");
            assert rows.count() == 1;
            over = rows.nth(0);
            said = over.inner_text();
            assert "Cash over at a cash-up" in said;
            assert "Cash sales recorded: KES 830" in said
                and "Cash counted: KES 1,000" in said
                and "KES 170 over" in said , said;
            assert "ours" not in said and "theirs" not in said , said;
            assert agent["email"] in said;
            # At the cinema's time (Nairobi), whatever the browser is set to.
            local = datetime.now(timezone.utc).astimezone(ZoneInfo("Africa/Nairobi"));
            assert local.strftime("%H:") in said , said;
            # A note is needed; then the count goes.
            over.locator('button:has-text("Mark resolved")').click();
            over.locator(
                '[role="alert"]:has-text("Say how it was sorted out")'
            ).wait_for();
            over.locator("input").fill("KES 170 was change from the float.");  # jac:ignore[W6002]
            over.locator('button:has-text("Mark resolved")').click();
            page.wait_for_selector(
                '[data-testid="open-exceptions"]:has-text("Nothing to look at")'
            );
            page.wait_for_selector(
                '[data-testid="nav-count-reconciliation"]', state="detached"
            );
            # The counts are listed under Cash, the correction with its first figure.
            assert _tab(page, "cash").count() == 0;
            counts = page.inner_text('[data-testid="cash-ups"]');
            assert "counted KES 1,660, recorded KES 1,660; first counted KES 1,600"
                in counts , counts;
            assert "counted KES 1,000, recorded KES 830" in counts;
            assert "counted KES 830, recorded KES 830" in counts;
            # Resolved: the corrected short "by the count", and the over with its note.
            done = _tab(page, "resolved");
            assert done.count() == 2;
            short = done.filter(has_text="Cash short at a cash-up").inner_text();
            assert "Resolved by the count" in short
                and "first counted KES 1,600" in short , short;
            assert "KES 170 was change from the float."
                in done.filter(has_text="Cash over at a cash-up").inner_text();
            assert page.locator('[data-testid="cash-ups"]').count() == 0;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.context.close();
            # Last: the agent sells again and leaves without signing out. The next agent
            # at the venue is shown their cash, and counts it on their behalf.
            _sale_by(owner, agent, ["A5"]);
            desk.context.close();
            other = add_staff(owner, "box_office_agent", owner["venue"]);
            nxt = _sign_in(browser, pw, project, other["email"]);
            nxt.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
            _on_shift(nxt);
            nxt.click('[data-testid="sale-kind-cash"]');
            left = nxt.locator('[data-testid="left-cash"]');
            left.wait_for();
            assert f"{agent['email']} didn't count their cash" in left.inner_text();
            assert "They're still signed in" in left.inner_text();
            left.locator("input").fill("830");  # jac:ignore[W6002]
            left.locator('button[type="submit"]').click();
            shown = nxt.locator('[data-testid="cash-confirm"]');
            shown.wait_for();
            assert f"You're counting {agent['email']}'s cash." in shown.inner_text();
            shown.locator('button:has-text("Save count")').click();
            nxt.wait_for_selector(
                f'[data-testid="left-cash-result"]:has-text("{agent[
                    "email"
                ]} recorded KES 830")'
            );
            assert "It matches." in nxt.inner_text('[data-testid="left-cash-result"]');
            assert nxt.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            # With nothing of their own to count, Sign out goes straight out.
            _sign_out(nxt, project);
            nxt.wait_for_url("**/login**");
            nxt.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
