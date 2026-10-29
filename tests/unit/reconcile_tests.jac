"""P15.6: reading an M-Pesa statement, and a cash count (ADR-0085).

- Columns are found by name, whatever their case, dots or slashes, and in any order;
  a missing one is -1.
- Completion times are read in the forms Safaricom's portal and spreadsheets write.
- A count shows its difference: short below zero, over above.
"""

import from datetime { datetime }
import from core.payments.reconcile { column_of, time_of, CashUp, cash_up_view, LABELS }

test "a statement's columns are found by name, in any order" {
    header = [
        "Receipt No.",
        "Completion Time",
        "Details",
        "Paid In",
        "A/C No.",
        "Transaction Status"
    ];
    assert column_of(header, ["receipt no", "receipt"]) == 0;
    assert column_of(header, ["completion time"]) == 1;
    assert column_of(header, ["paid in"]) == 3;
    assert column_of(header, ["ac no", "account no"]) == 4;
    assert column_of(header, ["transaction status", "status"]) == 5;
    assert column_of(["  RECEIPT  ", "paid in"], ["receipt"]) == 0;
    assert column_of(header, ["withdrawn"]) == -1;
}

test "completion times are read in the portal's and spreadsheets' forms" {
    want = datetime(2026, 10, 29, 14, 3, 22);
    for text in [
        "2026-10-29 14:03:22",
        "29-10-2026 14:03:22",
        "29/10/2026 14:03:22",
        "2026-10-29T14:03:22",
        " 2026-10-29 14:03:22.000 "
    ] {
        assert time_of(text) == want , text;
    }
    assert time_of("yesterday") is None;
    assert time_of("") is None;
}

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
        "not_in_app",
        "not_in_statement",
        "cash_short",
        "cash_over"
    ] {
        assert LABELS[kind] , kind;
    }
}
