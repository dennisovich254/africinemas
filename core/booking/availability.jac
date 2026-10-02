"""A seat's state at a moment (P4.2, architecture §24, §25, §102), as pure logic.

A SeatSlot (one per seat of a published screening) stores a state and, while held, when
the hold expires. Holds lapse lazily: every read treats a hold whose time is up as
available, so correctness never waits for the sweeper (P4.4). A hold that is paying
(PAYMENT_PENDING) never lapses this way; only the payment's outcome releases it.

Visitors see four states, each with words as well as a colour: available, held (by
someone else, perhaps paying), sold, and not for sale (BLOCKED and HOUSE seats).
"""

import from datetime { datetime }

enum SeatState {
    AVAILABLE = "available",
    HELD = "held",
    PAYMENT_PENDING = "payment_pending",
    SOLD = "sold",
    NOT_FOR_SALE = "not_for_sale"
}

glob TEXT: dict[str, str] = {
         "available": "Available",
         "held": "Held by another customer",
         "sold": "Sold",
         "not_for_sale": "Not for sale"
     };

def effective_state(state: str, hold_expires_at: str, now: datetime) -> SeatState {
    # The slot's state at `now`: a plain hold past its expiry is available again.
    stored = SeatState(state);
    if stored == SeatState.HELD {
        if not hold_expires_at or datetime.fromisoformat(hold_expires_at) <= now {
            return SeatState.AVAILABLE;
        }
    }
    return stored;
}

def public_state(state: SeatState) -> str {
    # What a visitor is told: a paying hold is just "held".
    if state == SeatState.PAYMENT_PENDING {
        return SeatState.HELD.value;
    }
    return state.value;
}

def state_text(shown: str) -> str {
    # Words for a public state, for screen readers and beside the seat map's colours.
    return TEXT[shown];
}

def sellable(state: SeatState) -> bool {
    return state == SeatState.AVAILABLE;
}
