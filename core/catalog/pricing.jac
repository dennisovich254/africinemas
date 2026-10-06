"""The pricing engine (P3.6, architecture §27, §28), as pure logic.

A cinema's price list:
- ticket types (ADULT, CHILD, ...), each with a display name;
- a price table: ticket type x seat zone, in integer cents (KES). A seat's zone comes from
  the seat designer; seats with no zone are in the "" (standard) zone;
- day-part surcharges: a name, weekdays (0 = Monday), a local start and end time (start
  inclusive, end exclusive, "24:00" allowed as an end), and an amount in cents that may be
  negative (a discount). Every matching surcharge applies, in list order;
- a service fee per ticket, and the cinema's time zone (surcharges use local time).

A ticket's price: max(0, table price + surcharges) + service fee. The price comes from the
table only; nothing a client sends is trusted. parse_price_list reports every problem at
once, like check_layout.
"""

import re;
import from datetime { datetime }
import from zoneinfo { ZoneInfo, ZoneInfoNotFoundError }

glob CURRENCY: str = "KES",
     DEFAULT_TIMEZONE: str = "Africa/Nairobi",
     CODE_PATTERN: str = "[A-Z][A-Z0-9_]{0,19}",
     TIME_PATTERN: str = "([01][0-9]|2[0-4]):([0-5][0-9])",
     NAME_MAX: int = 40,
     ZONE_MAX: int = 40,
     TICKET_TYPES_MAX: int = 10,
     SURCHARGES_MAX: int = 20,
     PRICE_MAX_CENTS: int = 100000000,  # KES 1,000,000
     ADJUST_MAX_CENTS: int = 10000000;  # KES 100,000

obj Surcharge {
    has name: str,
        days: list[int],
        start_min: int,
        end_min: int,
        amount_cents: int;
}

obj PriceTable {
    has currency: str,
        timezone: str,
        ticket_types: dict[str, str],
        prices: dict[str, dict[str, int]],
        surcharges: list[Surcharge],
        service_fee_cents: int;
}

obj PricingProblem {
    has code: str,
        message: str;
}

class PricingError(ValueError) {
    # A ticket we can't price, with a code and a message the UI can show.
    def init(self: PricingError, code: str, message: str) {
        super.init(message);
        self.code = code;
        self.message = message;
    }
}

def _clean(value: any) -> str {  # jac:ignore[W1037]
    return " ".join(str(value).split()) if value is not None else "";
}

def _cents(value: any, low: int, high: int) -> bool {  # jac:ignore[W1037]
    # An amount in cents, in [low, high], of whole shillings: Kenya doesn't use cents
    # and M-Pesa charges whole shillings (P5.1), so every price must be payable as
    # quoted. Floats and booleans aren't money.
    return isinstance(value, int)
        and not isinstance(value, bool)
        and value % 100 == 0
        and low <= value <= high;
}

def _minutes(text: any) -> int | None {  # jac:ignore[W1037]
    # "HH:MM" -> minutes since midnight (up to 24:00), or None.
    found = re.fullmatch(TIME_PATTERN, str(text));
    if found is None {
        return None;
    }
    total = int(found.group(1)) * 60 + int(found.group(2));
    return total if total <= 24 * 60 else None;
}

def _surcharge(item: any) -> Surcharge | None {  # jac:ignore[W1037]
    if not isinstance(item, dict) {
        return None;
    }
    name = _clean(item.get("name", ""));
    days = item.get("days", []);
    start = _minutes(item.get("start"));
    end = _minutes(item.get("end"));
    amount = item.get("amount_cents");
    if not name or len(name) > NAME_MAX {
        return None;
    }
    if not isinstance(days, list)
        or not days
        or any(
            not isinstance(d, int) or isinstance(d, bool) or not 0 <= d <= 6
            for d in days
        ) {
        return None;
    }
    if start is None or end is None or start >= 24 * 60 or end <= start {
        return None;
    }
    if not _cents(amount, -ADJUST_MAX_CENTS, ADJUST_MAX_CENTS) {
        return None;
    }
    return Surcharge(
        name=name,
        days=sorted(set(days)),
        start_min=start,
        end_min=end,
        amount_cents=int(amount)
    );
}

def parse_price_list(
    data: dict[str, any]  # jac:ignore[W1037]
) -> tuple[PriceTable | None, list[PricingProblem]] {
    problems: list[PricingProblem] = [];
    def problem(code: str, message: str) {
        problems.append(PricingProblem(code=code, message=message));
    }
    zone_name = _clean(data.get("timezone", "")) or DEFAULT_TIMEZONE;
    try {
        ZoneInfo(zone_name);
    } except (ZoneInfoNotFoundError, ValueError) {
        problem(
            "bad_timezone", f"'{zone_name}' isn't a time zone, like Africa/Nairobi."
        );
    }
    ticket_types: dict[str, str] = {};
    raw_types = data.get("ticket_types", []);
    if not isinstance(raw_types, list) or not raw_types {
        problem("no_ticket_types", "Add at least one ticket type, like Adult.");
        raw_types = [];
    } elif len(raw_types) > TICKET_TYPES_MAX {
        problem("bad_ticket_type", f"Use at most {TICKET_TYPES_MAX} ticket types.");
        raw_types = [];
    }
    for item in raw_types {
        code = _clean(item.get("code", "")).upper() if isinstance(item, dict) else "";
        name = _clean(item.get("name", "")) if isinstance(item, dict) else "";
        if re.fullmatch(CODE_PATTERN, code) is None
            or not name
            or len(name) > NAME_MAX {
            problem(
                "bad_ticket_type",
                f"Give each ticket type a name of up to {NAME_MAX} characters."
            );
        } elif code in ticket_types {
            problem(
                "duplicate_ticket_type",
                f"There are two ticket types called {name}. Give each a different name."
            );
        } else {
            ticket_types[code] = name;
        }
    }
    prices: dict[str, dict[str, int]] = {};
    raw_prices = data.get("prices", []);
    for item in raw_prices if isinstance(raw_prices, list) else [] {
        if not isinstance(item, dict) {
            problem(
                "bad_price", "Each price needs a zone, a ticket type and an amount."
            );
            continue;
        }
        zone = _clean(item.get("zone", ""));
        code = _clean(item.get("ticket_type", "")).upper();
        amount = item.get("price_cents");
        if len(zone) > ZONE_MAX {
            problem("bad_zone", f"A zone name has up to {ZONE_MAX} characters.");
        } elif not _cents(amount, 0, PRICE_MAX_CENTS) {
            where = f" in {zone}" if zone else "";
            problem(
                "bad_price",
                f"{ticket_types.get(code, code)}{where}: enter a whole number of shillings from KES 0 to 1,000,000."
            );
        } elif code not in ticket_types {
            problem("unknown_ticket_type", f"There's no ticket type coded {code}.");
        } elif code in prices.get(zone, {}) {
            problem(
                "duplicate_price",
                f"{ticket_types[code]} has two prices in {zone or 'the standard zone'}."
            );
        } else {
            prices.setdefault(zone, {})[code] = int(amount);
        }
    }
    surcharges: list[Surcharge] = [];
    raw_surcharges = data.get("surcharges", []);
    if isinstance(raw_surcharges, list) and len(raw_surcharges) > SURCHARGES_MAX {
        problem("bad_surcharge", f"Use at most {SURCHARGES_MAX} time-of-day extras.");
        raw_surcharges = [];
    }
    for item in raw_surcharges if isinstance(raw_surcharges, list) else [] {
        parsed = _surcharge(item);
        if parsed is None {
            label = _clean(item.get("name", "")) if isinstance(item, dict) else "";
            problem(
                "bad_surcharge",
                f"{label
                    or 'A time-of-day extra'} needs a name, at least one day, a start time before its end time, and an amount."
            );
        } else {
            surcharges.append(parsed);
        }
    }
    fee = data.get("service_fee_cents", 0);
    if not _cents(fee, 0, ADJUST_MAX_CENTS) {
        problem(
            "bad_service_fee",
            "Enter the service fee in whole shillings, from KES 0 to 100,000."
        );
        fee = 0;
    }
    if problems {
        return (None, problems);
    }
    return (
        PriceTable(
            currency=CURRENCY,
            timezone=zone_name,
            ticket_types=ticket_types,
            prices=prices,
            surcharges=surcharges,
            service_fee_cents=fee
        ),
        []
    );
}

def _clock(minutes: int) -> str {
    return f"{int(minutes / 60):02d}:{minutes % 60:02d}";
}

def price_list_data(table: PriceTable) -> dict[str, any] {  # jac:ignore[W1037]
    # The table in the same shape parse_price_list reads (for storage and for the UI).
    return {
        "currency": table.currency,
        "timezone": table.timezone,
        "ticket_types": [
            {"code": code, "name": name} for (code, name) in table.ticket_types.items()
        ],
        "prices": [
            {"zone": zone, "ticket_type": code, "price_cents": cents}
            for (zone, row) in table.prices.items() for (code, cents) in row.items()
        ],
        "surcharges": [
            {
                "name": s.name,
                "days": s.days,
                "start": _clock(s.start_min),
                "end": _clock(s.end_min),
                "amount_cents": s.amount_cents
            } for s in table.surcharges
        ],
        "service_fee_cents": table.service_fee_cents
    };
}

def price_ticket(
    table: PriceTable, ticket_type: str, zone: str, starts_at: datetime
) -> dict[str, any] {  # jac:ignore[W1037]
    # One ticket's price for a screening starting at `starts_at` (any time zone).
    code = _clean(ticket_type).upper();
    if code not in table.ticket_types {
        raise PricingError("unknown_ticket_type", f"There's no {code} ticket here.");
    }
    base = table.prices.get(_clean(zone), {}).get(code);
    if base is None {
        where = f"the {zone} zone" if zone else "standard seats";
        raise PricingError(
            "no_price", f"There's no {table.ticket_types[code]} price for {where}."
        );
    }
    local = starts_at.astimezone(ZoneInfo(table.timezone));
    minute = local.hour * 60 + local.minute;
    matched = [
        s
        for s in table.surcharges
        if local.weekday() in s.days and s.start_min <= minute < s.end_min
    ];
    surcharge = sum([s.amount_cents for s in matched]);
    return {
        "unit_price_cents": base,
        "surcharge_cents": surcharge,
        "service_fee_cents": table.service_fee_cents,
        "total_cents": max(0, base + surcharge) + table.service_fee_cents,
        "rules": [s.name for s in matched]
    };
}
