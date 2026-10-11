"""P12.2: what a venue sells, and at what price (core/snacks/catalog.jac `offer`), as pure logic.

A variant is on sale at a venue when its product is active and on at that venue, and the
variant is available and on there. Its price there is the venue's own price if it has
one, else the variant's price; with neither, it isn't on sale. A venue price is whole
cents from KES 1 to KES 100,000, or none (use the variant's price).
"""

import from core.snacks.catalog { offer, check_venue_price, PRICE_MAX_CENTS }

def _offer(
    status: str = "active",
    product_off: list[str] | None = None,
    available: bool = True,
    variant_off: list[str] | None = None,
    price: int | None = 30000,
    venue_prices: dict[str, int] | None = None,
    venue: str = "westgate"
) -> tuple[bool, int | None] {
    return offer(
        status,
        product_off or [],
        available,
        variant_off or [],
        price,
        venue_prices or {},
        venue
    );
}

test "an active, available variant sells at its own price" {
    assert _offer() == (True, 30000);
}

test "a venue price overrides the variant's price, at that venue only" {
    prices = {"westgate": 35000};
    assert _offer(venue_prices=prices) == (True, 35000);
    assert _offer(venue_prices=prices, venue="junction") == (True, 30000);
    # A venue price sells a variant that has no price of its own.
    assert _offer(price=None, venue_prices=prices) == (True, 35000);
}

test "anything off, or no price, means not on sale here" {
    for (why, got) in [
        ("draft", _offer(status="draft")),
        ("archived", _offer(status="archived")),
        ("product off here", _offer(product_off=["westgate"])),
        ("variant unavailable", _offer(available=False)),
        ("variant off here", _offer(variant_off=["westgate"])),
        ("no price", _offer(price=None))
    ] {
        assert got[0] == False , why;
    }
    # Off elsewhere is still on here.
    assert _offer(product_off=["junction"], variant_off=["junction"]) == (True, 30000);
}

test "a venue price is whole cents in range, or none" {
    assert check_venue_price(None) == (None, "");
    assert check_venue_price(35000) == (35000, "");
    for bad in [0, 99, PRICE_MAX_CENTS + 1, "350", 3.5, True] {
        (price, problem) = check_venue_price(bad);
        assert price is None and problem , bad;
    }
}
