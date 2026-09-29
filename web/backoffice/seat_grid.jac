"""The seat designer's grid, as plain data (P3.3).

The designer keeps `cells`: {"row:col": seat type} for every cell that holds a seat;
cells not in it are aisles. Seats are labelled automatically: the row's letter (A, B, …
Z, AA, AB, …) and the seat's number in that row, counted left to right and skipping
aisles. So the layout is labelled consistently whoever draws it, and the server's
check_layout (core/catalog/layout.jac) validates every save.
"""

# Public: SeatDesigner uses these at runtime, and client modules export only :pub names.
glob:pub MAX_ROWS: int = 50,
     MAX_COLS: int = 60,
     # (seat type, what people call it, a short code shown in the seat, Tailwind classes).
     # The code and the legend carry the meaning; the colour only helps (WCAG 1.4.1).
     SEAT_KINDS: list[tuple[str, str, str, str]] = [
         (
             "STANDARD",
             "Standard",
             "S",
             "bg-sky-100 text-sky-950 border-sky-400 dark:bg-sky-900 dark:text-sky-50 dark:border-sky-500"
         ),
         (
             "PREMIUM",
             "Premium",
             "P",
             "bg-violet-100 text-violet-950 border-violet-400 dark:bg-violet-900 dark:text-violet-50 dark:border-violet-500"
         ),
         (
             "VIP",
             "VIP",
             "V",
             "bg-amber-100 text-amber-950 border-amber-500 dark:bg-amber-800 dark:text-amber-50 dark:border-amber-500"
         ),
         (
             "RECLINER",
             "Recliner",
             "R",
             "bg-rose-100 text-rose-950 border-rose-400 dark:bg-rose-900 dark:text-rose-50 dark:border-rose-500"
         ),
         (
             "COUPLE",
             "Couple",
             "CP",
             "bg-pink-100 text-pink-950 border-pink-400 dark:bg-pink-900 dark:text-pink-50 dark:border-pink-500"
         ),
         (
             "WHEELCHAIR",
             "Wheelchair space",
             "W",
             "bg-emerald-100 text-emerald-950 border-emerald-500 dark:bg-emerald-900 dark:text-emerald-50 dark:border-emerald-500"
         ),
         (
             "COMPANION",
             "Companion",
             "CM",
             "bg-teal-100 text-teal-950 border-teal-400 dark:bg-teal-900 dark:text-teal-50 dark:border-teal-500"
         ),
         (
             "SOFA",
             "Sofa",
             "SF",
             "bg-orange-100 text-orange-950 border-orange-400 dark:bg-orange-900 dark:text-orange-50 dark:border-orange-500"
         ),
         (
             "BLOCKED",
             "Blocked (not sold)",
             "X",
             "bg-muted text-muted-foreground border-border"
         ),
         (
             "HOUSE",
             "House seat (not sold)",
             "H",
             "bg-zinc-200 text-zinc-900 border-zinc-500 dark:bg-zinc-700 dark:text-zinc-50 dark:border-zinc-400"
         )
     ];

glob UNSOLD: list[str] = ["BLOCKED", "HOUSE"],
     LETTERS: str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

def:pub kind_of(seat_type: str) -> tuple[str, str, str, str] {
    for kind in SEAT_KINDS {
        if kind[0] == seat_type {
            return kind;
        }
    }
    return SEAT_KINDS[0];
}

def:pub row_letters(index: int) -> str {
    # 0 -> "A", 25 -> "Z", 26 -> "AA", 27 -> "AB".
    if index < 26 {
        return LETTERS[index];
    }
    return LETTERS[int(index / 26) - 1] + LETTERS[index % 26];
}

def:pub cell_key(row: int, col: int) -> str {
    return f"{row}:{col}";
}

def:pub label_at(cells: dict[str, str], row: int, col: int) -> str {
    # The label of the seat in (row, col): its row letter and its number among the
    # row's seats counted from the left.
    count = 0;
    for c in range(col + 1) {
        if cell_key(row, c) in cells {
            count += 1;
        }
    }
    return f"{row_letters(row)}{count}";
}

def:pub seats_from_cells(
    cells: dict[str, str], rows: int, cols: int
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The seats to save, row by row, left to right, labelled.
    seats: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for r in range(rows) {
        number = 0;
        for c in range(cols) {
            key = cell_key(r, c);
            if key in cells {
                number += 1;
                seats.append(
                    {
                        "label": f"{row_letters(r)}{number}",
                        "row": r,
                        "col": c,
                        "seat_type": cells[key]
                    }
                );
            }
        }
    }
    return seats;
}

def:pub cells_from_seats(seats: list[dict[str, any]]) -> dict[str, str] {  # jac:ignore[W1037]
    cells: dict[str, str] = {};
    for s in seats {
        cells[cell_key(s["row"], s["col"])] = s["seat_type"];
    }
    return cells;
}

def:pub inside(cells: dict[str, str], rows: int, cols: int) -> dict[str, str] {
    # The cells that still fit a grid of rows x cols.
    kept: dict[str, str] = {};
    for key in cells {
        parts = key.split(":");
        if int(parts[0]) < rows and int(parts[1]) < cols {
            kept[key] = cells[key];
        }
    }
    return kept;
}

# Dicts are iterated with plain for loops in this client code: a comprehension over a
# dict compiles to array methods (.map/.filter) that a JS object doesn't have (JI-032).

def:pub sellable(cells: dict[str, str]) -> int {
    count = 0;
    for key in cells {
        if cells[key] not in UNSOLD {
            count += 1;
        }
    }
    return count;
}

def:pub seat_types_in(cells: dict[str, str]) -> list[str] {
    found: list[str] = [];
    for key in cells {
        if cells[key] not in found {
            found.append(cells[key]);
        }
    }
    return found;
}

def:pub without(cells: dict[str, str], removed: str) -> dict[str, str] {
    # A copy of `cells` without the cell `removed`.
    kept: dict[str, str] = {};
    for key in cells {
        if key != removed {
            kept[key] = cells[key];
        }
    }
    return kept;
}

def:pub clamp(value: int, low: int, high: int) -> int {
    return max(low, min(high, value));
}
