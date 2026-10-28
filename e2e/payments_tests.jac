"""P15.3 E2E: connecting a cinema's own M-Pesa, testing it, and a change that waits.

A verified cinema's owner opens Settings → Payments: not connected yet, with the
verified business's name filled in. They connect their Paybill with its Daraja keys and
their password, send the KES 1 test payment, and say they've paid it: payments go to
their Paybill, and the keys appear nowhere on the page. They then change to a Till: its
test goes through, but the change waits its 24 hours while the Paybill stays in use,
and they cancel it. Another business's name is refused with the reason, a test payment
that fails leaves the account unused, and the keys aren't on the page even after a
reload. The super admin's setup video plays above the written steps, and the owner
books a setup call (a day and a number are needed), which opens as a Help request.
A super admin sets the video's link on the console's Fees page (an http link is
refused). A public cinema that AfriCinemas hasn't verified is told so on Verification,
and its Payments page asks for verification first, with no form.
Phone and desktop, no sideways scrolling. The 24 hours passing, and customers'
payments reaching each account, are in tests/integration/mpesa_account_tests.jac
(they need a test-only clock).
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PLATFORM_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api {
    PASSWORD,
    platform_admin,
    platform_session,
    call,
    owner_with_cinema
}
import from e2e.support.catalog { cinema_selling_tickets }
import from e2e.support.verification { verified }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     # Made-up keys, built so no secret-looking text is in the source.
     KEYS: dict[str, str] = {
         "#mpesa-consumer-key": "e" * 14 + "7QRS",
         "#mpesa-consumer-secret": "f" * 21,
         "#mpesa-passkey": "g" * 64
     };

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _keys_and_password(page: any) {  # jac:ignore[W1037]
    for (selector, value) in KEYS.items() {
        _type(page, selector, value);
    }
    _type(page, "#mpesa-password", PASSWORD);
    page.click('[data-testid="mpesa-form"] button[type="submit"]');
    page.wait_for_selector('[data-testid="mpesa-pending"]');
}

def _tested(page: any) {  # jac:ignore[W1037]
    _type(page, "#mpesa-test-phone", "0712345678");
    page.click('button:has-text("Send KES 1 test")');
    page.wait_for_selector('[data-testid="mpesa-pending"] [role="status"]');
    page.click('button:has-text("I\'ve paid it")');
}

test "an owner connects M-Pesa, tests it, and cancels a change that waits" {
    # AfriCinemas' setup video, set by the super admin, plays above the steps.
    (_, admin) = platform_session(platform_admin());
    assert call(admin, "set_mpesa_guide_video", {"url": "https://youtu.be/dQw4w9WgXcQ"})[
        "ok"
    ];
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets(live=False);
            verified(owner);
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(BASE_URL + "/login");
            _type(page, "#email", owner["email"]);
            _type(page, "#password", PASSWORD);
            page.click('button[type="submit"]');
            page.wait_for_url("**/app**");
            page.goto(f"{BASE_URL}/app/{owner['slug']}/settings/payments");
            page.wait_for_selector('[data-testid="mpesa-form"]');
            assert "Not connected yet"
                in page.inner_text('[data-testid="mpesa-active"]');
            assert page.input_value("#mpesa-name") == "Nova Cinemas Ltd";
            page.click('[data-testid="mpesa-guide"] summary');
            page.wait_for_selector('[data-testid="mpesa-guide"] li >> visible=true');
            assert "youtube-nocookie.com/embed/dQw4w9WgXcQ"
                in page.get_attribute('[data-testid="mpesa-video"]', "src");
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            _type(page, "#mpesa-shortcode", "600100");
            # Another business's name is refused, and says why.
            _type(page, "#mpesa-name", "Someone Else Ltd");
            for (selector, value) in KEYS.items() {
                _type(page, selector, value);
            }
            _type(page, "#mpesa-password", PASSWORD);
            page.click('[data-testid="mpesa-form"] button[type="submit"]');
            page.wait_for_function(
                "document.querySelector('[data-testid=mpesa-problem]').innerText.includes('Nova Cinemas Ltd')"
            );
            assert page.locator('[data-testid="mpesa-pending"]').count() == 0;
            _type(page, "#mpesa-name", "Nova Cinemas Ltd");
            _keys_and_password(page);
            # A test that doesn't go through leaves it unused (0700 000 001 fails).
            _type(page, "#mpesa-test-phone", "0700000001");
            page.click('button:has-text("Send KES 1 test")');
            page.wait_for_selector('[data-testid="mpesa-pending"] [role="status"]');
            page.click('button:has-text("I\'ve paid it")');
            page.wait_for_function(
                "document.querySelector('[data-testid=mpesa-pending]').innerText.includes(\"didn't go through\")"
            );
            assert "Not connected yet"
                in page.inner_text('[data-testid="mpesa-active"]');
            _tested(page);
            page.wait_for_function(
                "document.querySelector('[data-testid=mpesa-active]').innerText.includes('Paybill 600100')"
            );
            assert "7QRS" in page.inner_text('[data-testid="mpesa-active"]');
            # The keys are nowhere on the page, then or after a reload.
            for again in [False, True] {
                if again {
                    page.reload();
                    page.wait_for_selector('[data-testid="mpesa-active"]');
                }
                html = page.content();
                for value in KEYS.values() {
                    assert value not in html , f"{project}: a key is on the page";
                }
            }
            # A change to a Till waits its 24 hours, and is cancelled.
            page.click('button:has-text("Change M-Pesa")');
            page.check('input[name="mpesa-kind"][value="till"]');
            _type(page, "#mpesa-shortcode", "700200");
            _type(page, "#mpesa-till", "800300");
            _keys_and_password(page);
            _tested(page);
            page.wait_for_selector('[data-testid="mpesa-waiting"]');
            assert "Till 800300" in page.inner_text('[data-testid="mpesa-pending"]');
            assert "Paybill 600100" in page.inner_text('[data-testid="mpesa-active"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.click('button:has-text("Cancel this change")');
            page.wait_for_selector('[data-testid="mpesa-pending"]', state="detached");
            assert "Paybill 600100" in page.inner_text('[data-testid="mpesa-active"]');
            # Booking a setup call files a Help request.
            page.click('button:has-text("Book a setup call")');
            # A day and a number are needed.
            page.click('[data-testid="setup-call-form"] button[type="submit"]');
            page.wait_for_selector(
                '[data-testid="setup-call"] [role="alert"]:has-text("Choose a day")'
            );
            _type(page, "#setup-call-day", "2099-01-15");
            page.select_option("#setup-call-time", "midday");
            _type(page, "#setup-call-phone", "0712345678");
            page.click('[data-testid="setup-call-form"] button[type="submit"]');
            page.wait_for_selector('[data-testid="setup-call-booked"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            link = page.get_attribute('[data-testid="setup-call-booked"] a', "href");
            assert f"/app/{owner['slug']}/help/" in link , link;
            asked = call(owner["token"], "support_requests", {"tenant": owner["slug"]});
            booked = [
                r
                for r in asked["requests"]
                if r["category"] == "setup_call"
            ];
            said = booked[0]["messages"][0]["text"] if booked else "";
            assert "Preferred time: Midday (12 to 3)" in said
                and "Phone: 0712345678" in said , asked;
            # The link opens the request in Help (straight onto it: JI-037 crashed here).
            page.click('[data-testid="setup-call-booked"] a');
            page.wait_for_function(
                "document.body.innerText.includes('Preferred time: Midday (12 to 3)')"
            );
            # Answered, so the shared support inbox is as the other tests expect.
            request_id = booked[0]["request_id"];
            call(admin, "platform_support_seen", {"request_id": request_id});
            call(
                admin,
                "platform_support_status",
                {"request_id": request_id, "status": "closed"}
            );
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

def _owner_page(browser: any, pw: any, project: str, email: str) -> any {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, "light")).new_page();
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app**");
    return page;
}

test "a public cinema AfriCinemas hasn't verified is told so, and can't connect M-Pesa" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            # Made public by a super admin without a review: not verified.
            owner = owner_with_cinema("Rupa Screens");
            page = _owner_page(browser, pw, project, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/verification");
            page.wait_for_function(
                "document.querySelector('[data-testid=verification-status]')?.innerText.includes(\"hasn't verified it yet\")"
            );
            assert "verified and public"
                not in page.inner_text('[data-testid="verification-status"]');
            assert page.locator('[data-testid="share-link"]').count() == 0;
            page.wait_for_selector('[data-testid="verification-form"]');
            page.goto(f"{BASE_URL}/app/{owner['slug']}/settings/payments");
            page.wait_for_selector('[data-testid="mpesa-blocked"]');
            assert "verifies your business first"
                in page.inner_text('[data-testid="mpesa-blocked"]');
            assert page.locator('[data-testid="mpesa-form"]').count() == 0;
            assert page.locator('[data-testid="setup-call"]').count() == 0;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a super admin sets the setup video's link on the console's Fees page" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            _type(us, "#email", admin);
            _type(us, "#password", PASSWORD);
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.goto(PLATFORM_URL + "/fees");
            us.wait_for_selector('[data-testid="setup-video"] #setup-video-url');
            _type(us, "#setup-video-url", "http://youtu.be/dQw4w9WgXcQ");
            us.click('[data-testid="setup-video"] button[type="submit"]');
            us.wait_for_selector(
                '[data-testid="setup-video"] [role="status"]:has-text("https link")'
            );
            # The same link the other test plays, so the order of tests doesn't matter.
            _type(us, "#setup-video-url", "https://youtu.be/dQw4w9WgXcQ");
            us.click('[data-testid="setup-video"] button[type="submit"]');
            us.wait_for_selector(
                '[data-testid="setup-video"] [role="status"]:has-text("Saved")'
            );
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            us.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
