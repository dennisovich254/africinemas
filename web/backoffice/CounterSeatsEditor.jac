"""Choosing the seats kept for the counter (2026-10-30, core/booking/counter_seats.jac).

The screen's seat map (the storefront's SeatMap): tap a seat to keep it for the counter
or give it back to online sale, then Save. Ticked seats are the counter's. Used on a
screen's page (every showtime there) and on a showtime (just that one). `load` and
`save` are the page's endpoints: each answers {"rows", "cols", "seats": [{"label",
"row", "col", "seat_type", "counter", "sellable"}]}.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from ..storefront.SeatMap { SeatMap }
import from core.catalog.screening_api {
    showtime_counter_seats,  # jac:ignore[W2037] authenticated endpoint
    set_showtime_counter_seats  # jac:ignore[W2037] authenticated endpoint
}

def _picked(grid: any) -> list[str] {  # jac:ignore[W1037]
    return [
        s["label"]
        for s in grid["seats"]
        if s["counter"]
    ];
}

def _as_map(grid: any) -> dict[str, any] {  # jac:ignore[W1037]
    # The grid as SeatMap draws it: sellable seats can be ticked, the rest can't.
    return {
        "rows": grid["rows"],
        "cols": grid["cols"],
        "seats": [
            {
                "label": s["label"],
                "row": s["row"],
                "col": s["col"],
                "seat_type": s["seat_type"],
                "zone": "",
                "state": "available" if s["sellable"] else "not_for_sale",
                "text": "Online" if s["sellable"] else "Not for sale"
            } for s in grid["seats"]
        ]
    };
}

def:pub CounterSeatsEditor(
    load: any,  # jac:ignore[W1037] async () -> the grid
    save: any,  # jac:ignore[W1037] async (labels) -> the grid
    note: str,
    testid: str
) -> JsxElement {
    [grid, set_grid] = useState(None);
    [picked, set_picked] = useState([]);
    [busy, set_busy] = useState(False);
    [said, set_said] = useState("");
    [problem, set_problem] = useState("");

    def shown(got: any) {  # jac:ignore[W1037]
        set_grid(got);
        set_picked(_picked(got));
    }

    async def start_loading {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await load();
        } except Exception as e {
            console.warn("counter seats failed", e);
        }
        if got is not None and got["ok"] {
            shown(got);
        } else {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't load the seats. Reload the page to try again."
            );
        }
    }

    def first {
        start_loading();
    }
    useEffect(first, []);

    def toggle(label: str) {
        mine: list[str] = picked;
        set_said("");
        if label in mine {
            set_picked(
                [
                    l
                    for l in mine
                    if l != label
                ]
            );
        } else {
            set_picked(mine + [label]);
        }
    }

    async def keep {
        set_busy(True);
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await save(picked);
        } except Exception as e {
            console.warn("saving counter seats failed", e);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't save that. Try again."
            );
            return;
        }
        shown(got);
        count = len(_picked(got));
        set_said(
            "Saved: no seats kept for the counter."
                if count == 0
                else f"Saved: {count} {'seat'
                    if count == 1
                    else 'seats'} kept for the counter."
        );
    }

    found: dict[str, any] | None = grid;  # jac:ignore[W1037]
    mine: list[str] = picked;
    if found is None {
        if problem {
            return <p role="alert" className="text-sm text-destructive">{problem}</p>;
        }
        return <Spinner aria-label="Loading"/>;
    }
    return
        <section className="flex flex-col gap-3" data-testid={testid}>
            <p className="text-sm text-muted-foreground">{note}</p>
            <p className="text-sm font-medium" data-testid="counter-seats-count">
                {f"{len(mine)} {'seat'
                    if len(mine) == 1
                    else 'seats'} kept for the counter"
                    + (f": {', '.join(sorted(mine))}" if len(mine) > 0 else "")}
            </p>
            <SeatMap seat_map={_as_map(found)} chosen={mine} on_toggle={toggle}/>
            <div className="flex flex-wrap items-center gap-3">
                <Button className="min-h-11" disabled={busy} onClick={keep}>
                    {"Saving…" if busy else "Save counter seats"}
                </Button>
                <p role="status" className="text-sm empty:hidden">{said}</p>
            </div>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </section>;
}

def:pub ShowtimeCounterSeats(slug: str, screening_id: str) -> JsxElement {
    # One showtime's counter seats: the screen's, changed for this showtime only.
    async def load -> any {  # jac:ignore[W1037]
        return await showtime_counter_seats(slug, screening_id);  # jac:ignore[W2037]
    }
    async def save(labels: list[str]) -> any {  # jac:ignore[W1037]
        return await set_showtime_counter_seats(slug, screening_id, labels);  # jac:ignore[W2037]
    }
    return
        <CounterSeatsEditor
            load={load}
            save={save}
            note="For this showtime only. They start as the screen's counter seats; a premiere can keep more for the counter, or a quiet show fewer."
            testid="showtime-counter-editor"
        />;
}
