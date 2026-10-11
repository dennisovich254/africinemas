"""P12.4 E2E: the Stock page (design guide §8).

A box office agent at Westgate opens Stock: Coca-Cola 500 ml (tracked) shows 0 and Out.
They record a delivery of 24 (the form previews "after this 24"), then 2 damaged; the
row shows 22 on hand and In stock, and Stock history lists both changes with their
reasons and who made them. They set a low-stock alert at 30: the row shows Low, and
"Low or out only" keeps it. Screenshots on mobile and desktop, light and dark.
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

def _sign_in(page: any, email: str, slug: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
    page.goto(f"{BASE_URL}/app/{slug}/snacks/stock");
    page.wait_for_selector('[data-testid="snack-stock"]');
}

def _said(page: any, words: str) {  # jac:ignore[W1037]
    page.wait_for_function(
        f"(document.querySelector('[data-testid=stock-message]')?.innerText || '').includes({repr(
            words
        )})"
    );
}

def _coke(owner: dict[str, str]) {
    kind = call(
        owner["token"],
        "create_snack_category",
        {"tenant": owner["slug"], "name": "Beverages"}
    )["category"]["category_id"];
    made = call(
        owner["token"],
        "save_snack_product",
        {
            "tenant": owner["slug"],
            "product_id": "",
            "name": "Coca-Cola 500 ml",
            "brand": "Coca-Cola",
            "description": "",
            "tags": [],
            "category_id": kind,
            "kind": "single",
            "option_names": [],
            "variants": [
                {
                    "variant_id": "",
                    "option_values": [],
                    "sku": "COKE-500",
                    "barcode": "",
                    "price_cents": 15000,
                    "available": True,
                    "track_stock": True
                }
            ]
        }
    );
    assert made["ok"] , made;
}

def _adjust(page: any, project: str, reason: str, quantity: str, note: str) {  # jac:ignore[W1037]
    button = page.locator('button[aria-label="Adjust Coca-Cola 500 ml"]');
    if project == "mobile" {
        button.tap();
    } else {
        button.click();
    }
    page.select_option("#stock-reason", reason);
    _type(page, "#stock-quantity", quantity);
    _type(page, "#stock-note", note);
    page.click('[data-testid="adjust-form"] button[type="submit"]');
}

test "the box office records deliveries and damage, and sets a low-stock alert" {
    owner = owner_with_cinema();
    venue = add_venue(owner);
    _coke(owner);
    agent = add_staff(owner, "box_office_agent", venue);
    call(agent["token"], "start_shift", {"tenant": owner["slug"]});
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_in(page, agent["email"], owner["slug"]);
        row = page.locator('[data-testid="stock-row"]', has_text="Coca-Cola 500 ml");
        assert row.locator('[data-testid="stock-status"]').inner_text() == "Out";
        page.locator('button[aria-label="Adjust Coca-Cola 500 ml"]').tap();
        _type(page, "#stock-quantity", "24");
        assert "after this 24" in page.inner_text('[data-testid="stock-preview"]');
        _type(page, "#stock-note", "Delivery");
        page.click('[data-testid="adjust-form"] button[type="submit"]');
        _said(page, "24 on hand");
        _adjust(page, "mobile", "damaged", "2", "Two broken bottles");
        _said(page, "22 on hand");
        assert row.locator('[data-testid="on-hand"]').inner_text() == "22";
        assert row.locator('[data-testid="stock-status"]').inner_text() == "In stock";
        moves = page.locator('[data-testid="movement"]').all_inner_texts();
        assert "Damaged -2" in moves[0] and "Two broken bottles" in moves[0] , moves;
        assert "Received +24" in moves[1] , moves;
        page.locator('button[aria-label="Alerts for Coca-Cola 500 ml"]').tap();
        _type(page, "#stock-low", "30");
        page.click('[data-testid="rules-form"] button[type="submit"]');
        _said(page, "Saved the alert");
        assert row.locator('[data-testid="stock-status"]').inner_text() == "Low";
        page.locator('[data-testid="low-only"]').check();
        assert page.locator('[data-testid="stock-row"]').count() == 1;
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the Stock page" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = owner_with_cinema();
                add_venue(owner);
                _coke(owner);
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _sign_in(page, owner["email"], owner["slug"]);
                _adjust(page, project, "received", "12", "Delivery");
                _said(page, "12 on hand");
                page.locator('button[aria-label="Adjust Coca-Cola 500 ml"]').click();
                page.wait_for_selector('[data-testid="adjust-form"]');
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"snack-stock-{project}-{scheme}.png"), full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
