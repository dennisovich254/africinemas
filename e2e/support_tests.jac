"""P13.5a E2E: a cinema asks AfriCinemas for help, and we answer.

A cinema's owner opens Help in their back office, starts a new request about payments
and sends it with Enter; it opens as a chat. The platform's super admin sees it counted
on Support, opens the chat (which clears the count) and replies; the owner sees the
reply counted on Help and on its row, opens it (which clears the count, with no
refresh), replies back, and our open chat shows that without a refresh. Phone and desktop, with the usual phone checks.
"""

import os;
import time;
import from pathlib { Path }
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

glob LIVE_MS: int = 15000,
     WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _screenshot -> str {
    # A PNG on disk, for the file picker.
    import from PIL { Image }
    path = artifact("support-screenshot.png");
    Image.new("RGB", (640, 400), (30, 90, 160)).save(path, format="PNG");
    return str(path);
}

def _mailed(to: str, words: str) -> bool {
    # Whether the server's outbox (scripts/e2e_env.sh) gets an email to `to` with
    # `words`, within LIVE_MS: the mail job runs every 2 seconds there.
    folder = Path(os.environ.get("AFRICINEMAS_OUTBOX_DIR", "e2e/artifacts/outbox"));
    for _ in range(int(LIVE_MS / 500)) {
        for f in (folder.glob("*.eml") if folder.exists() else []) {
            text = f.read_text(errors="replace");
            if to in text and words in text {
                return True;
            }
        }
        time.sleep(0.5);
    }
    return False;
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
            # With a screenshot: chosen, shown as a thumbnail, sent with the message.
            cinema.set_input_files('[data-testid="chat-file"]', _screenshot());
            cinema.wait_for_selector('[data-testid="chat-attached"]');
            # Enter sends, as in a messaging app; the chat opens.
            cinema.press("#help-text", "Enter");
            cinema.wait_for_selector('[data-testid="help-chat"]');
            assert "/help/" in cinema.url , cinema.url;
            assert problem in cinema.inner_text('[data-testid="support-thread"]');
            cinema.wait_for_selector(
                '[data-testid="support-thread"] [data-testid="support-image"]'
            );
            assert "Waiting for AfriCinemas"
                in cinema.inner_text('[data-testid="help-status"]');
            assert cinema.evaluate(WIDE_JS) <= 1 , f"{project}: help scrolls sideways";
            cinema.screenshot(path=artifact(f"help-{project}.png"), full_page=True);
            # Back to the list, as a cinema would while it waits for us.
            cinema.click('a:has-text("All requests")');
            cinema.wait_for_selector('[data-testid="help-section"]');
            # AfriCinemas: the Support link counts what we haven't read; the request.
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            us.fill("#email", admin);  # jac:ignore[W6002]
            us.fill("#password", PASSWORD);  # jac:ignore[W6002]
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.wait_for_selector('[data-testid="nav-count-support"]', state="attached");
            _go(us, project, "Support");
            us.wait_for_selector('[data-testid="support-inbox"]');
            row = us.locator('[data-testid="support-row"]', has_text=problem);
            row.wait_for();
            assert "Eldoret Electric" in row.inner_text();
            assert row.locator('[data-testid="support-unread"]').count() == 1;
            assert us.evaluate(WIDE_JS) <= 1 , f"{project}: inbox scrolls sideways";
            us.screenshot(
                path=artifact(f"support-inbox-{project}.png"), full_page=True
            );
            row.locator("a").click();
            us.wait_for_selector('[data-testid="support-request"]');
            # The cinema's screenshot, for us to read too.
            us.wait_for_selector(
                '[data-testid="support-thread"] [data-testid="support-image"]'
            );
            us.fill("#support-reply-text", "Which phone number did you try?");  # jac:ignore[W6002]
            us.click('[data-testid="chat-send"]');
            us.wait_for_selector(
                '[data-testid="support-status"]:has-text("Waiting for the cinema")'
            );
            assert us.evaluate(WIDE_JS) <= 1 , f"{project}: request scrolls sideways";
            us.screenshot(
                path=artifact(f"support-request-{project}.png"), full_page=True
            );
            # Our reply emails the cinema's owner (the server's outbox in tests).
            assert _mailed(owner["email"], "AfriCinemas replied") , "no email to the owner";
            # Read: our count is gone.
            us.wait_for_selector(
                '[data-testid="nav-count-support"]', state="detached", timeout=LIVE_MS
            );
            # The cinema: an unread reply, counted on Help and on its row.
            cinema.reload();
            counted = cinema.locator('[data-testid="nav-count-help"]').first;
            counted.wait_for(state="attached", timeout=LIVE_MS);
            assert counted.text_content().startswith("1") , counted.text_content();
            mine = cinema.locator(
                '[data-testid="help-request"]', has_text="Which phone number"
            );
            mine.wait_for();
            assert mine.locator('[data-testid="help-unread"]').count() == 1;
            # Opening it reads it: the count clears at once, no refresh.
            mine.locator("a").click();
            cinema.wait_for_selector('[data-testid="help-chat"]');
            assert "AfriCinemas" in cinema.inner_text('[data-testid="support-thread"]');
            assert "AfriCinemas replied"
                in cinema.inner_text('[data-testid="help-status"]');
            cinema.wait_for_selector(
                '[data-testid="nav-count-help"]', state="detached", timeout=LIVE_MS
            );
            cinema.screenshot(
                path=artifact(f"help-chat-{project}.png"), full_page=True
            );
            cinema.fill("#help-reply", "0712 345 678");  # jac:ignore[W6002]
            cinema.press("#help-reply", "Enter");
            cinema.wait_for_selector(
                '[data-testid="help-status"]:has-text("Waiting for AfriCinemas")'
            );
            # Ours shows it without a refresh: the open chat asks every few seconds.
            us.wait_for_selector(
                '[data-testid="support-thread"]:has-text("0712 345 678")',
                timeout=LIVE_MS
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
