"""How AfriCinemas handles money (ADR-0081): never a float, never a lost or invented cent.

- **Integers only.** Every amount is an int of cents (KES 1 = 100). Rates are ints of
  basis points (1% = 100 bp). Nothing is stored, summed or compared as a float.
- **Whole shillings for what customers pay.** M-Pesa charges whole shillings, so every
  price a customer can be charged is a whole number of shillings (whole_shillings);
  a payment for anything else is refused, never truncated.
- **Rounded once, half up, at the order.** A fee is worked out exactly (cents × basis
  points) and rounded once per order to the nearest cent, half a cent up (div_half_up).
  Its parts are then allocated by the largest-remainder method (allocate), so the parts
  always add up to the total, whatever the split.
- **Cumulative, for repeated events.** Refunds credit the fee on everything refunded so
  far, less what was already credited, so a series of partial refunds credits exactly
  what one full refund would.
- **Parsed as text.** Amounts and rates from outside (M-Pesa's callback, the console) are
  read with Decimal from their text (decimal_of), never through float.
"""

import from decimal { Decimal, InvalidOperation, ROUND_HALF_UP }

glob CENTS_PER_SHILLING: int = 100,
     BP_PER_WHOLE: int = 10000;

def whole_shillings(cents: int) -> bool {
    return isinstance(cents, int) and cents % CENTS_PER_SHILLING == 0;
}

def div_half_up(numerator: int, denominator: int) -> int {
    # numerator / denominator, rounded to the nearest integer, halves away from zero.
    if denominator <= 0 {
        raise ValueError("the denominator must be positive");
    }
    sign = -1 if numerator < 0 else 1;
    return sign * ((abs(numerator) * 2 + denominator) // (2 * denominator));
}

def allocate(total: int, exact: list[int], scale: int) -> list[int] {
    # Splits `total` into len(exact) whole parts in proportion to `exact` (each part's
    # exact amount, `scale` times larger than a cent): each part gets its floor, and the
    # cents left over go one by one to the largest remainders (ties to the first). The
    # parts always add up to `total`.
    floors = [e // scale for e in exact];
    left = total - sum(floors);
    order = sorted(
        range(len(exact)),
        key=lambda (i: int) -> tuple[int, int] { return (0 - exact[i] % scale, i); }  # jac:ignore[W1037]
    );
    parts = list(floors);
    n = 0;
    while left > 0 and len(order) > 0 {
        parts[order[n % len(order)]] += 1;
        left -= 1;
        n += 1;
    }
    while left < 0 and len(order) > 0 {
        i = order[len(order) - 1 - (n % len(order))];
        if parts[i] > 0 {
            parts[i] -= 1;
            left += 1;
        }
        n += 1;
    }
    return parts;
}

def decimal_of(value: any) -> Decimal | None {  # jac:ignore[W1037]
    # A finite Decimal from text or a number (through its text), or None.
    if isinstance(value, bool) {
        return None;
    }
    try {
        found = Decimal(str(value).strip());
    } except (InvalidOperation, ValueError) {
        return None;
    }
    return found if found.is_finite() else None;
}

def cents_of_shillings(value: any) -> int | None {  # jac:ignore[W1037]
    # An amount in shillings (M-Pesa's "1660" or "1660.00") as cents, or None if it isn't
    # a whole number of cents.
    found = decimal_of(value);
    if found is None {
        return None;
    }
    cents = found * CENTS_PER_SHILLING;
    if cents != cents.to_integral_value() {
        return None;
    }
    return int(cents);
}

def basis_points_of(value: any) -> int | None {  # jac:ignore[W1037]
    # A percentage with at most two decimals ("7", "2.5", 7.25) as basis points, or None.
    found = decimal_of(value);
    if found is None {
        return None;
    }
    bp = found * 100;
    if bp != bp.quantize(Decimal(1), rounding=ROUND_HALF_UP) {
        return None;
    }
    return int(bp);
}
