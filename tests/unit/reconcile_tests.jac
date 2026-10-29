"""P15.6: a cash count, and the words for each exception (ADR-0085).

- A count shows its difference: short below zero, over above.
- Every kind of exception has words; the statement's kinds are gone (2026-10-29).
"""

import from core.payments.reconcile { CashUp, cash_up_view, LABELS }

test "a cash count shows how far it's off, and every exception has words" {
    def count(counted: int, expected: int) -> dict[str, any] {  # jac:ignore[W1037]
        return cash_up_view(
            CashUp(
                tenant_id="t",
                member_id="m",
                member="agent@example.com",
                counted_cents=counted,
                expected_cents=expected,
                since="",
                at="2026-10-29T10:00:00+00:00"
            )
        );
    }
    assert count(160000, 166000)["difference_cents"] == -6000;
    assert count(100000, 83000)["difference_cents"] == 17000;
    assert count(0, 0)["difference_cents"] == 0;
    assert count(5, 5)["member"] == "agent@example.com";
    for kind in [
        "not_paid",
        "no_order",
        "amount_differs",
        "receipt_twice",
        "cash_short",
        "cash_over",
        "cash_not_counted"
    ] {
        assert LABELS[kind] , kind;
    }
    assert sorted(LABELS.keys())
        == sorted(
            [
                "not_paid",
                "no_order",
                "amount_differs",
                "receipt_twice",
                "cash_short",
                "cash_over",
                "cash_not_counted"
            ]
        );
}
