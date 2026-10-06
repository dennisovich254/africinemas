"""P3.6: the pricing engine (pure logic, core/catalog/pricing.jac; architecture §27, §28).

A cinema's price list: ticket types, a table of prices by ticket type and seat zone,
day-part surcharges (in the cinema's own time zone; they add up, and may be discounts),
and a per-ticket service fee. Money is integer cents (KES). A line never goes below the
service fee: base + surcharges is floored at 0.
"""

import from datetime { datetime, timezone }
import from core.catalog.pricing {
    PriceTable,
    PricingError,
    parse_price_list,
    price_ticket
}

def _list(changes: dict[str, any] | None = None) -> dict[str, any] {  # jac:ignore[W1037]
    data = {
        "timezone": "Africa/Nairobi",
        "ticket_types": [
            {"code": "ADULT", "name": "Adult"},
            {"code": "CHILD", "name": "Child"}
        ],
        "prices": [
            {"zone": "", "ticket_type": "ADULT", "price_cents": 80000},
            {"zone": "", "ticket_type": "CHILD", "price_cents": 50000},
            {"zone": "Gold", "ticket_type": "ADULT", "price_cents": 120000}
        ],
        "surcharges": [
            {
                "name": "Weekday evening",
                "days": [0, 1, 2, 3, 4],
                "start": "18:00",
                "end": "24:00",
                "amount_cents": 10000
            },
            {
                "name": "Weekend",
                "days": [5, 6],
                "start": "00:00",
                "end": "24:00",
                "amount_cents": 20000
            },
            {
                "name": "Morning",
                "days": [0, 1, 2, 3, 4, 5, 6],
                "start": "06:00",
                "end": "12:00",
                "amount_cents": -30000
            }
        ],
        "service_fee_cents": 3000
    };
    for (k, v) in (changes or {}).items() {
        data[k] = v;
    }
    return data;
}

def _table(changes: dict[str, any] | None = None) -> PriceTable {  # jac:ignore[W1037]
    (table, problems) = parse_price_list(_list(changes));
    assert problems == [] and table is not None , [p.code for p in problems];
    return table as PriceTable;
}

def _codes(data: dict[str, any]) -> list[str] {  # jac:ignore[W1037]
    (_, problems) = parse_price_list(data);
    return sorted([p.code for p in problems]);
}

def _at(day: int, hour: int, minute: int = 0) -> datetime {
    # 2026-10-05 is a Monday (weekday 0), given in Nairobi local time (UTC+3), in UTC.
    return datetime(2026, 10, 5 + day, hour - 3, minute, tzinfo=timezone.utc);
}

test "the base price comes from the ticket type and the seat's zone" {
    t = _table();
    tuesday_afternoon = _at(1, 14);
    assert price_ticket(t, "ADULT", "", tuesday_afternoon)
        == {
            "unit_price_cents": 80000,
            "surcharge_cents": 0,
            "service_fee_cents": 3000,
            "total_cents": 83000,
            "rules": []
        };
    assert price_ticket(t, "CHILD", "", tuesday_afternoon)["total_cents"] == 53000;
    assert price_ticket(t, "ADULT", "Gold", tuesday_afternoon)["total_cents"] == 123000;
}

test "day-part surcharges use the cinema's local time, start inclusive and end exclusive" {
    t = _table();
    evening = price_ticket(t, "ADULT", "", _at(1, 18));
    assert evening["surcharge_cents"] == 10000
        and evening["rules"] == ["Weekday evening"];
    assert price_ticket(t, "ADULT", "", _at(1, 17, 59))["surcharge_cents"] == 0;
    assert price_ticket(t, "ADULT", "", _at(1, 23, 59))["surcharge_cents"] == 10000;
    saturday = price_ticket(t, "ADULT", "", _at(5, 20));
    assert saturday["surcharge_cents"] == 20000 , "weekend, not the weekday evening";
    assert price_ticket(t, "ADULT", "", _at(1, 12))["surcharge_cents"] == 0 , "morning ends at 12:00";
}

test "surcharges add up, discounts included, and a line never goes below its fee" {
    t = _table();
    saturday_morning = price_ticket(t, "ADULT", "", _at(5, 10));
    assert saturday_morning["surcharge_cents"] == 20000 - 30000;
    assert saturday_morning["rules"] == ["Weekend", "Morning"];
    assert saturday_morning["total_cents"] == 80000 - 10000 + 3000;
    cheap = _table(
        {"prices": [{"zone": "", "ticket_type": "CHILD", "price_cents": 10000}]}
    );
    floored = price_ticket(cheap, "CHILD", "", _at(1, 9));
    assert floored["unit_price_cents"] + floored["surcharge_cents"] < 0;
    assert floored["total_cents"] == 3000 , "base and surcharges floor at zero";
}

test "a ticket type or zone without a price can't be quoted" {
    t = _table();
    for (ticket, zone, code) in [
        ("STUDENT", "", "unknown_ticket_type"),
        ("CHILD", "Gold", "no_price")
    ] {
        try {
            price_ticket(t, ticket, zone, _at(1, 14));
            assert False , f"{ticket}/{zone} was priced";
        } except PricingError as e {
            assert e.code == code , e.code;
        }
    }
}

test "a price list is checked, and every problem is reported at once" {
    assert _codes(_list()) == [];
    bad = _list(
        {
            "timezone": "Mars/Olympus",
            "ticket_types": [
                {"code": "ADULT", "name": "Adult"},
                {"code": "adult", "name": "Again"},
                {"code": "BAD CODE", "name": "Spaces"},
                {"code": "KID", "name": ""}
            ],
            "prices": [
                {"zone": "", "ticket_type": "ADULT", "price_cents": -1},
                {"zone": "", "ticket_type": "ADULT", "price_cents": 800.5},
                {"zone": "", "ticket_type": "NOPE", "price_cents": 100},
                {"zone": "z" * 41, "ticket_type": "ADULT", "price_cents": 100}
            ],
            "surcharges": [
                {
                    "name": "Late",
                    "days": [7],
                    "start": "18:00",
                    "end": "24:00",
                    "amount_cents": 1
                },
                {
                    "name": "Backwards",
                    "days": [0],
                    "start": "20:00",
                    "end": "18:00",
                    "amount_cents": 1
                },
                {
                    "name": "Odd",
                    "days": [0],
                    "start": "25:00",
                    "end": "26:00",
                    "amount_cents": 1
                },
                {
                    "name": "",
                    "days": [0],
                    "start": "10:00",
                    "end": "11:00",
                    "amount_cents": True
                }
            ],
            "service_fee_cents": -5
        }
    );
    assert _codes(bad)
        == sorted(
            [
                "bad_timezone",
                "duplicate_ticket_type",
                "bad_ticket_type",
                "bad_ticket_type",
                "bad_price",
                "bad_price",
                "unknown_ticket_type",
                "bad_zone",
                "bad_surcharge",
                "bad_surcharge",
                "bad_surcharge",
                "bad_surcharge",
                "bad_service_fee"
            ]
        ) , _codes(bad);
    assert "no_ticket_types" in _codes(_list({"ticket_types": []}));
}

test "a price list stores what it was given, tidied" {
    t = _table(
        {
            "ticket_types": [{"code": " adult ", "name": "  Adult  "}],
            "prices": [{"zone": " Gold ", "ticket_type": "adult", "price_cents": 100}],
            "surcharges": []
        }
    );
    assert t.ticket_types == {"ADULT": "Adult"};
    assert t.prices == {"Gold": {"ADULT": 100}};
    assert t.timezone == "Africa/Nairobi" and t.currency == "KES";
}

test "every amount is whole shillings: Kenya doesn't use cents, and M-Pesa charges shillings" {
    assert _codes(_list()) == [];
    assert _codes(
        _list({"prices": [{"zone": "", "ticket_type": "ADULT", "price_cents": 85050}]})
    )
        == ["bad_price"];
    assert _codes(_list({"service_fee_cents": 3050})) == ["bad_service_fee"];
    assert _codes(
        _list(
            {
                "surcharges": [
                    {
                        "name": "Evening",
                        "days": [0],
                        "start": "18:00",
                        "end": "24:00",
                        "amount_cents": 10050
                    }
                ]
            }
        )
    )
        == ["bad_surcharge"];
}
