"""P12.8 E2E: "Add snacks" on the storefront, between the tickets and paying.

A cinema selling tickets (Adult KES 800 + KES 30 fee) sells Popcorn (Small KES 200,
Large KES 400, with Butter for KES 30) and Coca-Cola, which tracks stock and has none,
so it isn't offered. A visitor holds A1, continues to the snack step, opens Popcorn,
picks Large with Butter and adds it: the cart says so and the total is KES 1,260. They
pay with M-Pesa for KES 1,260 and "You're booked" lists the popcorn. Another skips the
step: the order is the ticket alone. Phone and desktop; screenshots for review.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call }
import from e2e.support.catalog { cinema_selling_tickets }

glob SETTLE_MS: int = 30000;

def _made(owner: dict[str, str], name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
    got = call(owner["token"], name, {"tenant": owner["slug"], ** args});
    assert got["ok"] , (name, got);
    return got;
}

def _row(values: list[str], price: int, tracked: bool = False) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "variant_id": "",
        "option_values": values,
        "sku": "",
        "barcode": "",
        "price_cents": price,
        "available": True,
        "track_stock": tracked
    };
}

def _product(
    owner: dict[str, str],
    name: str,
    category: str,
    kind: str,
    rows: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    made = _made(
        owner,
        "save_snack_product",
        {
            "product_id": "",
            "name": name,
            "brand": "",
            "description": "",
            "tags": [],
            "category_id": category,
            "kind": kind,
            "option_names": ["Size"] if kind == "variants" else [],
            "variants": rows
        }
    )["product"];
    _made(owner, "publish_snack_product", {"product_id": made["product_id"]});
    return made;
}

def _with_snacks -> dict[str, str] {
    owner = cinema_selling_tickets();
    kinds = {
        c["name"]: c["category_id"]
        for c in _made(owner, "add_default_snack_categories", {})["categories"]
    };
    popcorn = _product(
        owner,
        "Popcorn",
        kinds["Popcorn"],
        "variants",
        [_row(["Small"], 20000), _row(["Large"], 40000)]
    );
    _product(owner, "Coca-Cola", kinds["Beverages"], "single", [_row([], 15000, True)]);
    group = _made(
        owner,
        "save_snack_addon_group",
        {
            "group_id": "",
            "name": "Popcorn extras",
            "label": "Extras",
            "min_picks": 0,
            "max_picks": 2,
            "repeatable": False,
            "options": [{"name": "Butter", "price_cents": 3000}]
        }
    )["group"];
    _made(
        owner,
        "set_snack_product_addons",
        {"product_id": popcorn["product_id"], "group_ids": [group["group_id"]]}
    );
    return owner;
}

def _press(page: any, project: str, selector: str) {  # jac:ignore[W1037]
    if project == "mobile" {
        page.locator(selector).first.tap();
    } else {
        page.locator(selector).first.click();
    }
}

def _total(page: any, text: str) {  # jac:ignore[W1037]
    page.wait_for_function(
        f"document.querySelector('[data-testid=checkout-total]')?.innerText === {repr(
            text
        )}"
    );
}

def _to_snacks(page: any, project: str, owner: dict[str, str], seat: str) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/c/{owner['slug']}/s/{owner['show']}");
    page.wait_for_selector(f'[data-testid="seat"][data-seat="{seat}"]');
    _press(page, project, f'[data-testid="seat"][data-seat="{seat}"]');
    _press(page, project, '[data-testid="hold-seats"]');
    _total(page, "KES 830");
    page.wait_for_selector('[data-testid="pay"]:has-text("Continue"):not([disabled])');
    _press(page, project, '[data-testid="pay"]');
    page.wait_for_selector('[data-testid="snack-step"]');
}

test "a visitor adds popcorn with butter, pays for it all, and sees it booked" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = _with_snacks();
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _to_snacks(page, project, owner, "A1");
            # Coca-Cola has no stock, so Beverages isn't offered.
            chips = page.locator('[data-testid="snack-category"]').all_inner_texts();
            assert chips == ["Popcorn"] , chips;
            _press(page, project, '[data-testid="snack-product"]:has-text("Popcorn")');
            page.wait_for_selector('[data-testid="snack-sheet"]');
            _press(page, project, '[data-testid="snack-variant"]:has-text("Large")');
            page.locator('[data-testid="snack-addon"]').first.check();
            assert "KES 430" in page.inner_text('[data-testid="snack-add"]');
            _press(page, project, '[data-testid="snack-add"]');
            page.wait_for_selector(
                '[data-testid="snack-cart"]:has-text("Popcorn · Large")'
            );
            assert "Butter" in page.inner_text('[data-testid="snack-cart"]');
            _total(page, "KES 1,260");
            _press(page, project, '[data-testid="snacks-continue"]');
            page.wait_for_selector('[data-testid="pay-panel"]');
            assert "1 × Popcorn · Large"
                in page.inner_text('[data-testid="order-snack"]');
            assert "KES 1,260" in page.inner_text('[data-testid="order-total"]');
            page.fill("#mpesa-phone", "0712 345 678");  # jac:ignore[W6002]
            page.fill("#tickets-email", "anna@example.com");  # jac:ignore[W6002]
            _press(page, project, '[data-testid="pay-mpesa"]');
            page.wait_for_selector('[data-testid="booked"]', timeout=SETTLE_MS);
            assert "Popcorn · Large"
                in page.inner_text('[data-testid="booked-snacks"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "skipping the snacks orders the ticket alone" {
    (pw, browser) = shared_browser();
    try {
        owner = _with_snacks();
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _to_snacks(page, "mobile", owner, "A2");
        skipper = page.locator('[data-testid="skip-snacks"]');
        go_on = page.locator('[data-testid="snacks-continue"]');
        assert skipper.is_visible() and go_on.is_visible();
        assert skipper.bounding_box()["height"] == go_on.bounding_box()["height"];
        skipper.tap();
        page.wait_for_selector('[data-testid="pay-panel"]');
        assert page.locator('[data-testid="order-snack"]').count() == 0;
        assert "KES 830" in page.inner_text('[data-testid="order-total"]');
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the snack step" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = _with_snacks();
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _to_snacks(page, project, owner, "A3");
                page.screenshot(
                    path=artifact(f"snack-step-{project}-{scheme}.png"), full_page=True
                );
                _press(page, project, '[data-testid="snack-product"]');
                page.wait_for_selector('[data-testid="snack-sheet"]');
                page.screenshot(path=artifact(f"snack-sheet-{project}-{scheme}.png"));
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
