"""The storefront seat map (P4.6): a showtime's seats, to choose from.

Seats sit where the cinema's layout puts them, with the screen at the top. Each state
has a shape and words as well as a colour (architecture §102): available seats are
outlined, the visitor's own are filled with a tick, held ones with a clock, sold ones
with a cross; seats not for sale are faint and can't be chosen. The legend says the same
in words, and every seat's name says it to screen readers.

On a phone the map first fits the width, as an overview (a big hall's seats are small);
the zoom buttons give full-size seats (up to 44 px), and the map then scrolls sideways
inside its own box, never the page. Keyboard users tab into the map
once and move between seats with the arrow keys; Enter or Space chooses a seat.
"""

import from react { useState }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Tick02Icon,
    Cancel01Icon,
    Clock01Icon,
    PlusSignIcon,
    MinusSignIcon
}
import from ...components.ui.button { Button }
import from .checkout_rules { seat_words, next_seat }
import from .showtimes { listed }

glob ZOOMS: list[str] = ["minmax(0, 2.75rem)", "2.25rem", "2.75rem"],
     SEAT_BASE: str = "flex aspect-square w-full items-center justify-center rounded-t-lg rounded-b-sm outline-offset-2 focus-visible:outline-2 focus-visible:outline-ring",
     LOOKS: dict[str, str] = {
         "available": "cursor-pointer border-2 border-[var(--ac-seat-available)] bg-transparent hover:bg-[var(--ac-seat-available)]/15",
         "chosen": "cursor-pointer bg-[var(--ac-seat-selected)] text-[var(--ac-on-seat-selected)]",
         "held": "cursor-not-allowed bg-[var(--ac-seat-held)] text-white",
         "sold": "cursor-not-allowed bg-[var(--ac-seat-sold)] text-muted-foreground",
         "not_for_sale": "border border-dashed border-border opacity-60"
     };

def _look(seat: dict[str, any], chosen: list[str]) -> str {  # jac:ignore[W1037]
    if listed(seat["label"], chosen) {
        return "chosen";
    }
    return seat["state"];
}

def SeatIcon(look: str) -> JsxElement {
    if look == "chosen" {
        return
            <HugeiconsIcon
                icon={Tick02Icon}
                strokeWidth={2.5}
                className="size-3.5"
                aria-hidden="true"
            />;
    }
    if look == "held" {
        return
            <HugeiconsIcon
                icon={Clock01Icon}
                strokeWidth={2}
                className="size-3"
                aria-hidden="true"
            />;
    }
    if look == "sold" {
        return
            <HugeiconsIcon
                icon={Cancel01Icon}
                strokeWidth={2.5}
                className="size-3"
                aria-hidden="true"
            />;
    }
    return <span/>;
}

def:pub SeatLegend -> JsxElement {
    return
        <ul
            data-testid="seat-legend"
            className="flex flex-wrap gap-x-4 gap-y-2 text-sm text-muted-foreground"
        >
            {[
                <li key={look} className="flex items-center gap-2">
                    <span
                        aria-hidden="true"
                        className={f"{SEAT_BASE} size-5 {LOOKS[look]}"}
                    >
                        <SeatIcon look={look}/>
                    </span>
                    {words}
                </li>
                for (look, words) in [
                    ("available", "Available"),
                    ("chosen", "Your seats"),
                    ("held", "Held"),
                    ("sold", "Sold"),
                    ("not_for_sale", "Not for sale")
                ]
            ]}
        </ul>;
}

def:pub SeatMap(
    seat_map: dict[str, any],  # jac:ignore[W1037]
    chosen: list[str],
    on_toggle: any,  # jac:ignore[W1037]
    locked: bool = False
) -> JsxElement {
    seats: list[dict[str, any]] = seat_map["seats"];  # jac:ignore[W1037]
    rows: int = seat_map["rows"];
    cols: int = seat_map["cols"];
    [zoom, set_zoom] = useState(0);
    [cursor, set_cursor] = useState("");
    first: str = seats[0]["label"] if seats else "";
    at: str = cursor or first;

    def move(label: str, e: any) {  # jac:ignore[W1037]
        target = next_seat(seats, label, e.key, rows, cols);
        if target == label {
            return;
        }
        e.preventDefault();
        set_cursor(target);
        el: any = document.querySelector(  # jac:ignore[W1037,W2001]
            f'[data-testid="seat-map"] [data-seat="{target}"]'
        );
        if el {
            el.focus();
        }
    }

    def choose(seat: dict[str, any]) {  # jac:ignore[W1037]
        set_cursor(seat["label"]);
        look = _look(seat, chosen);
        if locked or (look != "available" and look != "chosen") {
            return;
        }
        on_toggle(seat["label"]);
    }

    cells: list[any] = [];  # jac:ignore[W1037]
    taken: list[str] = [];
    for s in seats {
        taken.append(f"{s['row']}:{s['col']}");
    }
    for r in range(rows) {
        for c in range(cols) {
            if not listed(f"{r}:{c}", taken) {
                cells.append(
                    <span
                        key={f"gap-{r}-{c}"}
                        aria-hidden="true"
                        style={{"gridRow": r + 1, "gridColumn": c + 1}}
                    />
                );
            }
        }
    }
    for s in seats {
        look = _look(s, chosen);
        seat: dict[str, any] = s;  # jac:ignore[W1037]
        cells.append(
            <button
                key={seat["label"]}
                type="button"
                data-testid="seat"
                data-seat={seat["label"]}
                data-state={look}
                aria-label={seat_words(seat, look == "chosen")}
                aria-pressed={look == "chosen"
                    if look in ["available", "chosen"]
                    else None}
                aria-disabled={"true"
                    if locked or look not in ["available", "chosen"]
                    else None}
                tabIndex={0 if seat["label"] == at else -1}
                style={{"gridRow": seat["row"] + 1, "gridColumn": seat["col"] + 1}}
                className={f"{SEAT_BASE} {LOOKS[look]}"}
                onClick={lambda { choose(seat); }}
                onFocus={lambda { set_cursor(seat["label"]); }}
                onKeyDown={lambda (e: any) { move(seat["label"], e); }}  # jac:ignore[W1037]
            >
                <SeatIcon look={look}/>
            </button>
        );
    }
    return
        <div data-testid="seat-map" className="flex flex-col gap-3">
            <div className="flex items-center justify-between gap-3">
                <h3 className="text-lg font-semibold">Choose your seats</h3>
                <div className="flex items-center gap-2">
                    <Button
                        variant="outline"
                        data-testid="zoom-out"
                        aria-label="Smaller seats"
                        disabled={zoom == 0}
                        onClick={lambda { set_zoom(max(0, zoom - 1)); }}
                        className="size-11"
                    >
                        <HugeiconsIcon
                            icon={MinusSignIcon}
                            strokeWidth={2}
                            aria-hidden="true"
                        />
                    </Button>
                    <Button
                        variant="outline"
                        data-testid="zoom-in"
                        aria-label="Bigger seats"
                        disabled={zoom == len(ZOOMS) - 1}
                        onClick={lambda { set_zoom(min(len(ZOOMS) - 1, zoom + 1)); }}
                        className="size-11"
                    >
                        <HugeiconsIcon
                            icon={PlusSignIcon}
                            strokeWidth={2}
                            aria-hidden="true"
                        />
                    </Button>
                </div>
            </div>
            <div
                data-testid="seat-scroller"
                className="overflow-x-auto overscroll-x-contain rounded-lg border bg-card px-3 pt-4 pb-5"
            >
                <div
                    className={"mx-auto flex flex-col items-center gap-5 "
                        + ("w-full" if zoom == 0 else "w-max")}
                >
                    <div className="flex w-full max-w-md flex-col items-center gap-1">
                        <div
                            aria-hidden="true"
                            className="h-1.5 w-full rounded-full bg-muted-foreground/40"
                        />
                        <p
                            className="text-xs tracking-widest text-muted-foreground uppercase"
                        >
                            Screen
                        </p>
                    </div>
                    <div
                        role="group"
                        aria-label="Seats. Use the arrow keys to move between seats."
                        data-zoom={zoom}
                        className={"grid "
                            + ("w-full gap-1" if zoom == 0 else "gap-1.5")}
                        style={{
                            "gridTemplateColumns": f"repeat({cols}, {ZOOMS[zoom]})",
                            "gridTemplateRows": f"repeat({rows}, auto)",
                            "maxWidth": f"calc({cols} * 2.75rem + {cols - 1} * 0.25rem)"
                                if zoom == 0
                                else "none"
                        }}
                    >
                        {cells}
                    </div>
                </div>
            </div>
            <SeatLegend/>
        </div>;
}
