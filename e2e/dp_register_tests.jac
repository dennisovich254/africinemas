"""P15.0 E2E: the data protection registers in the console, on phone and desktop.

A super admin opens Data protection from the console's navigation. On Requests, they
log an access request from a cinema's customer: it's listed with its number, when it's
due and when to pass it on; answering without a note is refused; with one, it's
answered and can't change. On Breaches, they log one of both kinds of data: its two
clocks show; they assess it and add a step, which joins its record. No sideways
scrolling. The deadlines and who may see them: tests/integration/dp_register_tests.jac.
"""

import uuid;
import from e2e.support.web {
    shared_browser,
    close_contexts,
    PLATFORM_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { platform_admin, PASSWORD }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _fill(field: any, value: str) {  # jac:ignore[W1037]
    field.fill(value);  # jac:ignore[W6002]
}

def _go(page: any, project: str, section: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.click('[data-testid="shell-menu-button"]');
        page.wait_for_selector('[data-testid="shell-drawer"]', state="visible");
        page.click(f'[data-testid="shell-drawer"] nav a:has-text("{section}")');
    } else {
        page.click(f'[data-testid="shell-sidebar"] nav a:has-text("{section}")');
    }
}

test "a super admin logs a request and a breach, and records what was done" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(PLATFORM_URL + "/sign-in");
            _type(page, "#email", admin);
            _type(page, "#password", PASSWORD);
            page.click('[data-testid="platform-sign-in"] button[type="submit"]');
            page.wait_for_selector('[data-testid="platform-overview"]');
            _go(page, project, "Data protection");
            page.wait_for_selector('[data-testid="data-protection"]');
            assert page.get_attribute('[data-testid="dp-tab-requests"]', "aria-pressed")
                == "true";
            # A request, unique to this run (the server is shared).
            who = f"Wanjiru {uuid.uuid4().hex[:6]}";
            page.select_option("#dp-kind", "access");
            _type(page, "#dp-person", who);
            _type(page, "#dp-contact", "wanjiru@example.com");
            _type(page, "#dp-cinema", "nova");
            _type(page, "#dp-asked", "A copy of everything you hold about me.");
            page.click('[data-testid="dp-new-request"] button[type="submit"]');
            mine = page.locator('[data-testid="dp-request"]').filter(has_text=who);
            mine.wait_for();
            said = mine.inner_text();
            assert "Access: a copy of their data" in said and "due" in said , said;
            assert "pass to the cinema by" in said and "a customer of nova" in said;
            # Answered needs a note; with one, it's done and can't change.
            mine.locator("select").select_option("answered");
            mine.locator('button[type="submit"]').click();
            mine.locator('[role="alert"]:has-text("Say what was done")').wait_for();
            _fill(mine.locator("input"), "Sent the export by email.");
            mine.locator('button[type="submit"]').click();
            mine.locator(
                '[data-testid="dp-events"]:has-text("Sent the export by email.")'
            ).wait_for();
            assert mine.locator("select").count() == 0;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: requests scroll sideways";
            # A breach of both kinds of data: both clocks.
            page.click('[data-testid="dp-tab-breaches"]');
            page.wait_for_selector('[data-testid="dp-new-breach"]');
            what = f"Screenshot link public ({uuid.uuid4().hex[:6]})";
            page.select_option("#dp-role", "both");
            _type(page, "#dp-what", what);
            page.click('[data-testid="dp-new-breach"] button[type="submit"]');
            breach = page.locator('[data-testid="dp-breach"]').filter(has_text=what);
            breach.wait_for();
            said = breach.inner_text();
            assert "tell cinemas by" in said
                and "notify the Commissioner by" in said , said;
            # Assessed, then a step: both join its record.
            breach.locator('[id^="notifiable-"]').select_option("yes");
            _fill(
                breach.locator('[id^="why-"]'), "Phone numbers with receipts (reg 37)."
            );
            breach.locator('button:has-text("Save the assessment")').click();
            breach.locator(
                '[data-testid="dp-events"]:has-text("Notifiable: yes")'
            ).wait_for();
            breach.locator('[id^="step-"]').select_option("contained");
            _fill(breach.locator('[id^="note-"]'), "Link revoked.");
            breach.locator('button:has-text("Add")').click();
            breach.locator(
                '[data-testid="dp-events"]:has-text("Link revoked.")'
            ).wait_for();
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: breaches scroll sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
