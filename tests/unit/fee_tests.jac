"""P15.2: the fee on one order, by channel and category (core/payments/fees.jac).

The cinema agreement's worked example, scaled: two tickets at KES 600 (one with 3D
glasses at KES 300) and a KES 300 popcorn. Online: 7% of the tickets and the glasses,
20% of the snacks. At the box office: 3% of everything. A cinema's own rates replace the
standard's, a channel's "*" covers the categories a version doesn't name, and a flat fee
per item is added to the percentage.
"""

import from core.booking.models { Order }
import from core.payments.fees { compute_fee }
import from core.legal.fee_rule { rates_from, rate_of }

def _order -> Order {
    return Order(
        tenant_id="t",
        screening_id="s",
        holder="h",
        hold_id="",
        idempotency_key="k",
        reference="R",
        lines=[{"total_cents": 60000}, {"total_cents": 60000}],
        snack_lines=[
            {"purpose": "3d_glasses", "line_cents": 30000, "quantity": 1},
            {"line_cents": 30000, "quantity": 1}
        ],
        total_cents=180000
    );
}

def _rule(rates: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "scope": "platform",
        "version": 1,
        "applies_from": "2026-10-26",
        "rates": rates
    };
}

test "online: 7% of tickets and glasses, 20% of snacks; box office: 3% of everything" {
    standard = _rule(rates_from(700, 2000, 300));
    online = compute_fee(_order(), "online", standard);
    assert {p["category"]: p["fee_cents"] for p in online["parts"]}
        == {"tickets": 8400, "glasses": 2100, "snacks": 6000} , online;
    assert online["fee_cents"] == 16500 and online["channel"] == "online";
    counter = compute_fee(_order(), "counter", standard);
    assert counter["fee_cents"] == 5400 , counter;
    assert {p["bp"] for p in counter["parts"]} == {300};
}

test "rates: a channel's * covers unnamed categories, and per-item amounts add up" {
    rates = {
        "online:tickets": {"bp": 500, "per_unit_cents": 2000},
        "online:*": {"bp": 1000, "per_unit_cents": 0}
    };
    assert rate_of(rates, "online", "snacks") == {"bp": 1000, "per_unit_cents": 0};
    assert rate_of(rates, "counter", "tickets") == {"bp": 0, "per_unit_cents": 0};
    found = compute_fee(_order(), "online", _rule(rates));
    # Tickets: 5% of 120000 plus KES 20 a ticket; glasses and snacks: 10%.
    assert {p["category"]: p["fee_cents"] for p in found["parts"]}
        == {"tickets": 10000, "glasses": 3000, "snacks": 3000} , found;
}

test "rounding is half up, to the cent" {
    order = _order();
    order.lines = [{"total_cents": 150}];
    order.snack_lines = [];
    # 7% of 150 cents is 10.5 cents: 11.
    assert compute_fee(order, "online", _rule(rates_from(700, 2000, 300)))["fee_cents"]
        == 11;
}
