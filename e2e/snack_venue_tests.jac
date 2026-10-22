"""P12.2 E2E: snack availability and prices per venue, in the product editor.

An owner with two venues opens Popcorn: "At each venue" is a grid of variants by venue
(improvements #9). They untick "Sold here" for Junction (its column greys out), untick
Large's "On sale" at Westgate and give Small its own Westgate price, then save it all
with one "Save venue changes". A box office agent at Westgate sees the same grid: they
can switch On sale, but the price field is read-only for them. Screenshots of the
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

def _cell(page: any, label: str, venue: str, testid: str) -> any {  # jac:ignore[W1037]
    # A variant's On sale box or price field at a venue, found by its label.
    words = "on sale at" if testid == "on-sale" else "Price in KES for";
    return _row(page, label).locator(
        f'[data-testid="{testid}"][aria-label*="{venue}"][aria-label*="{words}" i]'
    );
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
        save = page.locator('[data-testid="save-venues"]');
        assert save.is_disabled() , "nothing to save yet";
        page.locator(
            '[data-testid="sold-at"][aria-label="Sold at Junction"]'
        ).uncheck();
        assert _row(page, "Small").inner_text().count("Not sold here") == 1;
        large = _cell(page, "Large", "Westgate", "on-sale");
        assert large.is_checked();
        large.uncheck();
        small = _cell(page, "Small", "Westgate", "venue-price");
        assert small.get_attribute("placeholder") == "200";
        small.fill("250");  # jac:ignore[W6002]
        assert "Unsaved changes" in page.inner_text('[data-testid="snack-venues"]');
        save.click();
        _said(page, "Saved your venue changes");
        got = call(
            owner["token"],
            "get_snack_product",
            {"tenant": owner["slug"], "product_id": product}
        )["product"];
        westgate = [
            v["venue_id"]
            for v in call(owner["token"], "list_venues", {"tenant": owner["slug"]})[
                "venues"
            ]
            if v["name"] == "Westgate"
        ][0];
        assert len(got["off_at"]) == 1 and westgate not in got["off_at"] , got[
            "off_at"
        ];
        by_size = {v["label"]: v for v in got["variants"]};
        assert westgate in by_size["Large"]["off_at"];
        assert by_size["Small"]["venue_prices"][westgate] == 25000;
        assert save.is_disabled() , "saved, nothing left to save";
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
        assert _cell(page, "Small", "Westgate", "venue-price").is_disabled();
        _cell(page, "Small", "Westgate", "on-sale").tap();
        page.locator('[data-testid="save-venues"]').tap();
        _said(page, "Saved your venue changes");
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
