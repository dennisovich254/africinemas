"""Seat layouts (P3.2, architecture §21): validation, as pure logic.

A layout is a grid of `rows` x `cols` cells. A seat sits in one cell; empty cells are
aisles and gaps. Each seat has a label unique in the layout (stored upper-case), one of
the architecture's seat types, and an optional zone name for pricing (3.6).
`check_layout` reports every problem at once so the designer (3.3) can show them all.
"""

import re;

glob SEAT_TYPES: list[str] = [
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
     ],
     # Seats that are never sold: out of service, or kept for the house.
     UNSELLABLE: list[str] = ["BLOCKED", "HOUSE"],
     MAX_ROWS: int = 50,
     MAX_COLS: int = 60,
     ZONE_MAX: int = 40,
     # 1 to 6 letters, digits or hyphens, starting with a letter or digit: A1, A01, VIP-3.
     LABEL_PATTERN: str = "[A-Z0-9][A-Z0-9-]{0,5}";

obj Seat {
    has label: str,
        row: int,
        col: int,
        seat_type: str = "STANDARD",
        zone: str = "";
}

obj LayoutProblem {
    # What's wrong, for a person to fix; `label` names the seat when it's about one.
    has code: str,
        message: str,
        label: str = "";
}

def _whole_number(value: any) -> bool {  # jac:ignore[W1037]
    # An int, and not a bool (which Python counts as one).
    return isinstance(value, int) and not isinstance(value, bool);
}

def parse_seats(raw: list[any]) -> tuple[list[Seat], list[LayoutProblem]] {  # jac:ignore[W1037]
    # Seats from a request body. Entries that aren't a seat (not an object, or without
    # a whole-number row and column) become bad_seat problems; the rest are tidied:
    # labels and seat types upper-cased and trimmed, zones trimmed.
    seats: list[Seat] = [];
    problems: list[LayoutProblem] = [];
    for (index, item) in enumerate(raw) {
        if not isinstance(item, dict)
            or not _whole_number(item.get("row"))
            or not _whole_number(item.get("col")) {
            problems.append(
                LayoutProblem(
                    code="bad_seat",
                    message=f"Seat {index + 1} needs a label, a row and a column."
                )
            );
            continue;
        }
        seats.append(
            Seat(
                label=str(item.get("label", "")).strip().upper(),
                row=item["row"],
                col=item["col"],
                seat_type=str(item.get("seat_type", "STANDARD")).strip().upper(),
                zone=" ".join(str(item.get("zone", "")).split())
            )
        );
    }
    return (seats, problems);
}

def check_layout(
    rows: int, cols: int, seats: list[Seat], for_publish: bool = False
) -> list[LayoutProblem] {
    problems: list[LayoutProblem] = [];
    if not 1 <= rows <= MAX_ROWS or not 1 <= cols <= MAX_COLS {
        problems.append(
            LayoutProblem(
                code="grid_size",
                message=f"A layout has 1 to {MAX_ROWS} rows and 1 to {MAX_COLS} columns."
            )
        );
    }
    seen_labels: set[str] = set();
    taken_cells: set[str] = set();
    for seat in seats {
        # Labels compare upper-cased, however the seat was made (parse_seats stores them so).
        label_key = seat.label.upper();
        if re.fullmatch(LABEL_PATTERN, label_key) is None {
            problems.append(
                LayoutProblem(
                    code="bad_label",
                    message="Label seats with 1 to 6 letters, digits or hyphens, like A12.",
                    label=seat.label
                )
            );
        } elif label_key in seen_labels {
            problems.append(
                LayoutProblem(
                    code="duplicate_label",
                    message=f"Two seats are labelled {seat.label}.",
                    label=seat.label
                )
            );
        }
        seen_labels.add(label_key);
        if seat.seat_type not in SEAT_TYPES {
            problems.append(
                LayoutProblem(
                    code="bad_seat_type",
                    message=f"{seat.label}: choose one of {', '.join(SEAT_TYPES)}.",
                    label=seat.label
                )
            );
        }
        if len(seat.zone) > ZONE_MAX {
            problems.append(
                LayoutProblem(
                    code="bad_zone",
                    message=f"{seat.label}: a zone name has up to {ZONE_MAX} characters.",
                    label=seat.label
                )
            );
        }
        if not (0 <= seat.row < rows and 0 <= seat.col < cols) {
            problems.append(
                LayoutProblem(
                    code="outside_grid",
                    message=f"{seat.label} is outside the {rows} x {cols} grid.",
                    label=seat.label
                )
            );
            continue;
        }
        cell = f"{seat.row}:{seat.col}";
        if cell in taken_cells {
            problems.append(
                LayoutProblem(
                    code="cell_taken",
                    message=f"{seat.label} is in a cell that already has a seat.",
                    label=seat.label
                )
            );
        }
        taken_cells.add(cell);
    }
    if for_publish and not any(s.seat_type not in UNSELLABLE for s in seats) {
        problems.append(
            LayoutProblem(
                code="nothing_to_sell",
                message="Add at least one seat that can be sold before publishing."
            )
        );
    }
    return problems;
}

def sellable_count(seats: list[Seat]) -> int {
    return len(
        [
            s
            for s in seats
            if s.seat_type not in UNSELLABLE
        ]
    );
}
