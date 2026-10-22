"""P12.5 E2E: faster catalog work (design guide §4).

- Templates: Add product offers Popcorn, Beverage, Packaged snack, Combo or blank;
  Popcorn starts in the Popcorn category with Small, Medium and Large.
- Import: a CSV with a bad row shows the row number and what to fix, and Import stays
  off; fixed, the preview lists the new products and Import makes them (as drafts).
- Duplicate opens a new draft "Copy of …" without SKUs.
- Bulk: ticking two products and Publish publishes the one that can be, and says why
  the other can't.
Screenshots of the template picker and the import preview, mobile and desktop.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call, owner_with_cinema, add_venue, PASSWORD }

glob GOOD_CSV: str = "product_name,category,variant,sku,price\nPopcorn,Popcorn,Small,POP-SM,200\nPopcorn,Popcorn,Large,POP-LG,400\nCoca-Cola 500 ml,Beverages,,COKE-500,150\n",
     BAD_CSV: str = "product_name,category,variant,sku,price\nPopcorn,Popcorn,Small,POP-SM,200\nCoca-Cola 500 ml,Beverages,,COKE-500,free\n";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _sign_in(page: any, email: str, slug: str, rest: str = "") {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
    page.goto(f"{BASE_URL}/app/{slug}/snacks/{rest}");
}

def _upload(page: any, text: str) {  # jac:ignore[W1037]
    page.set_input_files(
        '[data-testid="import-file"]',
        {"name": "snacks.csv", "mimeType": "text/csv", "buffer": text.encode()}
    );
}

def _owner -> dict[str, str] {
    owner = owner_with_cinema();
    add_venue(owner);
    call(owner["token"], "add_default_snack_categories", {"tenant": owner["slug"]});
    return owner;
}

test "a template starts Popcorn with its sizes in its category" {
    owner = _owner();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_in(page, owner["email"], owner["slug"], "new");
        page.wait_for_selector('[data-testid="template-picker"]');
        page.locator('[data-testid="template-popcorn"]').tap();
        page.wait_for_selector('[data-testid="snack-editor"]');
        assert page.locator("#p-category_id option:checked").inner_text() == "Popcorn";
        page.locator('[data-testid="step-pricing"]').tap();
        assert page.locator('[data-testid="variant-row"]').count() == 3;
    } finally {
        close_contexts(browser);
    }
}

test "an import shows bad rows first, then makes the products" {
    owner = _owner();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"], owner["slug"], "import");
        page.wait_for_selector('[data-testid="snack-import"]');
        _upload(page, BAD_CSV);
        page.wait_for_selector('[data-testid="import-errors"]');
        assert "Row 3, price" in page.inner_text('[data-testid="import-errors"]');
        assert page.locator('[data-testid="run-import"]').is_disabled();
        _upload(page, GOOD_CSV);
        page.wait_for_selector('[data-testid="import-summary"]');
        assert page.locator('[data-testid="import-product"]').count() == 2;
        page.click('[data-testid="run-import"]');
        page.wait_for_selector('[data-testid="import-result"]');
        assert "2 new products" in page.inner_text('[data-testid="import-result"]');
        page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks");
        page.locator('[data-testid="product-row"]', has_text="Popcorn").wait_for();
        assert "Draft"
            in page.locator(
                '[data-testid="product-row"]', has_text="Popcorn"
            ).inner_text();
    } finally {
        close_contexts(browser);
    }
}

test "duplicate opens a copy without SKUs, and bulk publish answers per product" {
    owner = _owner();
    call(
        owner["token"],
        "import_snack_catalog",
        {
            "tenant": owner["slug"],
            "csv_text": GOOD_CSV,
            "mapping": {},
            "create_categories": False
        }
    );
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"], owner["slug"]);
        page.locator('[data-testid="product-row"]', has_text="Popcorn").locator(
            "a"
        ).click();
        page.wait_for_selector('[data-testid="snack-editor"]');
        page.click('[data-testid="duplicate-product"]');
        page.wait_for_function(
            "document.querySelector('#p-name')?.value === 'Copy of Popcorn'"
        );
        page.click('[data-testid="step-pricing"]');
        assert page.input_value("#p-variants-0-sku") == "";
        page.click('a:has-text("← Products")');
        page.locator(
            '[data-testid="product-row"]', has_text="Copy of Popcorn"
        ).wait_for();
        page.locator(
            '[data-testid="select-product"][aria-label="Select Popcorn"]'
        ).check();
        page.locator(
            '[data-testid="select-product"][aria-label="Select Copy of Popcorn"]'
        ).check();
        page.locator('[data-testid="bulk-actions"] button:has-text("Publish")').click();
        page.wait_for_function(
            "(document.querySelector('[data-testid=bulk-note]')?.innerText || '').includes('Published 1 of 2')"
        );
        assert "Copy of Popcorn" in page.inner_text('[data-testid="bulk-note"]');
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of templates and the import" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = _owner();
            page = browser.new_context(
                **context_options(pw, project, "light"), reduced_motion="reduce"
            ).new_page();
            _sign_in(page, owner["email"], owner["slug"], "new");
            page.wait_for_selector('[data-testid="template-picker"]');
            page.screenshot(
                path=artifact(f"snack-templates-{project}.png"), full_page=True
            );
            page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks/import");
            page.wait_for_selector('[data-testid="snack-import"]');
            _upload(page, GOOD_CSV);
            page.wait_for_selector('[data-testid="import-summary"]');
            page.screenshot(
                path=artifact(f"snack-import-{project}.png"), full_page=True
            );
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
