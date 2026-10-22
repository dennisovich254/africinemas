"""P12.1 E2E: the snack catalog in the back office (design guide docs/snacks-guide.md).

An owner opens Snacks, goes to Categories and adds the usual six in one tap. They add
Popcorn in Popcorn: "has variants" starts with Size (Small, Medium, Large); they fill
two SKUs and prices and save the draft; Publish is refused and the missing Large price
and SKU show beside that row; filled in, it publishes. The list shows "3 variants",
"From KES 200" and Active, and finds it by SKU. A box office agent sees the list and
the product, read-only. Phone and PC, light and dark (screenshots for review).

The editor runs in steps (improvements #9): a new product adds its category on the spot
and takes images before its first save, which uploads them.
"""

import io;
import from PIL { Image }
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
    # Waits for the page's announcement to contain `words`; if it never does, fails
    # with what the page said instead and every error shown beside a field.
    try {
        page.wait_for_function(
            f"(document.querySelector('[data-testid={testid}]')?.innerText || '').includes({repr(
                words
            )})"
        );
    } except Exception as e {
        said = page.evaluate(
            f"document.querySelector('[data-testid={testid}]')?.innerText || ''"
        );
        alerts = page.locator('[role="alert"]').all_inner_texts();
        raise AssertionError(
            f"waited for {words!r}; the page said {said!r}; errors: {alerts}"
        ) from e;
    }
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
        page.wait_for_selector('[data-testid="category-row"]');
        names = page.locator('[data-testid="category-name"]').all_inner_texts();
        assert names[:2] == ["Popcorn", "Beverages"] and len(names) == 6 , names;
        # A product with variants.
        page.click('nav[aria-label="Snacks"] a:has-text("Products")');
        page.click('[data-testid="add-product"]');
        # Templates come first (P12.5); this starts blank.
        page.click('[data-testid="template-blank"]');
        page.wait_for_selector('[data-testid="snack-editor"]');
        _type(page, "#p-name", "Popcorn");
        page.select_option("#p-category_id", label="Popcorn");
        # Steps (improvements #9): Details, Images, then Variants & pricing.
        page.click('[data-testid="step-next"]');
        page.click('[data-testid="step-next"]');
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

test "a new product adds a category on the spot and takes an image before saving" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"], owner["slug"], "/new?template=blank");
        page.wait_for_selector('[data-testid="snack-editor"]');
        _type(page, "#p-name", "Samosa");
        # No categories yet: the new-category field is already open.
        _type(page, "#new-category-name", "Hot food");
        page.click('[data-testid="add-category"]');
        _said(page, "editor-message", "Added the Hot food category");
        assert page.locator("#p-category_id option:checked").inner_text() == "Hot food";
        page.click('[data-testid="step-next"]');
        out = io.BytesIO();
        Image.new("RGB", (300, 300), "#C8102E").save(out, format="PNG");
        page.set_input_files(
            '[data-testid="product-image-file"]',
            files=[
                {
                    "name": "samosa.png",
                    "mimeType": "image/png",
                    "buffer": out.getvalue()
                }
            ]
        );
        _said(page, "editor-message", "uploaded when you save");
        page.click('[data-testid="save-product"]');
        page.wait_for_url(
            lambda (url: str) -> bool { return not url.endswith("/new"); }
        );
        _said(page, "editor-message", "Saved");
        product = page.url.split("/")[-1].split("?")[0];
        got = call(
            owner["token"],
            "get_snack_product",
            {"tenant": owner["slug"], "product_id": product}
        )["product"];
        assert len(got["images"]) == 1 , got["images"];
        assert page.locator('[data-testid="step-images"][aria-current="step"]').count()
            == 1;
        # Fill in SKUs makes one from the name.
        page.click('[data-testid="step-pricing"]');
        page.click('[data-testid="fill-skus"]');
        assert page.input_value("#p-variants-0-sku") == "SAMOSA";
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
        page.locator('[data-testid="step-pricing"]').tap();
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
                page.click('[data-testid="step-pricing"]');
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

test "every snack page fits a phone, with no sideways scroll" {
    owner = owner_with_cinema();
    add_venue(owner);
    product = _stocked(owner);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_in(page, owner["email"], owner["slug"]);
        page.wait_for_selector('[data-testid="product-row"]');
        for (rest, ready) in [
            ("", '[data-testid="product-row"]'),
            (f"/{product}", '[data-testid="snack-editor"]'),
            ("/categories", '[data-testid="category-row"]'),
            ("/extras", '[data-testid="snack-extras"]'),
            ("/stock", '[data-testid="snack-stock"]'),
            ("/import", '[data-testid="snack-import"]')
        ] {
            page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks{rest}");
            page.wait_for_selector(ready);
            wide = page.evaluate(
                "document.documentElement.scrollWidth - document.documentElement.clientWidth"
            );
            assert wide <= 1 , f"/snacks{rest} is {wide}px wider than the phone";
        }
        # Every editor step fits too, and keeps Save and Publish in reach.
        page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks/{product}");
        page.wait_for_selector('[data-testid="save-bar"]');
        for key in ["details", "images", "pricing", "more"] {
            page.locator(f'[data-testid="step-{key}"]').tap();
            wide = page.evaluate(
                "document.documentElement.scrollWidth - document.documentElement.clientWidth"
            );
            assert wide <= 1 , f"the {key} step is {wide}px wider than the phone";
            assert page.locator('[data-testid="save-product"]').is_visible();
        }
    } finally {
        close_contexts(browser);
    }
}
