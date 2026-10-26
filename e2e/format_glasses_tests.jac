"""P12.13 E2E: glasses are offered per ticket for 3D, explicitly unchecked."""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    context_options,
    artifact
}
import from e2e.support.api { call }
import from e2e.support.catalog { cinema_selling_tickets }

test "3D checkout starts with bring-your-own and can add glasses per ticket" {
    (pw, browser) = shared_browser();
    try {
        for (project, width) in [("mobile", 375), ("tablet", 768), ("desktop", 1440)] {
            owner = cinema_selling_tickets();
            movie = call(owner["token"], "list_movies", {"tenant": owner["slug"]})[
                "movies"
            ][0];
            assert call(
                owner["token"],
                "update_movie",
                {
                    "tenant": owner["slug"],
                    "movie_id": movie["movie_id"],
                    "title": movie["title"],
                    "synopsis": movie["synopsis"],
                    "runtime_minutes": movie["runtime_minutes"],
                    "age_rating": movie["age_rating"],
                    "genres": movie["genres"],
                    "language": movie["language"],
                    "release_date": movie["release_date"],
                    "format": "3D"
                }
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
                **context_options(
                    pw, "mobile" if project == "mobile" else "desktop", "light"
                )
            ).new_page();
            if width == 768 {
                page.set_viewport_size({"width": width, "height": 900});
            }
            page.goto(f"{BASE_URL}/c/{owner['slug']}");
            links = page.locator(
                f'[data-testid="showtime"][href$="/s/{owner["show"]}"]'
            );
            links.first.wait_for(state="visible");
            assert "3D" in links.first.inner_text();
            assert call(
                owner["token"],
                "set_screening_format",
                {"tenant": owner["slug"], "screening_id": owner["show"], "format": "2D"}
            )["ok"];
            page.reload();
            links.first.wait_for(state="visible");
            assert "2D" in links.first.inner_text();
            assert call(
                owner["token"],
                "set_screening_format",
                {"tenant": owner["slug"], "screening_id": owner["show"], "format": "3D"}
            )["ok"];
            page.reload();
            links.first.wait_for(state="visible");
            assert "3D" in links.first.inner_text();
            page.goto(f"{BASE_URL}/c/{owner['slug']}/s/{owner['show']}");
            seat = page.locator('[data-testid="seat"][data-seat="A1"]');
            seat.tap() if project == "mobile" else seat.click();
            page.locator('[data-testid="hold-seats"]').click();
            page.wait_for_selector('[data-testid="glasses-choice"]');
            choice = page.locator('[data-testid="glasses-choice"] input');
            assert not choice.is_checked();
            assert choice.locator("xpath=..").bounding_box()["height"] >= 44;
            assert "I'll bring my own"
                in page.inner_text('[data-testid="glasses-choice"]');
            choice.check();
            assert "KES 950" == page.inner_text('[data-testid="checkout-total"]');
            assert page.evaluate(
                "document.documentElement.scrollWidth - document.documentElement.clientWidth"
            )
                <= 1 , f"{width}px checkout scrolls sideways";
            page.screenshot(path=artifact(f"3d-glasses-{project}.png"), full_page=True);
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
