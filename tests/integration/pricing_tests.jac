"""P3.6: price lists and quotes, through the production app (main.jac).

Each cinema has one price list (core/catalog/pricing.jac), versioned on every save.
quote_tickets prices seats of a published screening from the price list alone: seat
zones come from the screening's own seat slots, and anything a client sends besides
seat labels and ticket types is ignored (architecture §27, §28).
"""

import from os { path }
import from datetime { datetime, timedelta, timezone }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     NOVA: str = "nova",
     # 21:00 in Nairobi (UTC+3), two days ahead: inside the everyday evening surcharge.
     START: datetime = (datetime.now(timezone.utc) + timedelta(days=2)).replace(
         hour=18, minute=0, second=0, microsecond=0
     );

obj Setup {
    has app: Served,
        venue: str,
        screening: str,
        draft: str;
}

def _prices(adult: int = 80000) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "tenant": NOVA,
        "timezone": "Africa/Nairobi",
        "ticket_types": [
            {"code": "ADULT", "name": "Adult"},
            {"code": "CHILD", "name": "Child"}
        ],
        "prices": [
            {"zone": "", "ticket_type": "ADULT", "price_cents": adult},
            {"zone": "", "ticket_type": "CHILD", "price_cents": 50000},
            {"zone": "Gold", "ticket_type": "ADULT", "price_cents": 120000}
        ],
        "surcharges": [
            {
                "name": "Evening",
                "days": [0, 1, 2, 3, 4, 5, 6],
                "start": "18:00",
                "end": "24:00",
                "amount_cents": 10000
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
}

def _cinema(names: list[str], with_prices: bool = True) -> Setup {
    app = served(MAIN, ["owner"] + names);
    app.call("owner", "create_cinema", {"name": "Nova Cinemas", "slug": NOVA});
    app.call("owner", "start_shift", {"tenant": NOVA});
    venue = app.call(
        "owner",
        "create_venue",
        {"tenant": NOVA, "name": "Westgate", "city": "Nairobi", "address": ""}
    )["venue"]["venue_id"];
    screen = app.call(
        "owner",
        "create_auditorium",
        {"tenant": NOVA, "venue_id": venue, "name": "Screen 1"}
    )["auditorium"]["auditorium_id"];
    seats = [
        {"label": "A1", "row": 0, "col": 0},
        {"label": "A2", "row": 0, "col": 1},
        {"label": "A3", "row": 0, "col": 2, "seat_type": "VIP", "zone": "Gold"},
        {"label": "A4", "row": 0, "col": 3, "seat_type": "BLOCKED"}
    ];
    app.call(
        "owner",
        "save_layout",
        {"tenant": NOVA, "auditorium_id": screen, "rows": 1, "cols": 4, "seats": seats}
    );
    app.call("owner", "publish_layout", {"tenant": NOVA, "auditorium_id": screen});
    movie = app.call(
        "owner",
        "create_movie",
        {
            "tenant": NOVA,
            "title": "Rafiki",
            "synopsis": "",
            "runtime_minutes": 83,
            "age_rating": "18",
            "genres": [],
            "language": ""
        }
    )["movie"]["movie_id"];
    ids: list[str] = [];
    for hours in [0, 4] {
        ids.append(
            app.call(
                "owner",
                "create_screening",
                {
                    "tenant": NOVA,
                    "auditorium_id": screen,
                    "movie_id": movie,
                    "starts_at": (START + timedelta(hours=hours)).isoformat()
                }
            )["screening"]["screening_id"]
        );
    }
    app.call("owner", "schedule_screening", {"tenant": NOVA, "screening_id": ids[0]});
    app.call("owner", "publish_screening", {"tenant": NOVA, "screening_id": ids[0]});
    if with_prices {
        assert app.call("owner", "save_price_list", _prices())["ok"];
    }
    return Setup(app=app, venue=venue, screening=ids[0], draft=ids[1]);
}

def _quote(
    s: Setup,
    items: list[dict[str, any]],
    screening: str = "",
    who: str = "owner"  # jac:ignore[W1037]
) -> any {  # jac:ignore[W1037]
    return s.app.call(
        who,
        "quote_tickets",
        {"tenant": NOVA, "screening_id": screening or s.screening, "items": items}
    );
}

def _code(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

test "a price list is saved, read back and versioned" {
    s = _cinema([], with_prices=False);
    try {
        empty = s.app.call("owner", "get_price_list", {"tenant": NOVA});
        assert empty == {"ok": True, "price_list": None} , empty;
        first = s.app.call("owner", "save_price_list", _prices());
        assert first["ok"] and first["price_list"]["version"] == 1 , first;
        got = s.app.call("owner", "get_price_list", {"tenant": NOVA})["price_list"];
        assert got["version"] == 1 and got["currency"] == "KES";
        assert got["ticket_types"]
            == [{"code": "ADULT", "name": "Adult"}, {"code": "CHILD", "name": "Child"}];
        assert len(got["prices"]) == 3 and len(got["surcharges"]) == 2;
        assert got["service_fee_cents"] == 3000;
        second = s.app.call("owner", "save_price_list", _prices(adult=85000));
        assert second["price_list"]["version"] == 2;
        s.app.restart();
        assert s.app.call("owner", "get_price_list", {"tenant": NOVA})["price_list"][
            "version"
        ]
            == 2;
    } finally {
        s.app.close();
    }
}

test "an invalid price list is refused with every problem, and nothing is saved" {
    s = _cinema([], with_prices=False);
    try {
        bad = _prices();
        bad["ticket_types"] = [];
        bad["service_fee_cents"] = -1;
        answer = s.app.call("owner", "save_price_list", bad);
        assert _code(answer) == "invalid_price_list" , answer;
        assert sorted([p["code"] for p in answer["error"]["problems"]])
            == [
                "bad_service_fee",
                "no_ticket_types",
                "unknown_ticket_type",
                "unknown_ticket_type",
                "unknown_ticket_type"
            ] , answer["error"]["problems"];
        assert s.app.call("owner", "get_price_list", {"tenant": NOVA})["price_list"]
            is None;
    } finally {
        s.app.close();
    }
}

test "a quote prices each seat by ticket type, seat zone and the screening's local time" {
    s = _cinema([]);
    try {
        answer = _quote(
            s,
            [
                {"seat_label": "A1", "ticket_type": "ADULT"},
                {"seat_label": "A2", "ticket_type": "child"},
                {"seat_label": "A3", "ticket_type": "ADULT"}
            ]
        );
        assert answer["ok"] , answer;
        quote = answer["quote"];
        assert (quote["screening_id"], quote["currency"], quote["price_list_version"])
            == (s.screening, "KES", 1);
        assert [
            (
                l["seat_label"],
                l["zone"],
                l["ticket_type"],
                l["ticket_name"],
                l["total_cents"],
                l["rules"]
            ) for l in quote["lines"]
        ]
            == [
                ("A1", "", "ADULT", "Adult", 80000 + 10000 + 3000, ["Evening"]),
                ("A2", "", "CHILD", "Child", 50000 + 10000 + 3000, ["Evening"]),
                ("A3", "Gold", "ADULT", "Adult", 120000 + 10000 + 3000, ["Evening"])
            ] , quote["lines"];
        assert quote["total_cents"] == 93000 + 63000 + 133000;
    } finally {
        s.app.close();
    }
}

test "prices a client sends are ignored" {
    s = _cinema([]);
    try {
        honest = _quote(s, [{"seat_label": "A1", "ticket_type": "ADULT"}])["quote"];
        cheeky = _quote(
            s,
            [
                {
                    "seat_label": "A1",
                    "ticket_type": "ADULT",
                    "price_cents": 1,
                    "unit_price_cents": 1,
                    "total_cents": 1,
                    "zone": "Gold"
                }
            ]
        )["quote"];
        assert cheeky == honest , cheeky;
        assert cheeky["total_cents"] == 93000;
    } finally {
        s.app.close();
    }
}

test "a quote is refused for seats, ticket types and screenings it can't price" {
    s = _cinema([]);
    try {
        cases = [
            ([{"seat_label": "Z9", "ticket_type": "ADULT"}], "unknown_seat"),
            ([{"seat_label": "A4", "ticket_type": "ADULT"}], "seat_not_for_sale"),
            (
                [
                    {"seat_label": "A1", "ticket_type": "ADULT"},
                    {"seat_label": "a1", "ticket_type": "CHILD"}
                ],
                "duplicate_seat"
            ),
            ([{"seat_label": "A1", "ticket_type": "STUDENT"}], "unknown_ticket_type"),
            ([{"seat_label": "A3", "ticket_type": "CHILD"}], "no_price"),
            ([], "no_seats"),
            (["A1"], "no_seats")
        ];
        for (items, code) in cases {
            answer = _quote(s, items);
            assert _code(answer) == code , f"{items}: {answer}";
        }
        draft = _quote(
            s, [{"seat_label": "A1", "ticket_type": "ADULT"}], screening=s.draft
        );
        assert _code(draft) == "not_published" , draft;
    } finally {
        s.app.close();
    }
}

test "a quote needs a price list, and follows its latest version" {
    s = _cinema([], with_prices=False);
    try {
        one = [{"seat_label": "A1", "ticket_type": "ADULT"}];
        assert _code(_quote(s, one)) == "no_prices";
        s.app.call("owner", "save_price_list", _prices());
        s.app.call("owner", "save_price_list", _prices(adult=90000));
        quote = _quote(s, one)["quote"];
        assert quote["price_list_version"] == 2
            and quote["total_cents"] == 103000 , quote;
    } finally {
        s.app.close();
    }
}

test "box office can read prices and quote; only admins change prices" {
    s = _cinema(["bo"]);
    try {
        token = s.app.call(
            "owner",
            "invite_staff",
            {"tenant": NOVA, "role": "box_office_agent", "venue_id": s.venue}
        )["token"];
        s.app.call("bo", "accept_invite", {"token": token});
        s.app.call("bo", "start_shift", {"tenant": NOVA});
        assert s.app.call("bo", "get_price_list", {"tenant": NOVA})["price_list"][
            "version"
        ]
            == 1;
        assert _quote(s, [{"seat_label": "A1", "ticket_type": "ADULT"}], who="bo")[
            "ok"
        ];
        assert _code(s.app.call("bo", "save_price_list", _prices(adult=1)))
            == "forbidden";
    } finally {
        s.app.close();
    }
}

test "another cinema's screenings and prices are not found" {
    s = _cinema(["rival"]);
    try {
        s.app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        s.app.call("rival", "start_shift", {"tenant": "rift"});
        answer = s.app.call(
            "rival",
            "quote_tickets",
            {
                "tenant": "rift",
                "screening_id": s.screening,
                "items": [{"seat_label": "A1", "ticket_type": "ADULT"}]
            }
        );
        assert _code(answer) == "not_found" , answer;
        assert s.app.call("rival", "get_price_list", {"tenant": "rift"})["price_list"]
            is None , "Rift has its own (empty) price list";
    } finally {
        s.app.close();
    }
}

test "prices need an open shift" {
    s = _cinema([]);
    try {
        s.app.call("owner", "end_shift", {"tenant": NOVA});
        assert _code(s.app.call("owner", "save_price_list", _prices())) == "no_shift";
        assert _code(_quote(s, [{"seat_label": "A1", "ticket_type": "ADULT"}]))
            == "no_shift";
    } finally {
        s.app.close();
    }
}
