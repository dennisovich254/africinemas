"""P4.5: what an order asks for (core/booking/order_api.jac request_lines).

The same order sent again must compare equal whatever its order or spelling, so a
replay under the same idempotency key is recognised; anything else is a new request.
"""

import from core.catalog.answers { Refused }
import from core.booking.order_api { request_lines }

def _code(items: any) -> str {  # jac:ignore[W1037]
    try {
        request_lines(items);
    } except Refused as e {
        return e.code;
    }
    return "";
}

test "the same seats and tickets compare equal in any order and spelling" {
    one = request_lines(
        [
            {"seat_label": "a2", "ticket_type": "child "},
            {"seat_label": "A1", "ticket_type": "ADULT", "total_cents": 1}
        ]
    );
    other = request_lines(
        [
            {"seat_label": "A1", "ticket_type": "adult"},
            {"seat_label": "A2", "ticket_type": "CHILD"}
        ]
    );
    assert one == other == [["A1", "ADULT"], ["A2", "CHILD"]];
    assert request_lines([{"seat_label": "A2", "ticket_type": "ADULT"}])
        != request_lines([{"seat_label": "A2", "ticket_type": "CHILD"}]);
}

test "empty, oversized, malformed and repeated requests are refused" {
    assert _code([]) == "no_seats";
    assert _code(None) == "no_seats";
    assert _code(["A1"]) == "no_seats";
    assert _code([{"seat_label": f"A{i}", "ticket_type": "ADULT"} for i in range(11)])
        == "no_seats";
    assert _code(
        [
            {"seat_label": "A1", "ticket_type": "ADULT"},
            {"seat_label": "a1", "ticket_type": "CHILD"}
        ]
    )
        == "duplicate_seat";
}
