"""The storefront's snack menu (P12.6; ADR-0051): public, no login, like the rest of a
cinema's storefront (scope "storefront" in tests/isolation/registry.jac).

- public_snacks(slug, screening_id): the menu at the showtime's venue (menu_of), for a
  showtime on the storefront that hasn't started.
- price_snacks(slug, screening_id, lines): a cart's lines priced there (price_cart),
  with the total; a cart with problems is refused (snacks_unavailable) with every one.
- public_snack_image(slug, product_id, image_id): an active product's image.

An unknown cinema, showtime, product or image is not_found. Prices come only from the
server; nothing here changes anything.
"""

import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.responses { NOT_FOUND }
import from core.catalog.storefront { upcoming }
import from core.catalog.venues { find_screening }
import from core.catalog.answers { Refused }
import from core.snacks.store { find_product, image_answer }
import from core.snacks.menu { menu_of, price_cart }

def showing_venue(cinema: Tenant, screening_id: str) -> str {
    # The venue of a showtime on the storefront that hasn't started; "" for any other.
    if not screening_id
        or not any(e.screening_id == screening_id for e in upcoming(cinema)) {
        return "";
    }
    screening = find_screening(cinema, screening_id);
    return screening.venue_id if screening is not None else "";
}

def:pub public_snacks(slug: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    venue_id = showing_venue(cinema, screening_id);
    if not venue_id {
        return NOT_FOUND;
    }
    return {"ok": True, "categories": menu_of(cinema, venue_id)};
}

def:pub price_snacks(
    slug: str,
    screening_id: str,
    lines: list[dict[str, any]]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    venue_id = showing_venue(cinema, screening_id);
    if not venue_id {
        return NOT_FOUND;
    }
    (priced, total, problems) = price_cart(cinema, venue_id, lines);
    if problems {
        return {
            "ok": False,
            "error": {
                "code": "snacks_unavailable",
                "message": problems[0]["message"],
                "problems": problems
            }
        };
    }
    return {"ok": True, "lines": priced, "total_cents": total};
}

def:pub public_snack_image(
    slug: str, product_id: str, image_id: str
) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    product = find_product(cinema, product_id);
    if product is None or product.status != "active" {
        return NOT_FOUND;
    }
    found = [
        i
        for i in product.images
        if i["image_id"] == image_id
    ];
    if not found {
        return NOT_FOUND;
    }
    try {
        return image_answer(found[0]["key"]);
    } except Refused {
        return NOT_FOUND;
    }
}
