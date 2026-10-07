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

def _split(label: str) -> list[str] {
    # "AA12" -> ["AA", "12"]: the row part and the trailing number.
    cut = len(label);
    while cut > 0 and label[cut - 1] in "0123456789" {
        cut -= 1;
    }
    return [label[:cut], label[cut:]];
}

def:pub seat_number(label: str) -> str {
    # What a seat shows: its number ("12" for "AA12"), or its whole label if it has none.
    number = _split(label)[1];
    return number if len(number) > 0 else label;
}

def:pub row_names(seats: list[dict[str, any]], rows: int) -> list[str] {  # jac:ignore[W1037]
    # The name of each row, from its seats' labels ("A" for A1..A12); "" for a row
    # without seats.
    names: list[str] = [];
    for r in range(rows) {
        names.append("");
    }
    for s in seats {
        if names[s["row"]] == "" {
            names[s["row"]] = _split(s["label"])[0];
        }
    }
    return names;
}

def:pub phone_digits(text: str) -> str {
    # What a customer typed, as digits: spaces, dashes and a leading + dropped.
    out = "";
    for ch in text {
        if ch in "0123456789" {
            out += ch;
        } elif ch not in " -+" {
            return "";
        }
    }
    return out;
}

def:pub phone_problem(text: str) -> str {
    # Why this isn't an M-Pesa number ("" if it is), as the server checks it
    # (core/payments/phone.jac): 07.. / 01.. (10 digits), 2547.. / 2541.. (12), or 7.. /
    # 1.. (9).
    wanted = "Enter your M-Pesa number, like 0712 345 678.";
    if len(text.strip()) == 0 {
        return wanted;
    }
    digits = phone_digits(text);
    if len(digits) == 10 and digits[0] == "0" {
        digits = "254" + digits[1:];
    } elif len(digits) == 9 {
        digits = "254" + digits;
    }
    if len(digits) != 12
        or digits[:3] != "254"
        or (digits[3] != "7" and digits[3] != "1") {
        return wanted;
    }
    return "";
}

def:pub email_problem(text: str) -> str {
    # Why this isn't an address for the tickets ("" if it is), as the server checks it
    # (core/notify/addresses.jac): a local part and a dotted domain, no spaces.
    wanted = "Enter the email address for your tickets, like name@example.com.";
    address = text.strip();
    parts: list[str] = address.split("@");
    if len(address) == 0 or len(address) > 254 or len(parts) != 2 or " " in address {
        return wanted;
    }
    labels: list[str] = parts[1].lower().split(".");
    if len(parts[0]) == 0 or len(labels) < 2 or len(labels[len(labels) - 1]) < 2 {
        return wanted;
    }
    for label in labels {
        if len(label) == 0 {
            return wanted;
        }
        for ch in label {
            if ch not in "abcdefghijklmnopqrstuvwxyz0123456789-" {
                return wanted;
            }
        }
    }
    return "";
}
