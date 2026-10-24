"""P14.4 E2E: the owner verifies themself and the business, and submits for review.

A cinema not yet live, set up (venue, screen, prices) with its policies published. Its
owner opens Verification, reads why each item is asked for, fills the details (a wrong
KRA PIN is flagged beside its field), uploads the ID photos and the certificates, and
submits. The page then says it's with AfriCinemas, and nothing can be changed. Phone
and desktop, no sideways scrolling; on a phone the ID box takes a photo.
"""

import io;
import os;
import tempfile;
import from PIL { Image }
import from pypdf { PdfWriter }
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options
}
import from e2e.support.api { PASSWORD, call }
import from e2e.support.catalog { cinema_selling_tickets }

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     FIELDS: dict[str, str] = {
         "#verify-legal_name": "Kimani Wanjiru",
         "#verify-id_number": "12345678",
         "#verify-phone": "0712 345 678",
         "#verify-registered_name": "Nova Cinemas Ltd",
         "#verify-registration_number": "PVT-ABC123",
         "#verify-premises_address": "Westgate Mall, Nairobi"
     };

def _files -> tuple[str, str] {
    folder = tempfile.mkdtemp(prefix="africinemas-verify-");
    photo = os.path.join(folder, "id.png");
    Image.new("RGB", (900, 600), (40, 90, 160)).save(photo, format="PNG");
    pdf = os.path.join(folder, "certificate.pdf");
    writer = PdfWriter();
    writer.add_blank_page(width=200, height=200);
    with open(pdf, "wb") as f {
        writer.write(f);
    }
    return (photo, pdf);
}

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

def _ready(owner: dict[str, str]) {
    for kind in ["terms", "privacy", "refunds"] {
        saved = call(
            owner["token"],
            "save_policy",
            {
                "tenant": owner["slug"],
                "kind": kind,
                "text": "Ours.",
                "published": True,
                "reviewed": True
            }
        );
        assert saved["ok"] , saved;
    }
}

def _uploaded(page: any, item: str, path: str) {  # jac:ignore[W1037]
    page.set_input_files(f"#verify-file-{item}", path);
    page.wait_for_selector(f'[data-testid="verify-file-{item}-chosen"]');
}

test "the owner fills the details, uploads the documents and submits for review" {
    (photo, pdf) = _files();
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets(live=False);
            _ready(owner);
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/verification");
            page.wait_for_selector('[data-testid="verification-form"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            page.click('[data-testid="data-notice"] summary');
            assert "90 days" in page.inner_text('[data-testid="data-notice"]');
            assert page.is_disabled('[data-testid="submit-verification"]');
            for (selector, value) in FIELDS.items() {
                _type(page, selector, value);
            }
            page.select_option("#verify-business_type", "limited_company");
            _type(page, "#verify-permit_expiry", "2099-12-31");
            _type(page, "#verify-kra_pin", "123");
            page.click('[data-testid="verification-form"] button[type="submit"]');
            page.wait_for_selector('#verify-kra_pin[aria-invalid="true"]');
            _type(page, "#verify-kra_pin", "P051234567Q");
            page.click('[data-testid="verification-form"] button[type="submit"]');
            page.wait_for_function(
                "document.querySelector('[data-testid=verification-saved]').innerText === 'Saved.'"
            );
            # The ID boxes take a photo on a phone.
            accept = page.get_attribute("#verify-file-id_front", "accept") or "";
            assert "image/jpeg" in accept and "application/pdf" in accept;
            for item in ["id_front", "id_back"] {
                _uploaded(page, item, photo);
            }
            for item in [
                "registration_certificate",
                "kra_certificate",
                "county_permit"
            ] {
                _uploaded(page, item, pdf);
            }
            page.wait_for_selector(
                '[data-testid="submit-verification"]:not([disabled])'
            );
            page.click('[data-testid="submit-verification"]');
            page.wait_for_function(
                "document.querySelector('[data-testid=verification-status]')?.innerText.includes('for review')"
            );
            assert page.locator('[data-testid="verification-submit"]').count() == 0;
            assert page.is_disabled("#verify-legal_name");
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways after";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
