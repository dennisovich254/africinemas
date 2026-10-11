"""Stock rules (P12.4), as pure logic. Design guide docs/snacks-guide.md §8.

Stock is kept per variant per venue as on hand and reserved (the counts themselves are
atomic, in core/claims.jac); available = on hand − reserved. Every change has a reason
(REASONS) and is recorded as a movement; stock is never just overwritten.

- check_adjustment: the change to on hand for a reason and quantity, or why not.
- stock_status: "out", "low" or "ok" for the shelf.
- stock_allows: whether a tracked variant can sell `quantity` more (its at-zero rule).
"""

glob REASONS: list[str] = ["received", "damaged", "count", "other"],
     AT_ZERO: list[str] = ["unavailable", "allow"],
     QUANTITY_MAX: int = 100000;

def _whole(value: any) -> bool {  # jac:ignore[W1037]
    return isinstance(value, int) and not isinstance(value, bool);
}

def check_adjustment(reason: str, quantity: any, on_hand: int) -> tuple[int, str] {  # jac:ignore[W1037]
    # The change to on hand, and "" — or 0 and what's wrong.
    if reason not in REASONS {
        return (0, "Choose a reason: received, damaged, count correction or other.");
    }
    if not _whole(quantity) or abs(quantity) > QUANTITY_MAX {
        return (0, f"Enter a whole number up to {QUANTITY_MAX}.");
    }
    q: int = quantity;
    if reason == "received" {
        return (q, "") if q >= 1 else (0, "Enter how many arrived: 1 or more.");
    }
    if reason == "damaged" {
        if q < 1 {
            return (0, "Enter how many were damaged: 1 or more.");
        }
        return (0 - q, "") if q <= on_hand else (0, f"Only {on_hand} are on hand.");
    }
    if reason == "count" {
        return (q - on_hand, "")
            if q >= 0
            else (0, "Enter the counted total: 0 or more.");
    }
    if q == 0 {
        return (0, "Enter a change other than 0.");
    }
    return (q, "") if on_hand + q >= 0 else (0, f"Only {on_hand} are on hand.");
}

def check_rules(low_threshold: any, at_zero: any) -> str {  # jac:ignore[W1037]
    # "" when the stock rules are fine, else what's wrong.
    if not _whole(low_threshold) or low_threshold < 0 or low_threshold > QUANTITY_MAX {
        return f"Enter a low-stock alert from 0 to {QUANTITY_MAX}.";
    }
    if at_zero not in AT_ZERO {
        return "Choose what happens at zero: stop selling, or keep selling.";
    }
    return "";
}

def available_of(on_hand: int, reserved: int) -> int {
    return max(0, on_hand - reserved);
}

def stock_status(on_hand: int, reserved: int, low_threshold: int) -> str {
    available = available_of(on_hand, reserved);
    if available <= 0 {
        return "out";
    }
    return "low" if available <= low_threshold else "ok";
}

def stock_allows(tracked: bool, available: int, at_zero: str, quantity: int) -> bool {
    # Whether `quantity` more can be sold: always when untracked or "allow"; else only
    # what's available.
    return not tracked or at_zero == "allow" or available >= quantity;
}
