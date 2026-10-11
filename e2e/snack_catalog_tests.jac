"""P12.1 E2E: the snack catalog in the back office (design guide docs/snacks-guide.md).

An owner opens Snacks, goes to Categories and adds the usual six in one tap. They add
Popcorn in Popcorn: "has variants" starts with Size (Small, Medium, Large); they fill
two SKUs and prices and save the draft; Publish is refused and the missing Large price
and SKU show beside that row; filled in, it publishes. The list shows "3 variants",
"From KES 200" and Active, and finds it by SKU. A box office agent sees the list and
the product, read-only. Phone and PC, light and dark (screenshots for review).
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call, owner_with_cinema, add_venue, add_staff, PASSWORD }

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
    page.goto(f"{BASE_URL}/app/{slug}/snacks{rest}");
}

def _said(page: any, testid: str, words: str) {  # jac:ignore[W1037]
    page.wait_for_function(
        f"(document.querySelector('[data-testid={testid}]')?.innerText || '').includes({repr(
            words
        )})"
    );
}

def _stocked(owner: dict[str, str]) -> str {
    # Through the API: the usual categories and a published Popcorn. Returns its id.
    def made(name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
        got = call(owner["token"], name, {"tenant": owner["slug"], ** args});
        assert got["ok"] , (name, got);
        return got;
    }
    kinds = made("add_default_snack_categories", {})["categories"];
    popcorn = [
        c
        for c in kinds
        if c["name"] == "Popcorn"
    ][0]["category_id"];
    product = made(
        "save_snack_product",
        {
            "product_id": "",
            "name": "Popcorn",
            "brand": "",
            "description": "Freshly popped",
            "tags": [],
            "category_id": popcorn,
            "kind": "variants",
            "option_names": ["Size"],
            "variants": [
                {
                    "variant_id": "",
                    "option_values": [size],
                    "sku": sku,
                    "barcode": "",
                    "price_cents": price,
                    "available": True,
                    "track_stock": False
                }
                for (size, sku, price) in [
                    ("Small", "POP-SM", 20000),
                    ("Medium", "POP-MD", 30000),
                    ("Large", "POP-LG", 40000)
                ]
            ]
        }
    )["product"]["product_id"];
    made("publish_snack_product", {"product_id": product});
    return product;
}

test "an owner builds a product with variants, and publishing checks it" {
    owner = owner_with_cinema();
    add_venue(owner);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"], owner["slug"], "/categories");
        page.click('button:has-text("Add the usual categories")');
        _said(page, "categories-message", "Added the usual categories");
        names = page.locator('[data-testid="category-name"]').all_inner_texts();
        assert names[:2] == ["Popcorn", "Beverages"] and len(names) == 6 , names;
        # A product with variants.
        page.click('nav[aria-label="Snacks"] a:has-text("Products")');
        page.click('[data-testid="add-product"]');
        page.wait_for_selector('[data-testid="snack-editor"]');
        _type(page, "#p-name", "Popcorn");
        page.select_option("#p-category_id", label="Popcorn");
        page.click('[data-testid="kind-variants"]');
        rows = page.locator('[data-testid="variant-row"]');
        assert rows.count() == 3 , "Popcorn starts with Small, Medium and Large";
        _type(page, "#p-variants-0-sku", "pop-sm");
        _type(page, "#p-variants-0-price_cents", "200");
        _type(page, "#p-variants-1-sku", "POP-MD");
        _type(page, "#p-variants-1-price_cents", "300");
        page.click('[data-testid="save-product"]');
        _said(page, "editor-message", "Saved");
        page.wait_for_url("**/snacks/*");
        # Publishing names what's missing, beside the Large row.
        page.click('[data-testid="publish"]');
        page.wait_for_selector("#p-variants-2-price_cents-error");
        assert "Large" in page.inner_text("#p-variants-2-price_cents-error");
        page.wait_for_selector("#p-variants-2-sku-error");
        _type(page, "#p-variants-2-sku", "POP-LG");
        _type(page, "#p-variants-2-price_cents", "400");
        page.click('[data-testid="publish"]');
        _said(page, "editor-message", "Published");
        assert page.inner_text('[data-testid="editor-status"]') == "Active";
        assert page.input_value("#p-variants-0-sku") == "POP-SM";
        # The list shows it, and finds it by SKU.
        page.click('a:has-text("← Products")');
        row = page.locator('[data-testid="product-row"]', has_text="Popcorn");
        row.wait_for();
        text = row.inner_text();
        assert "3 variants" in text and "Active" in text , text;
        assert "From KES 200"
            in row.locator('[data-testid="product-price"]').inner_text();
        _type(page, "#product-search", "pop-lg");
        assert page.locator('[data-testid="product-row"]').count() == 1;
        _type(page, "#product-search", "nachos");
        page.wait_for_selector("text=No products match");
    } finally {
        close_contexts(browser);
    }
}

test "the box office reads the catalog without editing it" {
    owner = owner_with_cinema();
    venue = add_venue(owner);
    _stocked(owner);
    agent = add_staff(owner, "box_office_agent", venue);
    call(agent["token"], "start_shift", {"tenant": owner["slug"]});
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_in(page, agent["email"], owner["slug"]);
        row = page.locator('[data-testid="product-row"]', has_text="Popcorn");
        row.wait_for();
        assert page.locator('[data-testid="add-product"]').count() == 0;
        row.tap();
        page.wait_for_selector('[data-testid="snack-editor"]');
        assert page.locator('[data-testid="save-product"]').count() == 0;
        assert page.locator("#p-variants-0-sku").is_disabled();
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the snack catalog" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = owner_with_cinema();
                add_venue(owner);
                product = _stocked(owner);
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _sign_in(page, owner["email"], owner["slug"]);
                page.wait_for_selector('[data-testid="product-row"]');
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"snack-products-{project}-{scheme}.png"),
                    full_page=True
                );
                page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks/{product}");
                page.wait_for_selector('[data-testid="variant-table"]');
                page.screenshot(
                    path=artifact(f"snack-editor-{project}-{scheme}.png"),
                    full_page=True
                );
                page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks/categories");
                page.wait_for_selector('[data-testid="category-row"]');
                page.screenshot(
                    path=artifact(f"snack-categories-{project}-{scheme}.png"),
                    full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
