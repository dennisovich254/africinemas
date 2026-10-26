"""P12.14: paid snack batches share their booking's code, not its payment or stock.

Each addition is an Order under both the screening (reporting) and the original
Order (pickup). Ticket lines and totals on the original order stay immutable.
Collection belongs to each paid batch, so later purchases cannot re-open old snacks.
"""

import from datetime { datetime }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.booking.models { Order }

def addition_allowed(
    status: str, starts_at: str, at: datetime, state: str = "on_sale"
) -> bool {
    return state in ["on_sale", "sales_closed"]
        and status == "confirmed"
        and bool(starts_at)
        and at < datetime.fromisoformat(starts_at);
}

def additions(cinema: Tenant, booking: Order) -> list[Order] {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            o
            for o in [booking-->[?:Order]]
            if o.booking_id == node_id(booking) and o.tenant_id == node_id(cinema)
        ];
    } finally {
        restore(me);
    }
    return sorted(found, key=lambda (o: Order) -> str { return o.created_at; });
}

def snack_batches(cinema: Tenant, booking: Order) -> list[Order] {
    return [
        o
        for o in [booking] + additions(cinema, booking)
        if o.status == "confirmed" and any(not l.get("purpose") for l in o.snack_lines)
    ];
}

def snack_lines_of(batches: list[Order]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return [
        l for o in batches
        for l in o.snack_lines
        if not l.get("purpose")
    ];
}
