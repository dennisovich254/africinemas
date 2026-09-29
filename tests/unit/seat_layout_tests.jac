"""P3.2: seat layout validation (pure logic, core/catalog/layout.jac).

A layout is a grid of rows x columns; seats sit in cells and empty cells are aisles.
Every problem is reported at once, each with a code (and the seat's label when it's
about one seat), so the designer (3.3) can point at all of them.
"""

import from core.catalog.layout {
    Seat,
    SEAT_TYPES,
    MAX_ROWS,
    MAX_COLS,
    parse_seats,
    check_layout
}

def _codes(
    rows: int, cols: int, seats: list[Seat], for_publish: bool = False
) -> list[str] {
    return sorted([p.code for p in check_layout(rows, cols, seats, for_publish)]);
}

def _seat(label: str, row: int, col: int, seat_type: str = "STANDARD") -> Seat {
    return Seat(label=label, row=row, col=col, seat_type=seat_type);
}

def _hall -> list[Seat] {
    # Row A: three seats, an aisle at column 3, three seats. Row B: a wheelchair space.
    return [
        _seat("A1", 0, 0),
        _seat("A2", 0, 1),
        _seat("A3", 0, 2),
        _seat("A4", 0, 4, "PREMIUM"),
        _seat("A5", 0, 5, "PREMIUM"),
        _seat("A6", 0, 6, "VIP"),
        _seat("B1", 1, 0, "WHEELCHAIR"),
        _seat("B2", 1, 1, "COMPANION")
    ];
}

test "a well-formed layout with an aisle has no problems" {
    assert _codes(2, 7, _hall(), for_publish=True) == [];
}

test "the ten seat types from the architecture are the only ones" {
    assert SEAT_TYPES
        == [
            "STANDARD",
            "PREMIUM",
            "VIP",
            "RECLINER",
            "COUPLE",
            "WHEELCHAIR",
            "COMPANION",
            "SOFA",
            "BLOCKED",
            "HOUSE"
        ];
    assert _codes(1, 2, [_seat("A1", 0, 0, "GOLD"), _seat("A2", 0, 1, "")])
        == ["bad_seat_type", "bad_seat_type"];
}

test "the grid must be within bounds" {
    for (rows, cols) in [
        (0, 5),
        (5, 0),
        (MAX_ROWS + 1, 5),
        (5, MAX_COLS + 1),
        (-1, -1)
    ] {
        assert "grid_size" in _codes(rows, cols, []) , f"{rows} x {cols}";
    }
    assert _codes(MAX_ROWS, MAX_COLS, []) == [] , "the largest grid is fine";
}

test "seats must sit inside the grid" {
    outside = [
        _seat("A1", -1, 0),
        _seat("A2", 0, -1),
        _seat("A3", 3, 0),
        _seat("A4", 0, 4)
    ];
    problems = check_layout(3, 4, outside);
    assert sorted(
        [
            p.label
            for p in problems
            if p.code == "outside_grid"
        ]
    )
        == ["A1", "A2", "A3", "A4"] , problems;
    assert _codes(3, 4, [_seat("A1", 2, 3)]) == [] , "the last cell is inside";
}

test "one seat per cell" {
    problems = check_layout(1, 2, [_seat("A1", 0, 0), _seat("A2", 0, 0)]);
    assert [(p.code, p.label) for p in problems] == [("cell_taken", "A2")] , problems;
}

test "labels are unique ignoring case, and well-formed" {
    assert _codes(1, 2, [_seat("A1", 0, 0), _seat("a1", 0, 1)]) == ["duplicate_label"];
    for bad in ["", "A 1", "A1234567", "A/1", "-A1"] {
        assert _codes(1, 1, [_seat(bad, 0, 0)]) == ["bad_label"] , repr(bad);
    }
    assert _codes(1, 3, [_seat("A01", 0, 0), _seat("VIP-3", 0, 1), _seat("12", 0, 2)])
        == [];
}

test "zones are short names" {
    seat = _seat("A1", 0, 0);
    seat.zone = "z" * 41;
    assert _codes(1, 1, [seat]) == ["bad_zone"];
    seat.zone = "Premium";
    assert _codes(1, 1, [seat]) == [];
}

test "publishing needs at least one seat that can be sold" {
    unsellable = [_seat("A1", 0, 0, "BLOCKED"), _seat("A2", 0, 1, "HOUSE")];
    assert _codes(1, 2, unsellable) == [] , "a draft may have none";
    assert _codes(1, 2, unsellable, for_publish=True) == ["nothing_to_sell"];
    assert _codes(1, 2, [], for_publish=True) == ["nothing_to_sell"];
}

test "every problem is reported at once" {
    seats = [
        _seat("A1", 0, 0, "GOLD"),
        _seat("A1", 0, 1),
        _seat("B 1", 5, 0),
        _seat("B2", 0, 0)
    ];
    assert _codes(2, 2, seats)
        == sorted(
            [
                "bad_seat_type",
                "duplicate_label",
                "bad_label",
                "outside_grid",
                "cell_taken"
            ]
        );
}

test "seats from a request are read strictly, and tidied" {
    (seats, problems) = parse_seats(
        [
            {"label": " a1 ", "row": 0, "col": 0, "seat_type": "vip"},
            {"label": "A2", "row": 0, "col": 1},
            {"label": "A3", "row": "x", "col": 2},
            {"label": "A4", "col": 3},
            "not a seat",
            {"label": "A5", "row": 0, "col": 4, "zone": "  Front  "},
            {"label": "A6", "row": True, "col": 5}
        ]
    );
    assert [(s.label, s.seat_type, s.zone) for s in seats]
        == [("A1", "VIP", ""), ("A2", "STANDARD", ""), ("A5", "STANDARD", "Front")];
    assert [p.code for p in problems] == ["bad_seat"] * 4 , problems;
}
