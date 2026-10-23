"""P14.3c E2E: above Pay, what paying agrees to; and the box for the cinema's offers.

Nova publishes its terms, refunds and privacy policies and says it sends offers. At
checkout the notice above Pay links to each, opening in a new tab; the offers box is
there and not ticked. A customer who signs up sees the same notice, and finds the
offers choice in My account. Phone and desktop, no sideways scrolling.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { call, unique, email_for }
import from e2e.support.catalog { cinema_selling_tickets }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     NOTICE: str = '[data-testid="agree-notice"]';

def _seat(label: str) -> str {
    return f'[data-testid="seat"][data-seat="{label}"]';
}

def _press(page: any, project: str, selector: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.locator(selector).tap();
    } else {
        page.locator(selector).click();
    }
}

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _ready(owner: dict[str, str]) {
    # Nova's policies published, and it sends offers.
    for kind in ["terms", "refunds", "privacy"] {
        saved = call(
            owner["token"],
            "save_policy",
            {
                "tenant": owner["slug"],
                "kind": kind,
                "text": "## Ours\n\nAs agreed.",
                "published": True,
                "reviewed": True
            }
        );
        assert saved["ok"] , saved;
    }
    info = call(
        owner["token"],
        "save_site_info",
        {"tenant": owner["slug"], "info": {"sends_offers": True}}
    );
    assert info["ok"] , info;
}

test "above Pay, the notice links to the policies, and the offers box starts unticked" {
    owner = cinema_selling_tickets();
    _ready(owner);
    (pw, browser) = shared_browser();
    try {
        for (n, project) in enumerate(PROJECTS) {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            # Each run its own two seats: the last run's are still held.
            (first, second) = (f"A{2 * n + 1}", f"A{2 * n + 2}");
            page.goto(f"{BASE_URL}/c/{owner['slug']}/s/{owner['show']}");
            page.wait_for_selector(_seat(first));
            _press(page, project, _seat(first));
            _press(page, project, _seat(second));
            _press(page, project, '[data-testid="hold-seats"]');
            # The order is priced before Pay works (as in payment_tests).
            page.wait_for_function(
                "document.querySelector('[data-testid=checkout-total]')?.innerText === 'KES 1,660'"
            );
            _press(page, project, '[data-testid="pay"]');
            page.wait_for_selector(f'[data-testid="pay-panel"] {NOTICE} a');
            notice = page.inner_text(NOTICE);
            assert "By paying, you agree to this cinema's terms of ticket sale and refund policy."
                in notice , notice;
            assert "Its privacy policy says how your details are used." in notice;
            links = page.locator(f"{NOTICE} a");
            assert links.count() == 3;
            for n in range(3) {
                assert links.nth(n).get_attribute("target") == "_blank";
            }
            assert "/policies/terms" in (links.nth(0).get_attribute("href") or "");
            assert not page.is_checked("#offers");
            page.check("#offers");
            assert page.is_checked("#offers");
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "signing up shows the notice, and My account has the offers choice" {
    owner = cinema_selling_tickets();
    _ready(owner);
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            account = f"/c/{owner['slug']}/account";
            page.goto(f"{BASE_URL}/c/{owner['slug']}/sign-up?next={account}");
            page.wait_for_selector(f'[data-testid="customer-sign-up"] {NOTICE} a');
            assert "By creating an account, you agree to" in page.inner_text(NOTICE);
            assert not page.is_checked("#offers");
            _type(page, "#name", "Kim");
            _type(page, "#email", email_for(unique("kim")));
            _type(page, "#password", "Kim-Passw0rd!");
            page.check("#offers");
            _press(
                page, project, '[data-testid="customer-sign-up"] button[type="submit"]'
            );
            # Signed in, and back at the account page (not a glob: the sign-up page's
            # own URL would match one).
            page.wait_for_function("!!localStorage.getItem('jac_token')");
            page.wait_for_url(
                lambda (url: str) -> bool { return "/sign-" not in url
                    and url.endswith(account); }
            );
            page.wait_for_selector("#account-offers");
            assert page.is_checked("#account-offers");
            # Not uncheck(): the box changes once the cinema has answered.
            page.click("#account-offers");
            page.wait_for_function(
                "!document.querySelector('#account-offers').checked && !document.querySelector('#account-offers').disabled"
            );
            page.reload();
            page.wait_for_selector("#account-offers");
            assert not page.is_checked("#account-offers");
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
