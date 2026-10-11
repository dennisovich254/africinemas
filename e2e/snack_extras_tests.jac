"""P12.3 E2E: add-ons and combos in the back office (design guide §5).

An owner opens Combos & Add-ons and makes "Popcorn extras" (butter +30, caramel +50,
optional, up to 2), a wrong price caught beside its field; then gives it to Popcorn in
the product editor. They open the Movie Night Combo, tick Large Popcorn as its first
item and Coke and Fanta as the drinks (2 of them), save, and publish it. A box office
agent marks caramel unavailable at their venue (the switch says so, pressed).
Screenshots of the page and the combo editor on mobile and desktop, light and dark.
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

def _sign_in(page: any, email: str, slug: str, rest: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
    page.goto(f"{BASE_URL}/app/{slug}/snacks/{rest}");
}

def _said(page: any, testid: str, words: str) {  # jac:ignore[W1037]
    page.wait_for_function(
        f"(document.querySelector('[data-testid={testid}]')?.innerText || '').includes({repr(
            words
        )})"
    );
}

def _menu(owner: dict[str, str]) -> dict[str, str] {
    # Through the API: Popcorn (Small, Large), Coke, Fanta and an empty combo.
    def made(name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
        got = call(owner["token"], name, {"tenant": owner["slug"], ** args});
        assert got["ok"] , (name, got);
        return got;
    }
    kinds = {
        c["name"]: c["category_id"]
        for c in made("add_default_snack_categories", {})["categories"]
    };
    def product(
        name: str, kind_name: str, kind: str, rows: list[tuple[list[str], str, int]]
    ) -> str {
        return made(
            "save_snack_product",
            {
                "product_id": "",
                "name": name,
                "brand": "",
                "description": "",
                "tags": [],
                "category_id": kinds[kind_name],
                "kind": kind,
                "option_names": ["Size"] if kind == "variants" else [],
                "variants": [
                    {
                        "variant_id": "",
                        "option_values": values,
                        "sku": sku,
                        "barcode": "",
                        "price_cents": price,
                        "available": True,
                        "track_stock": False
                    } for (values, sku, price) in rows
                ]
            }
        )["product"]["product_id"];
    }
    return {
        "popcorn": product(
            "Popcorn",
            "Popcorn",
            "variants",
            [(["Small"], "POP-SM", 20000), (["Large"], "POP-LG", 40000)]
        ),
        "coke": product(
            "Coca-Cola 500 ml", "Beverages", "single", [([], "COKE-500", 15000)]
        ),
        "fanta": product(
            "Fanta 500 ml", "Beverages", "single", [([], "FANTA-500", 15000)]
        ),
        "combo": product(
            "Movie Night Combo", "Combos & Deals", "combo", [([], "COMBO-MN", 70000)]
        )
    };
}

test "an owner makes add-ons, gives them to a product, and builds a combo" {
    owner = owner_with_cinema();
    add_venue(owner);
    menu = _menu(owner);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"], owner["slug"], "extras");
        page.click('button:has-text("Add an add-on group")');
        _type(page, "#p-group-name", "Popcorn extras");
        _type(page, "#p-group-label", "Choose your extras");
        _type(page, "#p-group-max_picks", "2");
        _type(page, "#p-group-options-0-name", "Extra butter");
        _type(page, "#p-group-options-0-price_cents", "thirty");
        page.click('button:has-text("Add an add-on")');
        _type(page, "#p-group-options-1-name", "Caramel");
        _type(page, "#p-group-options-1-price_cents", "50");
        page.click('[data-testid="edit-addon-group"] button[type="submit"]');
        page.wait_for_selector("#p-group-options-0-price_cents-error");
        _type(page, "#p-group-options-0-price_cents", "30");
        page.click('[data-testid="edit-addon-group"] button[type="submit"]');
        _said(page, "extras-message", "Saved Popcorn extras");
        assert "+KES 30" in page.inner_text('[data-testid="addon-group"]');
        # Popcorn offers them.
        page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks/{menu['popcorn']}");
        page.locator(
            '[data-testid="product-addons"] label', has_text="Popcorn extras"
        ).locator(
            "input"
        ).check();
        page.click('button:has-text("Save add-ons")');
        page.wait_for_selector("text=Saved the add-ons.");
        # The combo: Large Popcorn, and two drinks chosen from Coke and Fanta.
        page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks/{menu['combo']}");
        page.wait_for_selector('[data-testid="combo-components"]');
        _type(page, "#p-components-0-label", "Popcorn");
        first = page.locator('[data-testid="combo-component"]').nth(0);
        first.locator("label", has_text="Popcorn · Large").locator("input").check();
        page.click('button:has-text("Add an item")');
        _type(page, "#p-components-1-label", "Drinks");
        _type(page, "#p-components-1-quantity", "2");
        second = page.locator('[data-testid="combo-component"]').nth(1);
        second.locator("label", has_text="Coca-Cola 500 ml").locator("input").check();
        second.locator("label", has_text="Fanta 500 ml").locator("input").check();
        page.click('button:has-text("Save what it includes")');
        _said(page, "components-message", "Saved what the combo includes");
        page.click('[data-testid="publish"]');
        _said(page, "editor-message", "Published");
    } finally {
        close_contexts(browser);
    }
}

test "the box office marks an add-on unavailable at their venue" {
    owner = owner_with_cinema();
    venue = add_venue(owner);
    call(
        owner["token"],
        "save_snack_addon_group",
        {
            "tenant": owner["slug"],
            "group_id": "",
            "name": "Popcorn extras",
            "label": "Choose your extras",
            "min_picks": 0,
            "max_picks": 2,
            "repeatable": False,
            "options": [
                {"name": "Extra butter", "price_cents": 3000},
                {"name": "Caramel", "price_cents": 5000}
            ]
        }
    );
    agent = add_staff(owner, "box_office_agent", venue);
    call(agent["token"], "start_shift", {"tenant": owner["slug"]});
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_in(page, agent["email"], owner["slug"], "extras");
        toggle = page.locator('[data-testid="addon"]', has_text="Caramel").locator(
            '[data-testid="addon-unavailable-switch"]'
        );
        toggle.tap();
        _said(page, "extras-message", "Caramel is unavailable");
        assert page.locator('[data-testid="addon"]', has_text="Caramel").locator(
            '[data-testid="addon-unavailable-switch"]'
        ).get_attribute(
            "aria-pressed"
        )
            == "true";
        assert page.locator('button:has-text("Add an add-on group")').count() == 0;
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of combos and add-ons" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = owner_with_cinema();
                add_venue(owner);
                menu = _menu(owner);
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _sign_in(page, owner["email"], owner["slug"], "extras");
                page.wait_for_selector('[data-testid="snack-extras"]');
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"snack-extras-{project}-{scheme}.png"),
                    full_page=True
                );
                page.goto(f"{BASE_URL}/app/{owner['slug']}/snacks/{menu['combo']}");
                page.wait_for_selector('[data-testid="combo-components"]');
                page.screenshot(
                    path=artifact(f"snack-combo-{project}-{scheme}.png"), full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
