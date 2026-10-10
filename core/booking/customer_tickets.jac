"""A signed-in customer's bookings at a cinema: "My tickets" (P6.3b, ADR-0010, ADR-0023).

Guest checkout stays the default; an account is optional. A signed-in customer who holds
a booking's ticket link saves it to their account at that cinema (save_booking proves
the link, as resending does). The page does this by itself when a signed-in visitor sees
their tickets, so to them it's automatic. Saving makes their customer profile at the
cinema if they have none (customer_api.join_customer).

Each saved booking is a permanent claim in the caller's own namespace,
"customer-orders:<tenant id>:<customer root id>", keyed by the order. my_tickets reads only
that namespace, so a customer sees only their own bookings, and only at that cinema.
Both endpoints need a login (def:priv); a wrong link, or one for another cinema, answers
not_found.
"""

import from datetime { datetime }
import from core.clock { now }
import from core.claims { claim, claims_in }
import from core.tenancy.models { Tenant, NAME_MAX }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id }
import from core.tenancy.customer_api { join_customer }
import from core.authz.context { NotFound }
import from core.catalog.answers { answer }
import from core.booking.ticket_delivery {
    order_by_link,
    order_of_cinema,
    booking_view,
    link_path
}

glob SAVED: str = "customer-orders";

def _space(cinema: Tenant) -> str {
    # The caller's saved bookings at `cinema`.
    return f"{SAVED}:{node_id(cinema)}:{node_id(root)}";
}

def _save(slug: str, token: str, display_name: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, order) = order_by_link(slug, token);
    join_customer(slug, display_name.strip()[:NAME_MAX] or "Customer");
    claim(_space(cinema), node_id(order), node_id(order));
    return {"ok": True, "link": link_path(cinema, order)};
}

def _mine(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = open_cinema(slug);
    if cinema is None {
        raise NotFound();
    }
    at = now();
    upcoming: list[dict[str, any]] = [];  # jac:ignore[W1037]
    past: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for (order_id, _, _) in claims_in(_space(cinema)) {
        order = order_of_cinema(cinema, order_id);
        if order is None or order.status != "confirmed" {
            continue;
        }
        view = booking_view(cinema, order);
        view["link"] = link_path(cinema, order);
        view["upcoming"] = bool(view["starts_at"])
            and datetime.fromisoformat(view["starts_at"]) >= at;
        (upcoming if view["upcoming"] else past).append(view);
    }
    by_start = lambda (b: dict[str, any]) -> str { return b["starts_at"]; };  # jac:ignore[W1037]
    return {
        "ok": True,
        "bookings": sorted(upcoming, key=by_start)
            + sorted(past, key=by_start, reverse=True)
    };
}

def bookings_of_caller(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The signed-in caller's bookings at `slug`, as my_tickets answers, for the AI
    # agent's my_tickets tool (P8.1). The caller must check they're signed in: a
    # signed-out request runs on the shared guest graph.
    return answer(lambda -> any { return _mine(slug); });  # jac:ignore[W1037]
}

def save_for_caller(slug: str, token: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Saves the booking behind ticket link `token` to the caller, as save_booking does,
    # for a booking made in Claude's booking card (P8.6b).
    return answer(lambda -> any { return _save(slug, token, ""); });  # jac:ignore[W1037]
}

def:priv save_booking(slug: str, token: str, display_name: str = "") -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _save(slug, token, display_name); });  # jac:ignore[W1037]
}

def:priv my_tickets(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _mine(slug); });  # jac:ignore[W1037]
}
