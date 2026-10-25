"""P12.13 E2E: glasses are offered per ticket for 3D, explicitly unchecked."""

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

test "3D checkout starts with bring-your-own and can add glasses per ticket" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets();
            movie = call(owner["token"], "list_movies", {"tenant": owner["slug"]})[
                "movies"
            ][0];
            assert call(
                owner["token"],
                "update_movie",
                {"tenant": owner["slug"], ** movie, "format": "3D"}
            )["ok"];
            assert call(
                owner["token"],
                "set_screening_format",
                {"tenant": owner["slug"], "screening_id": owner["show"], "format": "3D"}
            )["ok"];
            glasses = call(
                owner["token"],
                "configure_3d_glasses",
                {
                    "tenant": owner["slug"],
                    "venue_id": owner["venue"],
                    "sold": True,
                    "price_cents": 12000
                }
            )["glasses"];
            assert call(
                owner["token"],
                "adjust_snack_stock",
                {
                    "tenant": owner["slug"],
                    "product_id": glasses["product_id"],
                    "variant_id": glasses["variant_id"],
                    "venue_id": owner["venue"],
                    "reason": "received",
                    "quantity": 10,
                    "note": ""
                }
            )["ok"];
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            page.goto(f"{BASE_URL}/c/{owner['slug']}/s/{owner['show']}");
            seat = page.locator('[data-testid="seat"][data-seat="A1"]');
            seat.tap() if project == "mobile" else seat.click();
            page.locator('[data-testid="hold-seats"]').click();
            page.wait_for_selector('[data-testid="glasses-choice"]');
            choice = page.locator('[data-testid="glasses-choice"] input');
            assert not choice.is_checked();
            assert "I'll bring my own"
                in page.inner_text('[data-testid="glasses-choice"]');
            choice.check();
            assert "KES 950" == page.inner_text('[data-testid="checkout-total"]');
            page.screenshot(path=artifact(f"3d-glasses-{project}.png"), full_page=True);
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
