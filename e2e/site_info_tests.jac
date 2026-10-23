"""P14.3a E2E: a cinema's public information, filled in once and shown on every page.

The owner fills Settings › Website information (business name, contact, WhatsApp, social
media, directions, booking notes) and saves; a field with a problem says so beside it.
On the cinema's own address a visitor sees it in the footer of every page, with the
default design and inside the footer an AI wrote; "Getting here" on the Cinemas page and
"Good to know" before choosing tickets. Phone and desktop, no sideways scrolling.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    store_url
}
import from e2e.support.api { PASSWORD, call }
import from e2e.support.catalog { cinema_selling_tickets }
import from e2e.support.designs { ai_designed }

glob FORM: str = '[data-testid="site-info"]',
     STRIP: str = 'footer [data-testid="footer-info"]',
     WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     INFO: dict[str, any] = {  # jac:ignore[W1037]
         "business_name": "Nova Cinemas Ltd",
         "address": "Westgate Mall, Mwanzi Road, Nairobi",
         "phone": "0712 345 678",
         "whatsapp": "0798 765 432",
         "socials": {"instagram": "nova_cinemas"},
         "directions": "Third floor, by the food court.",
         "ticket_notes": [{"name": "Child", "note": "Under 12."}]
     };

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
}

def _saved(owner: dict[str, str]) {
    answer = call(
        owner["token"], "save_site_info", {"tenant": owner["slug"], "info": INFO}
    );
    assert answer["ok"] , answer;
}

test "the owner fills Website information, and a problem shows beside its field" {
    owner = cinema_selling_tickets();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/settings/website");
            page.wait_for_selector(FORM);
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            _type(page, "#info-business_name", "Nova Cinemas Ltd");
            _type(page, "#info-phone", "12");
            _type(page, "#info-whatsapp", "0798 765 432");
            _type(page, "#info-social-instagram", "@nova_cinemas");
            page.click('[data-testid="add-ticket-note"]');
            _type(page, "#info-note-0-name", "Child");
            _type(page, "#info-note-0-note", "Under 12.");
            page.click(f'{FORM} button[type="submit"]');
            page.wait_for_selector('#info-phone[aria-invalid="true"]');
            _type(page, "#info-phone", "0712 345 678");
            page.click(f'{FORM} button[type="submit"]');
            page.wait_for_function(
                "document.querySelector('[data-testid=site-info-saved]').innerText.includes('Saved')"
            );
            # Saved as the storefront shows it: a full number, the handle alone.
            assert page.input_value("#info-phone") == "+254712345678";
            assert page.input_value("#info-social-instagram") == "nova_cinemas";
            page.reload();
            page.wait_for_selector(FORM);
            assert page.input_value("#info-note-0-name") == "Child";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a visitor sees it in the footer of every page, and the visit and booking notes" {
    owner = cinema_selling_tickets();
    _saved(owner);
    store = store_url(owner["slug"]);
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            for path in ["/", "/movies", "/cinemas", f"/s/{owner['show']}"] {
                page.goto(store + path);
                page.wait_for_selector(STRIP);
                strip = page.inner_text(STRIP);
                assert "Nova Cinemas Ltd" in strip , f"{path}: {strip}";
                assert "Tickets by AfriCinemas" not in page.inner_text("footer");
                assert page.evaluate(WIDE_JS) <= 0 , f"{project} {path}: scrolls sideways";
            }
            page.goto(store + "/");
            page.wait_for_selector(STRIP);
            assert page.get_attribute(f'{STRIP} a[href^="tel:"]', "href")
                == "tel:+254712345678";
            assert page.get_attribute(f'{STRIP} a[href^="https://wa.me/"]', "href")
                == "https://wa.me/254798765432";
            assert page.get_attribute(f'{STRIP} [data-testid="info-socials"] a', "href")
                == "https://www.instagram.com/nova_cinemas";
            page.goto(store + "/cinemas");
            page.wait_for_selector('[data-testid="getting-here"]');
            assert "Third floor" in page.inner_text('[data-testid="getting-here"]');
            page.goto(f"{store}/s/{owner['show']}");
            page.wait_for_selector('[data-testid="good-to-know"]');
            assert "Under 12." in page.inner_text('[data-testid="good-to-know"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "under an AI-written design, it's inside the AI's footer" {
    owner = cinema_selling_tickets();
    _saved(owner);
    ai_designed(owner);
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(store_url(owner["slug"]) + "/");
            page.wait_for_selector('[data-testid="ai-header"]');
            info = '[data-testid="ai-footer"] [data-testid="footer-info"]';
            page.wait_for_selector(info);
            assert "Nova Cinemas Ltd" in page.inner_text(info);
            # One footer: nothing of ours below the AI's.
            assert page.locator('[data-testid="footer-info"]').count() == 1;
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
