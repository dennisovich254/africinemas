"""Going back from paying to change the order (owner, 2026-10-27): change_order.

At the Pay step, on the storefront and at the box office, the customer can go back to
change their seats, tickets or snacks. The unpaid order is cancelled and its seats go
back to an ordinary hold, so they stay the customer's while the hold lasts:
- **Only before any M-Pesa request is under way.** If a payment is pending, the
  request is refused until it ends, so no money can arrive for an order that's gone.
- **Never alongside a payment.** It takes the same one-time gate confirming takes
  (settlement's FINALIZE), permanently, so a late payment can never confirm it: it
  finds the order cancelled and goes to the refund path (late_success).
- **Everything placing did is undone, once:**
  - the snacks set aside go back on the shelf;
  - the seats go from "paying" back to held, until the hold's own time or at least
    RESUME_SECONDS from now;
  - the hold is a plain hold again, so the sweeper expires it if it's abandoned;
  - the claims placing took (the hold's order, the open order the resolver watches)
    are released, so the resolver never expires it, and never gives its snacks back a
    second time.
"""

import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims {
    claim,
    release,
    renew,
    make_permanent,
    holder as claim_holder
}
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id
}
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues { slots_of }
import from core.booking.models { SeatHold }
import from core.booking.availability { SeatState }
import from core.snacks.order_stock { release_snacks }
import from core.booking.hold_api {
    VISITOR_HOLDS,
    MAX_ENV,
    MAX_SECONDS,
    seconds_from_env,
    seat_namespace,
    showtime_on_sale,
    check_holder
}
import from core.booking.order_api { OPEN_ORDERS, ORDER_HOLDS, pending_order }
import from core.payments.models { PaymentIntent }
import from core.payments.state { PaymentState, is_final }
import from core.payments.settlement { FINALIZE }

glob RESUME_SECONDS: int = 120;

def _change(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, screening) = showtime_on_sale(slug, screening_id);
    check_holder(holder);
    order = pending_order(cinema, screening, holder);
    if order is None {
        raise Refused(
            "no_order", "There's no unpaid order to change. Reload the page."
        );
    }
    order_id = node_id(order);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        intents = [order-->[?:PaymentIntent]];
        hold: any = jobj(order.hold_id) if order.hold_id else None;  # jac:ignore[W1037]
    } finally {
        restore(me);
    }
    if [
        p
        for p in intents
        if not is_final(PaymentState(p.state))
    ] {
        raise Refused(
            "payment_in_progress",
            "An M-Pesa request is on its way to your phone. Wait for it to finish or time out, then change your order."
        );
    }
    if not isinstance(hold, SeatHold) {
        raise Refused("no_hold", "Your seats are no longer held. Choose them again.");
    }
    mine = f"change:{fresh_node_id()}";
    if claim(FINALIZE, order_id, mine) != mine {
        raise Refused("already_paid", "This order is already being paid.");
    }
    made = hold as SeatHold;
    hold_id = node_id(made);
    stamp = now();
    left = datetime.fromisoformat(made.expires_at) if made.expires_at else stamp;
    until = max(left, stamp + timedelta(seconds=RESUME_SECONDS));
    seconds = max(1, int((until - stamp).total_seconds()) + 1);
    space = seat_namespace(screening_id);
    for label in made.seats {
        renew(space, label, holder, seconds);
    }
    visitor = f"{screening_id}:{holder}";
    keep = seconds_from_env(MAX_ENV, MAX_SECONDS) + 60;
    if not renew(VISITOR_HOLDS, visitor, hold_id, keep) {
        claim(VISITOR_HOLDS, visitor, hold_id, keep);
    }
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        order.status = "cancelled";
        made.status = "held";
        made.expires_at = until.isoformat();
        for x in slots_of(cinema, screening) {
            if x.hold_id == hold_id and x.state == SeatState.PAYMENT_PENDING.value {
                x.state = SeatState.HELD.value;
                x.hold_expires_at = made.expires_at;
            }
        }
        if order.snack_stock {
            release_snacks(cinema, order.snack_venue_id, order.snack_stock);
        }
        commit_now();
    } except Exception as e {
        release(FINALIZE, order_id, mine);
        restore(me);
        raise e;
    }
    restore(me);
    # A cancelled order is never confirmed; its claims are no longer needed.
    make_permanent(FINALIZE, order_id, mine);
    release(OPEN_ORDERS, order_id, node_id(cinema));
    release(ORDER_HOLDS, hold_id, order_id);
    return {
        "ok": True,
        "hold": {
            "seats": list(made.seats),
            "expires_at": made.expires_at,
            "status": made.status
        }
    };
}

def:pub change_order(slug: str, screening_id: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _change(slug, screening_id, holder); });  # jac:ignore[W1037]
}
