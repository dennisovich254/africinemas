"""`/app/:slug/screens/:auditorium_id`: the seat layout designer (P3.3).

On a tablet or computer, staff who may configure seats paint the grid: choose a seat type,
then press on a cell (or drag across cells) to place seats of that type; pressing a seat
of the chosen type, or using the Aisle tool, clears it. The grid is one Tab stop; arrow
keys move, Enter or Space paints. Seats are labelled automatically (seat_grid.jac).

Save draft writes the screen's draft; Publish (after a confirmation) freezes it. Editing
a published layout saves the next version, and screenings keep the one they were given
(P3.2). Phones, and staff who may only read seat plans, get a read-only preview.
"""

import from react { useState, useEffect, useRef }
import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowLeft01Icon, ComputerIcon }
import from ...lib.utils { cn }
import from ...components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from core.catalog.layout_api {
    list_layouts,  # jac:ignore[W2037]
    get_layout,  # jac:ignore[W2037]
    save_layout,  # jac:ignore[W2037]
    publish_layout  # jac:ignore[W2037]
}  # def:priv endpoints over the server pin (JI-027)
import from .seat_grid {
    MAX_ROWS,
    MAX_COLS,
    SEAT_KINDS,
    kind_of,
    row_letters,
    cell_key,
    label_at,
    seats_from_cells,
    cells_from_seats,
    inside,
    sellable,
    seat_types_in,
    without,
    clamp
}

glob AISLE: str = "AISLE",
     NEW_ROWS: int = 8,
     NEW_COLS: int = 12,
     WIDE_QUERY: str = "(min-width: 768px)",
     # Merged with cn() (tailwind-merge), so a smaller size passed after it wins.
     SEAT_BASE: str = "flex size-8 shrink-0 items-center justify-center rounded-t-lg rounded-b-sm border text-[10px] font-semibold leading-none",
     AISLE_BASE: str = "size-8 shrink-0 rounded-sm border border-dashed border-border";

def snapshot(rows: int, cols: int, cells: dict[str, str]) -> str {
    # A comparable summary of the layout, to tell whether there are unsaved changes.
    parts: list[str] = [];
    # A plain loop: a comprehension over a dict breaks in client code (JI-032).
    for k in cells {
        parts.append(f"{k}={cells[k]}");
    }
    parts = sorted(parts);
    return f"{rows}x{cols}|" + ",".join(parts);
}

def status_text(meta: dict[str, any] | None) -> str {  # jac:ignore[W1037]
    if meta is None {
        return "Not saved yet";
    }
    state = "Published" if meta["status"] == "published" else "Draft";
    return f"{state} · version {meta['version']}";
}

def preview_class(cells: dict[str, str], r: int, c: int) -> str {
    # A preview cell: a small seat, or an empty gap for an aisle.
    key = cell_key(r, c);
    if key in cells {
        return cn(SEAT_BASE, kind_of(cells[key])[3], "size-5 text-[8px]");
    }
    return "size-5 shrink-0";
}

def SeatGlyph(seat_type: str, small: bool = False) -> JsxElement {
    kind = kind_of(seat_type);
    size = "size-5 text-[8px]" if small else "";
    return
        <span className={cn(SEAT_BASE, kind[3], size)} aria-hidden="true">
            {kind[2]}
        </span>;
}

# The read-only view: a picture of the layout, described for screen readers in one label.
def SeatPreview(rows: int, cols: int, cells: dict[str, str]) -> JsxElement {
    summary = f"Seat layout, {rows} rows by {cols} columns, {len(cells)} seats, {sellable(
        cells
    )} for sale";
    return
        <div className="overflow-x-auto rounded-lg border bg-card p-3">
            <div
                role="img"
                aria-label={summary}
                data-testid="seat-grid"
                className="flex w-max flex-col gap-0.5"
            >
                {[
                    <div key={r} className="flex items-center gap-0.5">
                        <span
                            className="w-5 shrink-0 text-center text-[10px] text-muted-foreground"
                        >
                            {row_letters(r)}
                        </span>
                        {[
                            <span
                                key={c}
                                data-cell={cell_key(r, c)}
                                data-seat-type={cells[cell_key(r, c)]
                                    if cell_key(r, c) in cells
                                    else ""}
                                className={preview_class(cells, r, c)}
                            >
                                {kind_of(cells[cell_key(r, c)])[2]
                                    if cell_key(r, c) in cells
                                    else ""}
                            </span> for c in range(cols)
                        ]}
                    </div> for r in range(rows)
                ]}
            </div>
        </div>;
}

def Legend(cells: dict[str, str]) -> JsxElement {
    used = seat_types_in(cells);
    present = [
        kind
        for kind in SEAT_KINDS
        if kind[0] in used
    ];
    return
        <ul className="flex flex-wrap gap-x-4 gap-y-2 text-sm" aria-label="Seat types">
            {[
                <li key={kind[0]} className="flex items-center gap-2">
                    <SeatGlyph seat_type={kind[0]} small={True}/>
                    {kind[1]}
                </li> for kind in present
            ]}
        </ul>;
}

def:pub SeatDesigner(
    slug: str, auditorium_id: str, permissions: list[str]
) -> JsxElement {
    [screen, set_screen] = useState(None);
    [failed, set_failed] = useState("");
    [loaded, set_loaded] = useState(False);
    [rows, set_rows] = useState(NEW_ROWS);
    [cols, set_cols] = useState(NEW_COLS);
    [rows_text, set_rows_text] = useState(str(NEW_ROWS));
    [cols_text, set_cols_text] = useState(str(NEW_COLS));
    [cells, set_cells] = useState({});
    [saved, set_saved] = useState(snapshot(NEW_ROWS, NEW_COLS, {}));
    [meta, set_meta] = useState(None);
    [tool, set_tool] = useState("STANDARD");
    [busy, set_busy] = useState("");
    [message, set_message] = useState("");
    [problems, set_problems] = useState([]);
    [confirming, set_confirming] = useState(False);
    [focus_key, set_focus_key] = useState(cell_key(0, 0));
    [wide, set_wide] = useState(True);
    painting = useRef("");  # "set" or "clear" while a press is being dragged

    grid_cells: dict[str, str] = cells;  # jac:ignore[W1037]
    info: dict[str, any] | None = meta;  # jac:ignore[W1037]
    unsaved = snapshot(rows, cols, grid_cells) != saved;
    can_configure = "seats.configure" in permissions;
    editable = can_configure and wide;

    def show(layout: dict[str, any]) {  # jac:ignore[W1037]
        set_rows(layout["rows"]);
        set_cols(layout["cols"]);
        set_rows_text(str(layout["rows"]));
        set_cols_text(str(layout["cols"]));
        loaded_cells = cells_from_seats(layout["seats"]);
        set_cells(loaded_cells);
        set_saved(snapshot(layout["rows"], layout["cols"], loaded_cells));
        set_meta(
            {
                "layout_id": layout["layout_id"],
                "version": layout["version"],
                "status": layout["status"]
            }
        );
    }

    async def load {
        venues_answer: any = None;  # jac:ignore[W1037]
        listed: any = None;  # jac:ignore[W1037]
        got: any = None;  # jac:ignore[W1037]
        try {
            venues_answer = await list_venues(slug);  # jac:ignore[W2037]
            listed = await list_layouts(slug, auditorium_id);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("loading the layout failed", e);
            set_failed("We couldn't load this screen. Refresh the page to try again.");
            return;
        }
        if not listed["ok"] {
            set_failed(
                "This screen doesn't exist, or you can't see its seat layout."
                    if listed["error"]["code"] in ["not_found", "forbidden"]
                    else listed["error"]["message"]
            );
            return;
        }
        if venues_answer["ok"] {
            for v in venues_answer["venues"] {
                for a in v["auditoriums"] {
                    if a["auditorium_id"] == auditorium_id {
                        set_screen({"name": a["name"], "venue": v["name"]});
                    }
                }
            }
        }
        latest = listed["draft_version"] or listed["published_version"];
        if latest {
            for l in listed["layouts"] {
                if l["version"] == latest {
                    got = await get_layout(slug, l["layout_id"]);  # jac:ignore[W2037]
                    if got["ok"] {
                        show(got["layout"]);
                    }
                }
            }
        }
        set_loaded(True);
    }

    # Named functions for effects: a one-statement lambda would return its value, which
    # React calls as the cleanup (JI-028).
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, auditorium_id]);

    def watch_width -> any {  # jac:ignore[W1037]
        query: any = window.matchMedia(WIDE_QUERY);  # jac:ignore[W1037,W2001]
        set_wide(query.matches);
        handler = lambda (e: any) { set_wide(e.matches); };  # jac:ignore[W1037]
        query.addEventListener("change", handler);
        return lambda { query.removeEventListener("change", handler); };
    }
    useEffect(watch_width, []);

    def stop_painting_on_release -> any {  # jac:ignore[W1037]
        win: any = window;  # jac:ignore[W1037,W2001]
        stop = lambda { painting.current = ""; };
        win.addEventListener("pointerup", stop);
        return lambda { win.removeEventListener("pointerup", stop); };
    }
    useEffect(stop_painting_on_release, []);

    def warn_before_leaving -> any {  # jac:ignore[W1037]
        win: any = window;  # jac:ignore[W1037,W2001]
        guard = lambda (e: any) { if unsaved {  # jac:ignore[W1037]
            e.preventDefault();
            e.returnValue = "";
        }};  # jac:ignore[W1037]
        win.addEventListener("beforeunload", guard);
        return lambda { win.removeEventListener("beforeunload", guard); };
    }
    useEffect(warn_before_leaving, [unsaved]);

    def apply_paint(key: str, action: str) {
        set_message("");
        set_cells(
            lambda (prev: dict[str, str]) -> dict[str, str] {
                next_cells = without(prev, key);
                if action == "set" {
                    next_cells[key] = tool;
                }
                return next_cells;
            }
        );
    }

    def action_for(key: str) -> str {
        # Pressing a seat of the chosen type (or using the Aisle tool) clears the cell.
        if tool == AISLE or (key in grid_cells and grid_cells[key] == tool) {
            return "clear";
        }
        return "set";
    }

    def press(key: str) {
        action = action_for(key);
        painting.current = action;
        set_focus_key(key);
        apply_paint(key, action);
    }

    def drag_over(key: str) {
        if painting.current {
            apply_paint(key, painting.current);
        }
    }

    def move_focus(key: str, e: any) {  # jac:ignore[W1037]
        parts = key.split(":");
        r = int(parts[0]);
        c = int(parts[1]);
        moves = {
            "ArrowUp": (r - 1, c),
            "ArrowDown": (r + 1, c),
            "ArrowLeft": (r, c - 1),
            "ArrowRight": (r, c + 1),
            "Home": (r, 0),
            "End": (r, cols - 1)
        };
        if e.key == "Enter" or e.key == " " {
            e.preventDefault();
            apply_paint(key, action_for(key));
            return;
        }
        if e.key not in moves {
            return;
        }
        e.preventDefault();
        target = moves[e.key];
        nr = clamp(target[0], 0, rows - 1);
        nc = clamp(target[1], 0, cols - 1);
        next_key = cell_key(nr, nc);
        set_focus_key(next_key);
        el: any = document.querySelector(  # jac:ignore[W1037]
            f'[data-testid="seat-grid"] [data-cell="{next_key}"]'
        );  # jac:ignore[W1037,W2001]
        if el {
            el.focus();
        }
    }

    def resize(which: str) {
        # Apply the typed size (clamped to what a layout allows); seats that no longer
        # fit are removed.
        new_rows = clamp(int(rows_text or "1"), 1, MAX_ROWS)
            if which == "rows"
            else rows;
        new_cols = clamp(int(cols_text or "1"), 1, MAX_COLS)
            if which == "cols"
            else cols;
        set_rows(new_rows);
        set_cols(new_cols);
        set_rows_text(str(new_rows));
        set_cols_text(str(new_cols));
        set_cells(inside(grid_cells, new_rows, new_cols));
        set_focus_key(cell_key(0, 0));
    }

    async def save {
        answer: any = None;  # jac:ignore[W1037]
        set_busy("saving");
        set_message("");
        set_problems([]);
        try {
            answer = await save_layout(  # jac:ignore[W2037]
                slug,
                auditorium_id,
                rows,
                cols,
                seats_from_cells(grid_cells, rows, cols)
            );
        } except Exception as e {
            console.warn("save_layout failed", e);
            set_busy("");
            set_message("We couldn't save. Check your connection and try again.");
            return;
        }
        set_busy("");
        if answer["ok"] {
            show(answer["layout"]);
            set_message("Draft saved.");
            return;
        }
        if answer["error"]["code"] == "invalid_layout" {
            set_problems(answer["error"]["problems"]);
        }
        set_message(answer["error"]["message"]);
    }

    async def publish {
        answer: any = None;  # jac:ignore[W1037]
        set_confirming(False);
        set_busy("publishing");
        set_message("");
        set_problems([]);
        try {
            answer = await publish_layout(slug, auditorium_id);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("publish_layout failed", e);
            set_busy("");
            set_message("We couldn't publish. Check your connection and try again.");
            return;
        }
        set_busy("");
        if answer["ok"] {
            show(answer["layout"]);
            set_message(f"Published version {answer['layout']['version']}.");
            return;
        }
        if answer["error"]["code"] == "invalid_layout" {
            set_problems(answer["error"]["problems"]);
        }
        set_message(answer["error"]["message"]);
    }

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if not loaded {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading the seat layout…
            </p>;
    }
    names: dict[str, str] | None = screen;  # jac:ignore[W1037]
    heading = (
        f"{names['name']} · {names['venue']}" if names is not None else "Seat layout"
    );
    published = info is not None and info["status"] == "published";
    draft_ready = info is not None and info["status"] == "draft" and not unsaved;
    next_version = (info["version"] + 1) if info is not None else 1;

    header = <div className="flex flex-col gap-3">
        <Link
            to={f"/app/{slug}/screens"}
            className="inline-flex min-h-11 w-fit items-center gap-1 text-sm font-medium text-muted-foreground hover:text-foreground"
        >
            <HugeiconsIcon icon={ArrowLeft01Icon} strokeWidth={2} aria-hidden="true"/>
            Screens
        </Link>
        <div className="flex flex-wrap items-center gap-3">
            <h2 className="text-xl font-semibold">{heading}</h2>
            <Badge
                variant={"default" if published else "secondary"}
                data-testid="layout-status"
            >
                {status_text(info)}
            </Badge>
            <span className="text-sm text-muted-foreground" data-testid="seat-count">
                {len(grid_cells)} seats · {sellable(grid_cells)} for sale
            </span>
        </div>
    </div>;

    if not editable {
        note: any = None;  # jac:ignore[W1037]
        if not wide {
            note = <Alert data-testid="larger-screen-notice">
                <HugeiconsIcon icon={ComputerIcon} strokeWidth={2} aria-hidden="true"/>
                <AlertTitle>Use a larger screen to edit</AlertTitle>
                <AlertDescription>
                    Seat layouts are edited on a tablet or computer. Here's the current layout.
                </AlertDescription>
            </Alert>;
        } else {
            note = <p
                className="text-sm text-muted-foreground"
                data-testid="read-only-note"
            >
                You can view this layout but can't change it. Owners and admins edit seat layouts.
            </p>;
        }
        return
            <div className="flex flex-col gap-5" data-testid="seat-designer">
                {header}
                {note}
                {len(grid_cells) > 0
                    and <SeatPreview rows={rows} cols={cols} cells={grid_cells}/>}
                {len(grid_cells) == 0
                    and <p className="text-muted-foreground">
                        This screen has no seat layout yet.
                    </p>}
                <Legend cells={grid_cells}/>
            </div>;
    }

    tools = <div
        role="group"
        aria-label="Seat type"
        data-testid="seat-tools"
        className="flex flex-wrap gap-2"
    >
        {[
            <Button
                key={kind[0]}
                variant="outline"
                className="h-10 gap-2 px-3 aria-pressed:border-foreground aria-pressed:bg-muted"
                aria-pressed={"true" if tool == kind[0] else "false"}
                data-tool={kind[0]}
                onClick={lambda { set_tool(kind[0]); }}
            >
                <SeatGlyph seat_type={kind[0]} small={True}/>
                {kind[1]}
            </Button> for kind in SEAT_KINDS
        ]}
        <Button
            variant="outline"
            className="h-10 gap-2 px-3 aria-pressed:border-foreground aria-pressed:bg-muted"
            aria-pressed={"true" if tool == AISLE else "false"}
            data-tool={AISLE}
            onClick={lambda { set_tool(AISLE); }}
        >
            <span className={f"{AISLE_BASE} size-5"} aria-hidden="true"/>
            Aisle (clear)
        </Button>
    </div>;

    size_controls = <div className="flex flex-wrap items-end gap-4">
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="layout-rows">Rows</Label>
            <Input
                id="layout-rows"
                type="number"
                min={1}
                max={MAX_ROWS}
                value={rows_text}
                onChange={lambda (e: any) { set_rows_text(e.target.value); }}  # jac:ignore[W1037]
                onBlur={lambda { resize("rows"); }}
                onKeyDown={lambda (e: any) { if e.key == "Enter" { resize("rows"); }}}  # jac:ignore[W1037]
                className="h-10 w-24"
            />
        </div>
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="layout-cols">Columns</Label>
            <Input
                id="layout-cols"
                type="number"
                min={1}
                max={MAX_COLS}
                value={cols_text}
                onChange={lambda (e: any) { set_cols_text(e.target.value); }}  # jac:ignore[W1037]
                onBlur={lambda { resize("cols"); }}
                onKeyDown={lambda (e: any) { if e.key == "Enter" { resize("cols"); }}}  # jac:ignore[W1037]
                className="h-10 w-24"
            />
        </div>
        <p className="pb-2 text-sm text-muted-foreground">
            Up to {MAX_ROWS} rows and {MAX_COLS} columns. Making the grid smaller removes the seats outside it.
        </p>
    </div>;

    grid = <div className="overflow-x-auto rounded-lg border bg-card p-4">
        <div className="flex w-max flex-col gap-1">
            <div
                className="mb-3 ml-7 rounded-sm bg-muted py-1 text-center text-xs font-medium tracking-widest text-muted-foreground uppercase"
                aria-hidden="true"
            >
                Screen
            </div>
            <div
                role="grid"
                aria-label="Seat layout editor"
                data-testid="seat-grid"
                className="flex flex-col gap-1 select-none"
            >
                {[
                    <div key={r} role="row" className="flex items-center gap-1">
                        <span
                            role="rowheader"
                            className="w-6 shrink-0 text-center text-xs text-muted-foreground"
                        >
                            {row_letters(r)}
                        </span>
                        {[
                            <span key={c} role="gridcell">
                                <button
                                    type="button"
                                    data-cell={cell_key(r, c)}
                                    data-seat-type={grid_cells[cell_key(r, c)]
                                        if cell_key(r, c) in grid_cells
                                        else ""}
                                    tabIndex={0 if cell_key(r, c) == focus_key else -1}
                                    aria-label={(
                                        f"{label_at(grid_cells, r, c)}, {kind_of(
                                            grid_cells[cell_key(r, c)]
                                        )[1]}"
                                            if cell_key(r, c) in grid_cells
                                            else f"Row {row_letters(r)}, column {c
                                                + 1}, aisle"
                                    )}
                                    className={(
                                        f"{SEAT_BASE} {kind_of(
                                            grid_cells[cell_key(r, c)]
                                        )[3]}"
                                            if cell_key(r, c) in grid_cells
                                            else AISLE_BASE
                                    )
                                        + " cursor-pointer outline-offset-2 focus-visible:outline-2 focus-visible:outline-ring"}
                                    onPointerDown={lambda (e: any) {  # jac:ignore[W1037]
                                        e.preventDefault();
                                        press(cell_key(r, c));
                                    }}
                                    onPointerEnter={lambda { drag_over(
                                        cell_key(r, c)
                                    ); }}
                                    onFocus={lambda { set_focus_key(cell_key(r, c)); }}
                                    onKeyDown={lambda (e: any) { move_focus(  # jac:ignore[W1037]
                                        cell_key(r, c), e
                                    ); }}  # jac:ignore[W1037]
                                    onClick={lambda (e: any) {  # jac:ignore[W1037]
                                    # Clicks from assistive tech (no pointer press) paint too.
                                    if e.detail == 0 {
                                        apply_paint(
                                            cell_key(r, c), action_for(cell_key(r, c))
                                        );
                                    }}}
                                >
                                    {kind_of(grid_cells[cell_key(r, c)])[2]
                                        if cell_key(r, c) in grid_cells
                                        else ""}
                                </button>
                            </span> for c in range(cols)
                        ]}
                    </div> for r in range(rows)
                ]}
            </div>
        </div>
    </div>;

    actions = <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-3">
            <Button
                className="min-h-11 px-5"
                disabled={busy != "" or not unsaved}
                onClick={save}
            >
                {busy == "saving" and <Spinner aria-hidden="true"/>}{"Saving…"
                    if busy == "saving"
                    else "Save draft"}
            </Button>
            <Button
                variant="outline"
                className="min-h-11 px-5"
                disabled={busy != "" or not draft_ready}
                onClick={lambda { set_confirming(True); }}
            >
                {busy == "publishing" and <Spinner aria-hidden="true"/>}{"Publishing…"
                    if busy == "publishing"
                    else "Publish"}
            </Button>
            {unsaved
                and <span
                    className="text-sm text-muted-foreground"
                    data-testid="unsaved-note"
                >
                    {(
                        f"Unsaved changes. Saving creates version {next_version}; screenings keep version {info[
                            'version'
                        ]}."
                            if published
                            else "Unsaved changes."
                    )}
                </span>}
            {info is not None
                and info["status"] == "draft"
                and unsaved
                and <span className="sr-only">
                    Save your changes before publishing.
                </span>}
        </div>
        {confirming
            and <div
                className="flex flex-col gap-3 rounded-lg border p-4"
                data-testid="publish-confirm"
                role="group"
                aria-labelledby="publish-confirm-title"
            >
                <p id="publish-confirm-title" className="font-medium">
                    Publish version {info["version"]}?
                </p>
                <p className="text-sm text-muted-foreground">
                    New screenings will use this layout, and it can't be changed afterwards. To change it later, you'll save a new version; screenings keep the version they were given.
                </p>
                <div className="flex flex-wrap gap-3">
                    <Button className="min-h-11 px-5" onClick={publish}>
                        Publish version {info["version"]}
                    </Button>
                    <Button
                        variant="ghost"
                        className="min-h-11 px-5"
                        onClick={lambda { set_confirming(False); }}
                    >
                        Cancel
                    </Button>
                </div>
            </div>}
        <p
            role="status"
            aria-live="polite"
            className="text-sm"
            data-testid="save-message"
        >
            {message}
        </p>
        {len(problems) > 0
            and <Alert variant="destructive">
                <AlertTitle>Fix these before saving</AlertTitle>
                <AlertDescription>
                    <ul className="list-disc pl-4">
                        {[
                            <li key={i}>{p["message"]}</li>
                            for (i, p) in enumerate(problems)
                        ]}
                    </ul>
                </AlertDescription>
            </Alert>}
    </div>;

    return
        <div className="flex flex-col gap-5" data-testid="seat-designer">
            {header}{size_controls}{tools}{grid}{actions}
        </div>;
}
