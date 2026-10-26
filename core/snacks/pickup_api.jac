"""Collecting snacks at the snack counter (P12.9; ADR-0053). Tenant-scoped endpoints,
listed in tests/isolation/registry.jac.

A paid order with snacks has one pickup code (core/booking/confirm.jac): a reference
like a ticket's, and a QR signed as "SNK1". Staff on shift with concessions.collect at
the order's snack venue (box office staff and managers, general managers, admins,
owners; a venue-limited role only at its venues):

- snack_pickup(tenant, code): what the order holds, to get ready, and whether it can be
  handed over now. Changes nothing.
- hand_over_snacks(tenant, code): hands it over, once. Refusals, in the order they're
  checked: invalid_code (not a code this server made, nor a reference), ticket_code (a
  ticket's, which is scanned at the door), unknown_pickup (no such pickup here; another
  cinema's gets the same answer), not_paid, too_early (pickup opens PICKUP_OPENS_MINUTES
  before the showtime starts, except a sale taken by staff at the counter can be handed
  over immediately), showtime_over (it closes when the showtime ends) and
  already_collected (with when, and who handed them over).

One handover per order, however many counters race: the order is claimed (COLLECTED,
an atomic claim, ADR-0007) before it is marked collected, and the claim is released if
saving fails, as at the door (core/booking/redeem_api.jac).
"""

import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, release, holder }
import from core.authz.policy { Resource, require }
import from core.authz.context { TenantScope, on_shift }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id
}
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Screening }
import from core.catalog.venues { find_screening, find_movie, find_venue }
import from core.catalog.storefront_api { cinema_timezone }
import from core.booking.models { Order }
import from core.booking.ticket_codes {
    REFS,
    VERSION,
    PICKUPS,
    PICKUP_VERSION,
    read_qr,
    typed_reference
}
import from core.booking.redeem_api { staff_name }
import from core.payments.ledger { LedgerEntry }
import from core.audit.log { audited }

glob COLLECT: str = "concessions.collect",
     # A snacks-only sale at the box office (P12.10) is collected within this many hours.
     WALK_IN_HOURS: int = 24,
     COLLECTED: str = "snacks-collected",
     PICKUP_OPENS_MINUTES: int = 120,
     TICKET_CODE: str = "This is a ticket. It's scanned at the door, not here.";

def _reference(code: str) -> str {
    # The pickup reference a scanned or typed code names.
    text = code.strip();
    if text.startswith(f"{VERSION}.") {
        raise Refused("ticket_code", TICKET_CODE);
    }
    found = read_qr(text, PICKUP_VERSION)
        if text.startswith(f"{PICKUP_VERSION}.")
        else typed_reference(text);
    if found is None {
        raise Refused(
            "invalid_code", "This isn't a snack pickup code from this cinema."
        );
    }
    return found;
}

def _order(scope: TenantScope, reference: str) -> Order {
    # The cinema's order with this pickup code; another cinema's reads as unknown.
    owner = holder(PICKUPS, reference);
    unknown = Refused(
        "unknown_pickup", "No snack order with this code at this cinema."
    );
    if owner is None {
        if holder(REFS, reference) is not None {
            raise Refused("ticket_code", TICKET_CODE);
        }
        raise unknown;
    }
    (tenant_id, _, order_id) = owner.partition("|");
    if tenant_id != node_id(scope.tenant) {
        raise unknown;
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found: any = jobj(order_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    if not isinstance(found, Order) {
        raise unknown;
    }
    return found as Order;
}

def opens_at(screening: Screening) -> datetime {
    return datetime.fromisoformat(screening.starts_at)
        - timedelta(minutes=PICKUP_OPENS_MINUTES);
}

def _walk_in_open(order: Order, at: datetime) -> bool {
    # A snacks-only sale's snacks can be handed over for WALK_IN_HOURS after it.
    return at - datetime.fromisoformat(order.created_at)
        < timedelta(hours=WALK_IN_HOURS);
}

def _sold_at_counter(scope: TenantScope, order: Order) -> bool {
    # Counter cash and M-Pesa payments record the staff member who took the sale.
    # Those snacks are already in front of the customer, so they can be handed over
    # immediately instead of waiting for the public showtime pickup window.
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found = any(
            [
                e.kind == "payment" and bool(e.recorded_by)
                for e in [order-->[?:LedgerEntry]]
            ]
        );
    } finally {
        restore(me);
    }
    return found;
}

def _view(
    scope: TenantScope, order: Order, screening: Screening | None
) -> dict[str, any] {  # jac:ignore[W1037]
    # What the counter shows: the order, its showtime, its snacks and their state.
    movie = find_movie(scope.tenant, screening.movie_id)
        if screening is not None
        else None;
    venue = find_venue(scope.tenant, order.snack_venue_id);
    at = now();
    window = "open";
    if not order.screening_id {
        # Snacks only, at the box office (P12.10): handed over within a day.
        window = "open" if _walk_in_open(order, at) else "over";
    } elif screening is None or at >= datetime.fromisoformat(screening.ends_at) {
        window = "over";
    } elif not _sold_at_counter(scope, order) and at < opens_at(screening) {
        window = "early";
    }
    return {
        "reference": order.pickup_reference,
        "order_reference": order.reference,
        "paid": order.status == "confirmed",
        "movie_title": movie.title if movie is not None else "",
        "starts_at": screening.starts_at if screening is not None else "",
        "opens_at": opens_at(screening).isoformat() if screening is not None else "",
        "venue": venue.name if venue is not None else "",
        "timezone": cinema_timezone(scope.tenant),
        "window": window,
        "snacks": [
            {
                "name": l["name"],
                "quantity": l["quantity"],
                "addons": [a["name"] for a in l.get("addons", [])],
                "choices": [c["name"] for c in l.get("choices", [])]
            }
            for l in order.snack_lines
            if not l.get("purpose")
        ],
        "collected_at": order.snacks_collected_at,
        "collected_by": staff_name(scope.tenant, order.snacks_collected_by)
            if order.snacks_collected_by
            else ""
    };
}

def _found(tenant: str, code: str) -> tuple[TenantScope, Order, Screening | None] {
    # The caller's scope, the order a code names and its showtime, once the caller may
    # hand over snacks where they're collected.
    scope = on_shift(tenant);
    order = _order(scope, _reference(code));
    require(
        scope.ctx,
        COLLECT,
        Resource(tenant_id=scope.ctx.tenant_id, venue_id=order.snack_venue_id)
    );
    return (scope, order, find_screening(scope.tenant, order.screening_id));
}

def _collected(scope: TenantScope, at: str, member: str) -> Refused {
    return Refused(
        "already_collected",
        "These snacks have already been handed over.",
        {"collected_at": at, "collected_by": staff_name(scope.tenant, member)}
    );
}

def _snack_pickup(tenant: str, code: str) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, order, screening) = _found(tenant, code);
    return {"ok": True, "pickup": _view(scope, order, screening)};
}

def _hand_over(tenant: str, code: str) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, order, screening) = _found(tenant, code);
    if order.status != "confirmed" {
        raise Refused("not_paid", "This order isn't paid.");
    }
    at = now();
    if not order.screening_id {
        # Snacks only, at the box office (P12.10): no showtime, a day to collect.
        if not _walk_in_open(order, at) {
            raise Refused("sale_over", "This sale is more than a day old.");
        }
    } elif screening is None or at >= datetime.fromisoformat(screening.ends_at) {
        raise Refused("showtime_over", "This showtime has ended.");
    } elif not _sold_at_counter(scope, order) and at < opens_at(screening) {
        raise Refused(
            "too_early",
            "Snacks for this showtime can't be collected yet.",
            {"opens_at": opens_at(screening).isoformat()}
        );
    }
    if order.snacks_collected_at {
        raise _collected(scope, order.snacks_collected_at, order.snacks_collected_by);
    }
    member = scope.ctx.member_root_id;
    stamp = at.isoformat();
    mine = f"{member}|{stamp}|{fresh_node_id()}";
    won = claim(COLLECTED, node_id(order), mine);
    if won != mine {
        (giver, _, rest) = won.partition("|");
        raise _collected(scope, rest.partition("|")[0], giver);
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        order.snacks_collected_at = stamp;
        order.snacks_collected_by = member;
        commit_now();
    } except Exception as e {
        release(COLLECTED, node_id(order), mine);
        raise e;
    } finally {
        restore(me);
    }
    return {"ok": True, "pickup": _view(scope, order, screening)};
}

def:protect snack_pickup(tenant: str, code: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _snack_pickup(tenant, code); });  # jac:ignore[W1037]
}

def _do_hand_over(tenant: str, code: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _hand_over(tenant, code); });  # jac:ignore[W1037]
}

def:protect hand_over_snacks(tenant: str, code: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "snacks.handed_over",
        "order",
        "",
        lambda -> any { return _do_hand_over(tenant, code); }  # jac:ignore[W1037]
    );
}
