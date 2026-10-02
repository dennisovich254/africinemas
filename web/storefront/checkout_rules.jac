"""How checkout words and moves things (P4.6): money, the hold's countdown, each seat's
words for screen readers, moving between seats with the arrow keys, and the ids the
browser keeps for the visit.

The visitor is anonymous (ADR-0010): the browser names them with a random holder id
kept in sessionStorage for the visit, and makes a new idempotency key for each order it
starts (architecture §26). Storage can be unavailable (private windows): then the id
lasts until the page is reloaded.
"""

glob HOLDER_KEY: str = "africinemas:holder",
     MOVES: dict[str, list[int]] = {
         "ArrowUp": [-1, 0],
         "ArrowDown": [1, 0],
         "ArrowLeft": [0, -1],
         "ArrowRight": [0, 1]
     };

def _two(n: int) -> str {
    return ("0" if n < 10 else "") + str(n);
}

def _grouped(n: int) -> str {
    # 1560 -> "1,560".
    text = str(n);
    out = "";
    while len(text) > 3 {
        out = "," + text[len(text) - 3:] + out;
        text = text[:len(text) - 3];
    }
    return text + out;
}

def:pub money(cents: int, currency: str) -> str {
    # "KES 1,560" (whole units when there are no cents), "KES 12.50" otherwise.
    whole = int(cents / 100);
    rest = cents - whole * 100;
    if rest == 0 {
        return f"{currency} {_grouped(whole)}";
    }
    return f"{currency} {_grouped(whole)}.{_two(rest)}";
}

def:pub countdown(seconds: int) -> str {
    # "7:59"; never below "0:00".
    left = max(0, seconds);
    minutes = int(left / 60);
    return f"{minutes}:{_two(left - minutes * 60)}";
}

def:pub seconds_until(when: str, now_ms: int) -> int {
    if not when {
        return 0;
    }
    return int((new(Date, when).getTime() - now_ms) / 1000);  # jac:ignore[W2001]
}

def:pub seat_words(seat: dict[str, any], chosen: bool) -> str {  # jac:ignore[W1037]
    # "Seat A1, Gold, available" / "Seat A2, your seat" / "Seat A3, sold".
    kind = ""
        if seat["seat_type"] in ["STANDARD", ""]
        else seat["seat_type"].toLowerCase();
    parts: list[str] = [f"Seat {seat['label']}"];
    if seat["zone"] {
        parts.append(seat["zone"]);
    }
    if kind {
        parts.append(kind);
    }
    parts.append("your seat" if chosen else seat["text"].toLowerCase());
    return ", ".join(parts);
}

def:pub next_seat(
    seats: list[dict[str, any]],  # jac:ignore[W1037]
    label: str,
    key: str,
    rows: int,
    cols: int
) -> str {
    # The seat the arrow `key` moves to from `label`: the nearest one in that direction,
    # skipping gaps; `label` itself at the edge. Seats that aren't for sale count too, so
    # the cursor moves the way the eye does.
    if key not in MOVES {
        return label;
    }
    step = MOVES[key];
    at: dict[str, any] | None = None;  # jac:ignore[W1037]
    for s in seats {
        if s["label"] == label {
            at = s;
        }
    }
    if at is None {
        return label;
    }
    row = at["row"] + step[0];
    col = at["col"] + step[1];
    while 0 <= row and row < rows and 0 <= col and col < cols {
        for s in seats {
            if s["row"] == row and s["col"] == col {
                return s["label"];
            }
        }
        row += step[0];
        col += step[1];
    }
    return label;
}

def _random_id(prefix: str) -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    try {
        return f"{prefix}-{win.crypto.randomUUID()}";
    } except Exception {
        return f"{prefix}-{win.Date.now()}-{int(win.Math.random() * 1000000000)}";  # jac:ignore[W6001]
    }
}

def:pub visitor_id -> str {
    # The holder id for this visit, made on first use.
    win: any = window;  # jac:ignore[W1037,W2001]
    try {
        kept = win.sessionStorage.getItem(HOLDER_KEY);
        if kept {
            return kept;
        }
        made = _random_id("visitor");
        win.sessionStorage.setItem(HOLDER_KEY, made);
        return made;
    } except Exception {
        if not win.__africinemasHolder {
            win.__africinemasHolder = _random_id("visitor");
        }
        return win.__africinemasHolder;
    }
}

def:pub order_key -> str {
    # A fresh idempotency key for an order the visitor starts.
    return _random_id("order");
}
