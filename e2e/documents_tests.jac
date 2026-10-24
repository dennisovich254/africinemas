"""P14.3d E2E: a cinema's licence as a PDF, uploaded in Settings and opened by a visitor.

The owner uploads the KFCB licence in Settings › Documents; a visitor on the cinema's own
address finds it in the footer and opens the PDF from its page. A policy published as a
PDF alone shows Open the PDF on its page. Phone and desktop, no sideways scrolling.
"""

import io;
import os;
import base64;
import tempfile;
import from pypdf { PdfWriter }
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

glob WIDE_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _pdf_bytes -> bytes {
    writer = PdfWriter();
    writer.add_blank_page(width=200, height=200);
    out = io.BytesIO();
    writer.write(out);
    return out.getvalue();
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

test "the owner uploads the licence, and a visitor opens it from the footer" {
    owner = cinema_selling_tickets();
    store = store_url(owner["slug"]);
    path = os.path.join(tempfile.mkdtemp(prefix="africinemas-pdf-"), "licence.pdf");
    with open(path, "wb") as f {
        f.write(_pdf_bytes());
    }
    (pw, browser) = shared_browser();
    try {
        for (n, project) in enumerate(PROJECTS) {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            title = f"KFCB film exhibition licence {n + 1}";
            _sign_in(page, owner["email"]);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/settings/documents");
            page.wait_for_selector('[data-testid="document-upload"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: scrolls sideways";
            _type(page, "#document-title", title);
            page.set_input_files("#document-file", path);
            page.click('[data-testid="document-upload"] button[type="submit"]');
            page.wait_for_function(
                "document.querySelector('[data-testid=documents-saved]').innerText.includes('Uploaded')"
            );
            assert page.locator('[data-testid="document-row"]').count() == n + 1;
            # A visitor, on the cinema's own address.
            page.goto(store + "/");
            link = f'footer [data-testid="info-documents"] a:has-text("{title}")';
            page.wait_for_selector(link);
            page.click(link);
            page.wait_for_selector('[data-testid="open-pdf-link"]');
            assert "/documents/" in page.url;
            assert (
                page.get_attribute('[data-testid="open-pdf-link"]', "href") or ""
            ).startswith(
                "blob:"
            );
            assert title in page.inner_text('[data-testid="document-page"]');
            assert page.evaluate(WIDE_JS) <= 0 , f"{project}: the document scrolls sideways";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a policy published as a PDF alone opens from its page" {
    owner = cinema_selling_tickets();
    tenant = {"tenant": owner["slug"], "kind": "refunds"};
    attached = call(
        owner["token"],
        "upload_policy_pdf",
        {** tenant, "data_base64": base64.b64encode(_pdf_bytes()).decode()}
    );
    assert attached["ok"] , attached;
    published = call(
        owner["token"],
        "save_policy",
        {** tenant, "text": "", "published": True, "reviewed": True}
    );
    assert published["ok"] , published;
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(store_url(owner["slug"]) + "/policies/refunds");
            page.wait_for_selector(
                '[data-testid="policy-page"] [data-testid="open-pdf-link"]'
            );
            assert "Refunds and cancellations"
                in page.inner_text('[data-testid="policy-page"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
