"""P13.5a E2E: a cinema asks AfriCinemas for help, and we answer.

A cinema's owner opens Help in their back office, starts a new request about payments
and sends it with Enter; it opens as a chat. The platform's super admin finds it in
the console's Support inbox, under Open, opens the chat and replies; the owner sees the
answer, with the status now waiting on them, replies back, and finds the conversation
in their list with its last message. Phone and desktop, with the usual phone checks.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PLATFORM_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { owner_with_cinema, platform_admin, PASSWORD }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _go(page: any, project: str, section: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.click('[data-testid="shell-menu-button"]');
        page.wait_for_selector('[data-testid="shell-drawer"]', state="visible");
        page.click(f'[data-testid="shell-drawer"] nav a:has-text("{section}")');
    } else {
        page.click(f'[data-testid="shell-sidebar"] nav a:has-text("{section}")');
    }
}

test "a cinema asks for help, AfriCinemas answers, and the cinema sees the answer" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema("Eldoret Electric");
            cinema = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            cinema.goto(BASE_URL + "/login");
            cinema.fill("#email", owner["email"]);  # jac:ignore[W6002]
            cinema.fill("#password", PASSWORD);  # jac:ignore[W6002]
            cinema.click('button[type="submit"]');
            cinema.wait_for_url("**/app");
            cinema.goto(f"{BASE_URL}/app/{owner['slug']}");
            _go(cinema, project, "Help");
            cinema.wait_for_selector('[data-testid="help-section"]');
            cinema.click('[data-testid="help-new"]');
            cinema.select_option("#help-category", "payments");
            problem = f"M-Pesa prompts never arrive ({project}).";
            cinema.fill("#help-text", problem);  # jac:ignore[W6002]
            # Enter sends, as in a messaging app; the chat opens.
            cinema.press("#help-text", "Enter");
            cinema.wait_for_selector('[data-testid="help-chat"]');
            assert "/help/" in cinema.url , cinema.url;
            assert problem in cinema.inner_text('[data-testid="support-thread"]');
            assert "Waiting for AfriCinemas"
                in cinema.inner_text('[data-testid="help-status"]');
            assert cinema.evaluate(WIDE_JS) <= 1 , f"{project}: help scrolls sideways";
            cinema.screenshot(path=artifact(f"help-{project}.png"), full_page=True);
            # AfriCinemas: the inbox, the request, a reply.
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            us.fill("#email", admin);  # jac:ignore[W6002]
            us.fill("#password", PASSWORD);  # jac:ignore[W6002]
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            _go(us, project, "Support");
            us.wait_for_selector('[data-testid="support-inbox"]');
            row = us.locator('[data-testid="support-row"]', has_text=problem);
            row.wait_for();
            assert "Eldoret Electric" in row.inner_text();
            assert us.evaluate(WIDE_JS) <= 1 , f"{project}: inbox scrolls sideways";
            us.screenshot(
                path=artifact(f"support-inbox-{project}.png"), full_page=True
            );
            row.locator("a").click();
            us.wait_for_selector('[data-testid="support-request"]');
            us.fill("#support-reply-text", "Which phone number did you try?");  # jac:ignore[W6002]
            us.click('[data-testid="chat-send"]');
            us.wait_for_selector(
                '[data-testid="support-status"]:has-text("Waiting for the cinema")'
            );
            assert us.evaluate(WIDE_JS) <= 1 , f"{project}: request scrolls sideways";
            us.screenshot(
                path=artifact(f"support-request-{project}.png"), full_page=True
            );
            # The cinema sees the answer in the chat, and it's their turn.
            cinema.reload();
            cinema.wait_for_selector(
                '[data-testid="support-thread"]:has-text("Which phone number did you try?")'
            );
            assert "AfriCinemas" in cinema.inner_text('[data-testid="support-thread"]');
            assert "AfriCinemas replied"
                in cinema.inner_text('[data-testid="help-status"]');
            cinema.screenshot(
                path=artifact(f"help-chat-{project}.png"), full_page=True
            );
            cinema.fill("#help-reply", "0712 345 678");  # jac:ignore[W6002]
            cinema.press("#help-reply", "Enter");
            cinema.wait_for_selector(
                '[data-testid="help-status"]:has-text("Waiting for AfriCinemas")'
            );
            # Back to the list: the conversation, with its last message.
            cinema.click('a:has-text("All requests")');
            row = cinema.locator('[data-testid="help-request"]').first;
            row.wait_for();
            assert "0712 345 678" in row.inner_text();
            cinema.context.close();
            us.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
