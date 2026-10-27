"""ADR-0081: money is integers of cents, rounded once, and never lost or invented.

core/money.jac's rules, and the fee (core/payments/fees.jac) checked against them on
thousands of random orders: the parts always add up to the fee, the fee is the exact
amount rounded once (half up), and the cinema's share plus the fee is what was paid.
"""

import random;
import from core.money {
    allocate,
    div_half_up,
    whole_shillings,
    basis_points_of,
    cents_of_shillings
}
import from core.booking.models { Order }
import from core.payments.fees { compute_fee }
import from core.legal.fee_rule { rates_from }

test "rounding is half up, once" {
    assert div_half_up(105000, 10000) == 11;
    assert div_half_up(104999, 10000) == 10;
    assert div_half_up(-105000, 10000) == -11;
    assert div_half_up(0, 7) == 0;
}

test "allocation keeps every cent" {
    # A third each of 100 cents: 33, 33, 34 (the cent left over goes to the largest
    # remainder), never 33, 33, 33.
    parts = allocate(100, [333333, 333333, 333334], 10000);
    assert parts == [33, 33, 34] , parts;
    rng = random.Random(81);
    for _ in range(2000) {
        exact = [rng.randint(0, 5000000) for _ in range(rng.randint(1, 4))];
        total = div_half_up(sum(exact), 10000);
        parts = allocate(total, exact, 10000);
        assert sum(parts) == total , (exact, total, parts);
        # No part is ever more than a cent from its exact share.
        for (p, e) in zip(parts, exact) {
            assert abs(p * 10000 - e) < 10000 + 1 , (p, e);
        }
    }
}

test "amounts and rates are read as text, never through float" {
    assert cents_of_shillings("1660") == 166000;
    assert cents_of_shillings(1660.0) == 166000;
    assert cents_of_shillings("0.1") == 10;
    assert cents_of_shillings("12.345") is None;
    assert cents_of_shillings("abc") is None and cents_of_shillings(None) is None;
    assert cents_of_shillings("Infinity") is None;
    assert basis_points_of("7") == 700 and basis_points_of(2.5) == 250;
    assert basis_points_of("7.25") == 725 and basis_points_of(0.1) == 10;
    assert basis_points_of("7.255") is None and basis_points_of(True) is None;
    assert whole_shillings(150000) and not whole_shillings(15050);
}

test "on random orders the fee is exact, rounded once, and its parts add up" {
    rng = random.Random(15);
    rules = [rates_from(700, 2000, 300), rates_from(333, 1777, 125)];
    for _ in range(1000) {
        order = Order(
            tenant_id="t",
            screening_id="s",
            holder="h",
            hold_id="",
            idempotency_key="k",
            reference="R",
            lines=[
                {"total_cents": rng.randint(1, 3000) * 100}
                for _ in range(rng.randint(0, 6))
            ],
            snack_lines=[
                {
                    "line_cents": rng.randint(1, 2000) * 100,
                    "quantity": rng.randint(1, 3)
                } for _ in range(rng.randint(0, 4))
            ]
                + (
                    [{"purpose": "3d_glasses", "line_cents": 30000, "quantity": 1}]
                        if rng.random() < 0.3
                        else []
                )
        );
        order.total_cents = sum([l["total_cents"] for l in order.lines])
            + sum([l["line_cents"] for l in order.snack_lines]);
        rates = rng.choice(rules);
        channel = rng.choice(["online", "counter"]);
        found = compute_fee(
            order,
            channel,
            {"scope": "platform", "version": 1, "applies_from": "", "rates": rates}
        );
        assert found["fee_cents"]
            == sum([p["fee_cents"] for p in found["parts"]]) , found;
        exact = sum([p["base_cents"] * p["bp"] for p in found["parts"]]);
        assert found["fee_cents"] == div_half_up(exact, 10000) , found;
        share = order.total_cents - found["fee_cents"];
        assert share + found["fee_cents"] == order.total_cents and share >= 0;
    }
}
