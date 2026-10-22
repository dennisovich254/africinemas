"""P12.2 E2E: snack availability and prices per venue, in the product editor.

An owner with two venues opens Popcorn: under "At each venue" they stop selling it at
Junction, mark Large unavailable at Westgate (the switch says so, pressed) and give
Small its own Westgate price. A box office agent at Westgate sees the same section: they
can flip availability, but the price field is read-only for them. Screenshots of the
section on mobile and desktop.
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

def _sign_in(page: any, email: str, slug: str, product: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
    page.goto(f"{BASE_URL}/app/{slug}/snacks/{product}");
    page.click('[data-testid="step-more"]');
    page.wait_for_selector('[data-testid="snack-venues"]');
}

def _said(page: any, words: str) {  # jac:ignore[W1037]
    # Waits for the section's announcement to contain `words`; if it never does, fails
    # with what it said instead and every error shown beside a field.
    try {
        page.wait_for_function(
            f"(document.querySelector('[data-testid=venues-message]')?.innerText || '').includes({repr(
                words
            )})"
        );
    } except Exception as e {
        said = page.evaluate(
            "document.querySelector('[data-testid=venues-message]')?.innerText || ''"
        );
        alerts = page.locator('[role="alert"]').all_inner_texts();
        raise AssertionError(
            f"waited for {words!r}; the page said {said!r}; errors: {alerts}"
        ) from e;
    }
}

def _popcorn(owner: dict[str, str]) -> str {
    def made(name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
        got = call(owner["token"], name, {"tenant": owner["slug"], ** args});
        assert got["ok"] , (name, got);
        return got;
    }
    kind = made("create_snack_category", {"name": "Popcorn"})["category"][
        "category_id"
    ];
    return made(
        "save_snack_product",
        {
            "product_id": "",
            "name": "Popcorn",
            "brand": "",
            "description": "",
            "tags": [],
            "category_id": kind,
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
                    ("Large", "POP-LG", 40000)
                ]
            ]
        }
    )["product"]["product_id"];
}

def _row(page: any, label: str) -> any {  # jac:ignore[W1037]
    return page.locator('[data-testid="venue-variant-row"]', has_text=label);
}

test "an owner sets where a product sells, availability and a venue price" {
    owner = owner_with_cinema();
    add_venue(owner, "Westgate");
    add_venue(owner, "Junction");
    product = _popcorn(owner);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        _sign_in(page, owner["email"], owner["slug"], product);
        page.locator('[data-testid="snack-venues"] label', has_text="Junction").locator(
            '[data-testid="sold-at"]'
        ).uncheck();
        page.click('button:has-text("Save venues")');
        _said(page, "Saved where it's sold");
        page.select_option('[data-testid="venue-choice"]', label="Westgate");
        large = _row(page, "Large").locator('[data-testid="venue-unavailable-switch"]');
        assert large.get_attribute("aria-pressed") == "false";
        large.click();
        _said(page, "Large is unavailable at Westgate");
        assert _row(page, "Large").locator(
            '[data-testid="venue-unavailable-switch"]'
        ).get_attribute(
            "aria-pressed"
        )
            == "true";
        _row(page, "Small").locator("input").fill("250");  # jac:ignore[W6002]
        _row(page, "Small").locator('button:has-text("Save")').click();
        _said(page, "Small costs KES 250 at Westgate");
    } finally {
        close_contexts(browser);
    }
}

test "the box office flips availability at their venue, but can't set prices" {
    owner = owner_with_cinema();
    venue = add_venue(owner, "Westgate");
    product = _popcorn(owner);
    agent = add_staff(owner, "box_office_agent", venue);
    call(agent["token"], "start_shift", {"tenant": owner["slug"]});
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_in(page, agent["email"], owner["slug"], product);
        assert page.locator('[data-testid="sold-at"]').count() == 0;
        assert _row(page, "Small").locator("input").is_disabled();
        _row(page, "Small").locator('[data-testid="venue-unavailable-switch"]').tap();
        _said(page, "Small is unavailable at Westgate");
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the venue settings" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = owner_with_cinema();
                add_venue(owner, "Westgate");
                add_venue(owner, "Junction");
                product = _popcorn(owner);
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _sign_in(page, owner["email"], owner["slug"], product);
                page.evaluate("document.fonts.ready");
                page.locator('[data-testid="snack-venues"]').screenshot(
                    path=artifact(f"snack-venues-{project}-{scheme}.png")
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
