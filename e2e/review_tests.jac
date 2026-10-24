"""P14.5 E2E: a reviewer asks for changes, then approves; the cinema goes public, verified.

An owner submits their cinema's verification. The platform's super admin opens Reviews,
finds it, opens the ID photo, and asks for a change with a reason. The owner resubmits;
the reviewer ticks the checklist and approves. A visitor then finds the storefront, with
"Verified cinema" in its footer. Phone and desktop, no sideways scrolling.
"""

import io;
import base64;
import from PIL { Image }
import from pypdf { PdfWriter }
import from e2e.support.web {
    shared_browser,
    close_contexts,
    PLATFORM_URL,
    BASE_URL,
    PROJECTS,
    context_options,
    store_url,
    artifact
}
import from e2e.support.api { platform_admin, PASSWORD, call }
import from e2e.support.catalog { cinema_selling_tickets }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     DETAILS: dict[str, str] = {
         "legal_name": "Kimani Wanjiru",
         "id_number": "12345678",
         "phone": "0712 345 678",
         "registered_name": "Nova Cinemas Ltd",
         "business_type": "limited_company",
         "registration_number": "PVT-ABC123",
         "kra_pin": "P051234567Q",
         "permit_expiry": "2099-12-31",
         "premises_address": "Westgate Mall, Nairobi"
     };

def _png -> str {
    out = io.BytesIO();
    Image.new("RGB", (900, 600), (40, 90, 160)).save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _pdf -> str {
    writer = PdfWriter();
    writer.add_blank_page(width=200, height=200);
    out = io.BytesIO();
    writer.write(out);
    return base64.b64encode(out.getvalue()).decode();
}

def _submitted(owner: dict[str, str]) {
    tenant = owner["slug"];
    token = owner["token"];
    assert call(token, "save_verification", {"tenant": tenant, "details": DETAILS})[
        "ok"
    ];
    for (item, kind, data) in [
        ("id_front", "image/png", _png()),
        ("id_back", "image/png", _png()),
        ("registration_certificate", "application/pdf", _pdf()),
        ("kra_certificate", "application/pdf", _pdf()),
        ("county_permit", "application/pdf", _pdf())
    ] {
        sent = call(
            token,
            "upload_verification_file",
            {"tenant": tenant, "item": item, "content_type": kind, "data_base64": data}
        );
        assert sent["ok"] , sent;
    }
    for kind in ["terms", "privacy", "refunds"] {
        assert call(
            token,
            "save_policy",
            {
                "tenant": tenant,
                "kind": kind,
                "text": "Ours.",
                "published": True,
                "reviewed": True
            }
        )["ok"];
    }
    done = call(token, "submit_verification", {"tenant": tenant});
    assert done["ok"] , done;
}

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

test "changes are asked, then the cinema is approved and public with its badge" {
    admin = platform_admin();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets(live=False);
            _submitted(owner);
            us = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            us.goto(PLATFORM_URL + "/sign-in");
            _type(us, "#email", admin);
            _type(us, "#password", PASSWORD);
            us.click('[data-testid="platform-sign-in"] button[type="submit"]');
            us.wait_for_selector('[data-testid="platform-overview"]');
            us.goto(PLATFORM_URL + "/reviews");
            row = f'[data-testid="review-row"][href="/reviews/{owner["slug"]}"]';
            us.wait_for_selector(row);
            us.click(row);
            us.wait_for_selector('[data-testid="review-page"]');
            assert "P051234567Q" in us.inner_text('[data-testid="review-page"]');
            us.click('[data-testid="open-id_front"]');
            us.wait_for_selector('[data-testid="shown-id_front"]');
            assert us.is_disabled('[data-testid="approve-verification"]');
            assert us.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            _type(
                us,
                "#review-reasons",
                "The ID photo is blurred. Take it again in good light."
            );
            us.click('[data-testid="ask-changes"]');
            us.wait_for_function(
                "document.querySelector('[data-testid=review-status]').innerText === 'Changes asked'"
            );
            mine = call(owner["token"], "verification", {"tenant": owner["slug"]});
            assert mine["editable"] and "blurred" in mine["reasons"][0] , mine;
            # The owner resubmits, and the reviewer approves.
            assert call(
                owner["token"], "submit_verification", {"tenant": owner["slug"]}
            )["ok"];
            us.reload();
            us.wait_for_selector('[data-testid="review-decision"]');
            checks = us.locator('[data-testid="review-check"]');
            for n in range(checks.count()) {
                checks.nth(n).check();
            }
            us.click('[data-testid="approve-verification"]');
            us.wait_for_function(
                "document.querySelector('[data-testid=review-status]').innerText === 'Approved'"
            );
            us.context.close();
            # The owner's back office shows it.
            office = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            office.goto(BASE_URL + "/login");
            _type(office, "#email", owner["email"]);
            _type(office, "#password", PASSWORD);
            office.click('button[type="submit"]');
            office.wait_for_url("**/app");
            office.goto(f"{BASE_URL}/app/{owner['slug']}");
            office.wait_for_selector('[data-testid="backoffice-verified"]');
            # And on Your cinemas.
            office.goto(f"{BASE_URL}/app");
            office.wait_for_selector('[data-testid="cinema-list"]');
            try {
                office.wait_for_selector(
                    f'[data-testid="cinema-list"] a[href="/app/{owner[
                        "slug"
                    ]}"] [data-testid="cinema-verified"]'
                );
            } except Exception as e {
                office.screenshot(
                    path=artifact(f"your-cinemas-{project}.png"), full_page=True
                );
                raise e;
            }
            office.context.close();
            visitor = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            visitor.goto(store_url(owner["slug"]) + "/");
            visitor.wait_for_selector('footer [data-testid="verified-badge"]');
            # And at the top, beside the logo, linking to the same check.
            pill = visitor.get_attribute('[data-testid="verified-pill"]', "href") or "";
            assert pill.endswith(f"/verified/{owner['slug']}") , pill;
            assert "Verified cinema"
                in visitor.inner_text('[data-testid="verified-badge"]');
            # The badge links to the check on AfriCinemas' own site, which confirms it.
            href = visitor.get_attribute('[data-testid="verified-badge"]', "href")
                or "";
            assert href.endswith(f"/verified/{owner['slug']}") , href;
            visitor.goto(href);
            visitor.wait_for_selector('[data-testid="verified-yes"]');
            visitor.goto(href.replace(owner["slug"], "no-such-cinema-here"));
            visitor.wait_for_selector('[data-testid="verified-no"]');
            visitor.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
