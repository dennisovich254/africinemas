"""P12.14: add snacks from My tickets and by reference at the counter.
Runs on phone and desktop in CI; review screenshots cover 375/768/1440 in both themes.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call, unique, email_for, PASSWORD }
import from e2e.support.snacks { with_snacks }

def _booking(owner: dict[str, str]) -> dict[str, any] {  # jac:ignore[W1037]
    holder = unique("holder") + "-0123456789abcdef";
    where = {"slug": owner["slug"], "screening_id": owner["show"], "holder": holder};
    menu = call(
        "", "public_snacks", {"slug": owner["slug"], "screening_id": owner["show"]}
    );
    variant = menu["categories"][0]["products"][0]["variants"][0]["variant_id"];
    assert call("", "hold_seats", {** where, "labels": ["A1"]})["ok"];
    placed = call(
        "",
        "place_order",
        {
            ** where,
            "idempotency_key": unique("order") + "-0123456789abcdef",
            "items": [{"seat_label": "A1", "ticket_type": "ADULT"}],
            "snacks": [{"variant_id": variant, "quantity": 1}]
        }
    );
    assert placed["ok"] , placed;
    sold = call(
        owner["token"],
        "sell_for_cash",
        {
            "tenant": owner["slug"],
            "screening_id": owner["show"],
            "holder": holder,
            "email": ""
        }
    );
    assert sold["ok"] , sold;
    token = sold["payment"]["link"].split("/")[-1];
    view = call("", "tickets_by_link", {"slug": owner["slug"], "token": token});
    assert view["ok"] , view;
    return {
        "link": sold["payment"]["link"],
        "reference": view["booking"]["reference"],
        "pickup": view["booking"]["pickup"]["reference"]
    };
}

def _add(page: any) {  # jac:ignore[W1037]
    page.locator('[data-testid="snack-product"]').first.click();
    page.click('[data-testid="snack-add"]');
    page.wait_for_selector('[data-testid="snack-sale-pay"]:not([disabled])');
    assert page.inner_text('[data-testid="snack-sale-total"]') == "KES 200";
    page.click('[data-testid="snack-sale-pay"]');
    page.wait_for_selector('[data-testid="snack-sale-payment"]');
    assert page.inner_text('[data-testid="snack-sale-amount"]') == "KES 200";
}

test "My tickets adds snacks with another M-Pesa payment and the same pickup" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = with_snacks(90);
            booking = _booking(owner);
            page = browser.new_context(
                **context_options(pw, project, "light"), reduced_motion="reduce"
            ).new_page();
            page.goto(f"{BASE_URL}/c/{owner['slug']}/sign-up?next={booking['link']}");
            page.wait_for_selector('[data-testid="customer-sign-up"]');
            email = email_for(unique("snack-buyer"));
            page.fill("#name", "Snack buyer");  # jac:ignore[W6002]
            page.fill("#email", email);  # jac:ignore[W6002]
            page.fill("#password", PASSWORD);  # jac:ignore[W6002]
            page.check('[data-testid="customer-sign-up"] #adult');  # "I'm 18 or over" (P15.0)
            page.click('[data-testid="customer-sign-up"] button[type="submit"]');
            page.wait_for_selector('[data-testid="saved-to-account"]');
            page.goto(f"{BASE_URL}/c/{owner['slug']}/my-tickets");
            page.click('[data-testid="saved-add-snacks"]');
            page.wait_for_selector('[data-testid="tickets-page"]');
            page.click('[data-testid="add-more-snacks"]');
            page.wait_for_selector('[data-testid="snack-grid"]');
            if project == "desktop" {
                for scheme in ["light", "dark"] {
                    page.emulate_media(color_scheme=scheme);
                    for width in [375, 768, 1440] {
                        page.set_viewport_size({"width": width, "height": 900});
                        assert page.evaluate(
                            "document.documentElement.scrollWidth <= innerWidth"
                        );
                        targets = page.locator(
                            '[data-testid="more-snacks"] button:visible'
                        );
                        for i in range(targets.count()) {
                            box = targets.nth(i).bounding_box();
                            assert box["height"] >= 44 and box["width"] >= 44 , box;
                        }
                        page.screenshot(
                            path=artifact(f"more-snacks-{width}-{scheme}.png"),
                            full_page=True
                        );
                    }
                }
            }
            _add(page);
            assert page.locator('[data-testid="snack-sale-cash"]').count() == 0;
            page.fill("#extra-snack-email", email);  # jac:ignore[W6002]
            page.fill("#snack-sale-phone", "0712 345 678");  # jac:ignore[W6002]
            page.get_by_role("button", name="Send M-Pesa prompt").click();
            page.wait_for_selector('[data-testid="snack-sale-done"]', timeout=30000);
            assert page.inner_text('[data-testid="snack-sale-code"]').strip()
                == booking["pickup"];
            page.reload();
            page.wait_for_selector('[data-testid="tickets-page"]');
            assert page.locator('[data-testid="ticket"]').count() == 1;
            assert page.inner_text('[data-testid="pickup-reference"]').strip()
                == booking["pickup"];
            assert page.locator('[data-testid="booked-snacks"] li').count() == 2;
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "box office finds the booking and adds snacks for cash" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = with_snacks(90);
            booking = _booking(owner);
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(BASE_URL + "/login");
            page.fill("#email", owner["email"]);  # jac:ignore[W6002]
            page.fill("#password", PASSWORD);  # jac:ignore[W6002]
            page.click('button[type="submit"]');
            page.wait_for_url("**/app");
            page.goto(f"{BASE_URL}/app/{owner['slug']}/box-office");
            page.click('[data-testid="sale-kind-extra"]');
            page.fill("#extra-booking-reference", booking["reference"]);  # jac:ignore[W6002]
            page.get_by_role("button", name="Find booking").click();
            page.wait_for_selector('[data-testid="snack-grid"]');
            _add(page);
            page.click('[data-testid="snack-sale-cash"]');
            page.click('[data-testid="snack-sale-confirm-cash"]');
            page.wait_for_selector('[data-testid="snack-sale-done"]');
            assert page.inner_text('[data-testid="snack-sale-code"]').strip()
                == booking["pickup"];
            page.click('[data-testid="snack-sale-hand-over"]');
            page.wait_for_selector('[data-testid="snack-sale-handed"]');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
