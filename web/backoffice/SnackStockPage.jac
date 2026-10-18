"""`/app/:slug/snacks/stock`: stock levels, adjustments and history (P12.4; design guide §8).

For the venue chosen (staff who work at more than one pick it): every tracked variant
with on hand, reserved, available and its status (Low, Out), with a "Low or out only"
filter. "Adjust" opens a small form in the row: the reason (received, damaged, count
correction, other), the quantity (for a count, the counted total; for other, + or −) and
a note, with the stock after the change shown before saving. "Alerts" sets the low-stock
alert and what happens at zero (stop selling, or keep selling for snacks made to order).
Stock history lists the latest movements: what changed, why, by whom and when.

Who can do what follows the server: adjusting and alerts need concessions.inventory at
that venue; everyone with snack access can read.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.snacks.inventory_api {
    snack_stock_levels,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    snack_stock_history,  # jac:ignore[W2037]
    adjust_snack_stock,  # jac:ignore[W2037]
    set_snack_stock_rules  # jac:ignore[W2037]
}
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from ..shell.AppLink { AppLink }
import from .form_parts { TextField, FieldError, submit_with, on_input }
import from .snack_view { SnackSubnav, snack_path, whole_number, with_field }

glob REASONS: list[tuple[str, str]] = [
         ("received", "Stock received"),
         ("damaged", "Damaged items"),
         ("count", "Count correction"),
         ("other", "Other")
     ],
     REASON_WORDS: dict[str, str] = {
         "received": "Received",
         "damaged": "Damaged",
         "count": "Count correction",
         "other": "Other",
         "sale": "Sold"
     },
     SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm";

def:pub after_change(reason: str, quantity: int, on_hand: int) -> int {
    # The stock after an adjustment, as the server will make it (for the preview).
    if reason == "received" {
        return on_hand + quantity;
    }
    if reason == "damaged" {
        return on_hand - quantity;
    }
    if reason == "count" {
        return quantity;
    }
    return on_hand + quantity;
}

def:pub int_of(text: str) -> any {  # jac:ignore[W1037]
    # "12", "-3", "+5" as a whole number, or None.
    # Browser-safe: no str.isdigit or lstrip(chars) in the client runtime.
    cleaned = text.strip();
    if cleaned.startswith("+") {
        cleaned = cleaned[1:];
    }
    negative = cleaned.startswith("-");
    value = whole_number(cleaned[1:] if negative else cleaned, -1);
    if value == -1 {
        return None;
    }
    return 0 - value if negative else value;
}

def:pub SnackStockPage(slug: str, permissions: list[str]) -> JsxElement {
    can_adjust = "concessions.inventory" in permissions;
    [venues, set_venues] = useState(None);
    [venue, set_venue] = useState("");
    [levels, set_levels] = useState(None);
    [history, set_history] = useState([]);
    [low_only, set_low_only] = useState(False);
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [message, set_message] = useState("");
    [errors, set_errors] = useState({});
    [open_row, set_open_row] = useState("");
    [mode, set_mode] = useState("");
    [form, set_form] = useState(
        {
            "reason": "received",
            "quantity": "",
            "note": "",
            "low": "0",
            "at_zero": "unavailable"
        }
    );

    async def load_venues {
        places: any = None;  # jac:ignore[W1037]
        try {
            places = await list_venues(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_venues failed", e);
            set_failed("We couldn't load your venues. Refresh the page to try again.");
            return;
        }
        if not places["ok"] {
            set_failed(places["error"]["message"]);
            return;
        }
        found = [{"id": v["venue_id"], "name": v["name"]} for v in places["venues"]];
        set_venues(found);
        if found {
            set_venue(found[0]["id"]);
        }
    }

    def start_venues {
        load_venues();
    }
    useEffect(start_venues, [slug]);

    async def load {
        if not venue {
            return;
        }
        got: any = None;  # jac:ignore[W1037]
        moves: any = None;  # jac:ignore[W1037]
        try {
            got = await snack_stock_levels(slug, venue);  # jac:ignore[W2037]
            moves = await snack_stock_history(slug, venue, "", 50);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("loading stock failed", e);
            set_failed("We couldn't load the stock. Refresh the page to try again.");
            return;
        }
        if not got["ok"] {
            set_failed(got["error"]["message"]);
            return;
        }
        set_levels(got["levels"]);
        set_history(moves["movements"] if moves["ok"] else []);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [venue]);

    values: dict[str, str] = form;

    def put(key: str, text: str) {
        set_form(with_field(values, key, text));
    }

    def open_form(row: dict[str, any], which: str) {  # jac:ignore[W1037]
        set_open_row(row["variant_id"]);
        set_mode(which);
        set_errors({});
        set_form(
            {
                "reason": "received",
                "quantity": "",
                "note": "",
                "low": str(row["low_threshold"]),
                "at_zero": row["at_zero"]
            }
        );
    }

    async def run(work: any, done: str) -> bool {  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await work();
        } except Exception as e {
            console.warn("stock change failed", e);
        }
        set_busy(False);
        if answer is None {
            set_message("We couldn't save that. Check your connection and try again.");
            return False;
        }
        if not answer["ok"] {
            shown: dict[str, str] = {};
            shown["stock-form"] = answer["error"]["message"];
            set_errors(shown);
            return False;
        }
        set_errors({});
        set_open_row("");
        # Announced once the list shows the change, never before.
        await load();
        set_message(done);
        return True;
    }

    async def adjust(row: dict[str, any]) {  # jac:ignore[W1037]
        quantity = int_of(values["quantity"]);
        if quantity is None {
            shown: dict[str, str] = {};
            shown["stock-form"] = "Enter a whole number, like 12.";
            set_errors(shown);
            return;
        }
        product_id: str = row["product_id"];
        variant_id: str = row["variant_id"];
        here: str = venue;
        reason: str = values["reason"];
        note: str = values["note"];
        def send -> any {  # jac:ignore[W1037]
            return adjust_snack_stock(  # jac:ignore[W2037]
                slug, product_id, variant_id, here, reason, quantity, note
            );
        }
        await run(
            send,
            f"{row['label']}: {after_change(reason, quantity, row['on_hand'])} on hand."
        );
    }

    async def save_rules(row: dict[str, any]) {  # jac:ignore[W1037]
        low = int_of(values["low"]);
        if low is None or low < 0 {
            shown: dict[str, str] = {};
            shown["stock-form"] = "Enter a low-stock alert of 0 or more.";
            set_errors(shown);
            return;
        }
        product_id: str = row["product_id"];
        variant_id: str = row["variant_id"];
        here: str = venue;
        at_zero: str = values["at_zero"];
        def send -> any {  # jac:ignore[W1037]
            return set_snack_stock_rules(  # jac:ignore[W2037]
                slug, product_id, variant_id, here, low, at_zero
            );
        }
        await run(send, f"Saved the alert for {row['label']}.");
    }

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if venues is None or (venue and levels is None) {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading stock…
            </p>;
    }
    places: list[dict[str, str]] = venues;
    rows: list[dict[str, any]] = levels or [];  # jac:ignore[W1037]
    moves: list[dict[str, any]] = history;  # jac:ignore[W1037]
    shown_rows = [
        r
        for r in rows
        if r["status"] != "ok"
    ]
        if low_only
        else rows;
    field_errors: dict[str, str] = errors;
    counts = {
        s: len(
            [
                r
                for r in rows
                if r["status"] == s
            ]
        ) for s in ["low", "out"]
    };

    def StatusBadge(status: str) -> JsxElement {
        if status == "out" {
            return <Badge variant="destructive" data-testid="stock-status">Out</Badge>;
        }
        if status == "low" {
            return <Badge variant="secondary" data-testid="stock-status">Low</Badge>;
        }
        return <Badge variant="outline" data-testid="stock-status">In stock</Badge>;
    }

    def AdjustForm(row: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        quantity = int_of(values["quantity"]);
        preview = after_change(values["reason"], quantity, row["on_hand"])
            if quantity is not None
            else None;
        return
            <form
                data-testid="adjust-form"
                className="flex flex-col gap-3 border-t pt-3"
                onSubmit={submit_with(lambda { adjust(row); })}
            >
                <div className="grid gap-3 sm:grid-cols-3">
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="stock-reason">Reason</Label>
                        <select
                            id="stock-reason"
                            value={values["reason"]}
                            onChange={on_input(
                                lambda (text: str) { put("reason", text); }
                            )}
                            className={SELECT_CLASSES}
                        >
                            {[
                                <option key={k} value={k}>{w}</option>
                                for (k, w) in REASONS
                            ]}
                        </select>
                    </div>
                    <TextField
                        field_id="stock-quantity"
                        label={"Counted total"
                            if values["reason"] == "count"
                            else (
                                "Change (+ or −)"
                                    if values["reason"] == "other"
                                    else "How many"
                            )}
                        value={values["quantity"]}
                        on_value={lambda (text: str) { put("quantity", text); }}
                        input_mode="numeric"
                        auto_focus={True}
                    />
                    <TextField
                        field_id="stock-note"
                        label="Note (optional)"
                        value={values["note"]}
                        on_value={lambda (text: str) { put("note", text); }}
                    />
                </div>
                <p className="text-sm" data-testid="stock-preview">
                    {f"On hand now {row['on_hand']}"
                        + (f", after this {preview}" if preview is not None else "")}
                </p>
                {field_errors["stock-form"]
                    and <FieldError
                        field_id="stock-form"
                        error={field_errors["stock-form"]}
                    />}
                <div className="flex flex-wrap gap-2">
                    <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                        Save adjustment
                    </Button>
                    <Button
                        type="button"
                        variant="ghost"
                        className="min-h-11 px-5"
                        onClick={lambda { set_open_row(""); }}
                    >
                        Cancel
                    </Button>
                </div>
            </form>;
    }

    def RulesForm(row: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        return
            <form
                data-testid="rules-form"
                className="flex flex-col gap-3 border-t pt-3"
                onSubmit={submit_with(lambda { save_rules(row); })}
            >
                <TextField
                    field_id="stock-low"
                    label="Low-stock alert at"
                    value={values["low"]}
                    on_value={lambda (text: str) { put("low", text); }}
                    input_mode="numeric"
                    hint="Show Low when this many or fewer are available."
                />
                <fieldset className="flex flex-col gap-1">
                    <legend className="mb-1 text-sm font-medium">
                        When none are left
                    </legend>
                    {[
                        <label
                            key={k}
                            className="flex min-h-11 items-center gap-3 text-sm"
                        >
                            <input
                                type="radio"
                                name="at-zero"
                                checked={values["at_zero"] == k}
                                onChange={lambda { put("at_zero", k); }}
                                className="size-5"
                            />
                            {w}
                        </label>
                        for (k, w) in [
                            ("unavailable", "Stop selling it (bottles, packets)"),
                            ("allow", "Keep selling it (made to order)")
                        ]
                    ]}
                </fieldset>
                {field_errors["stock-form"]
                    and <FieldError
                        field_id="stock-form"
                        error={field_errors["stock-form"]}
                    />}
                <div className="flex flex-wrap gap-2">
                    <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                        Save alert
                    </Button>
                    <Button
                        type="button"
                        variant="ghost"
                        className="min-h-11 px-5"
                        onClick={lambda { set_open_row(""); }}
                    >
                        Cancel
                    </Button>
                </div>
            </form>;
    }

    def Row(row: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        vid: str = row["variant_id"];
        return
            <li
                key={vid}
                data-testid="stock-row"
                className="flex flex-col gap-3 rounded-lg border bg-card p-4"
            >
                <div className="flex flex-wrap items-center gap-3">
                    <div className="flex min-w-0 flex-1 flex-col">
                        <span className="font-medium" data-testid="stock-label">
                            {row["label"]}
                        </span>
                        <span className="text-sm text-muted-foreground">
                            {row["sku"]}
                        </span>
                    </div>
                    <dl className="grid grid-cols-3 gap-4 text-sm tabular-nums">
                        <div>
                            <dt className="text-muted-foreground">On hand</dt>
                            <dd data-testid="on-hand">{row["on_hand"]}</dd>
                        </div>
                        <div>
                            <dt className="text-muted-foreground">Reserved</dt>
                            <dd>{row["reserved"]}</dd>
                        </div>
                        <div>
                            <dt className="text-muted-foreground">Available</dt>
                            <dd data-testid="available">{row["available"]}</dd>
                        </div>
                    </dl>
                    <StatusBadge status={row["status"]}/>
                </div>
                {can_adjust
                    and open_row != vid
                    and <div className="flex flex-wrap gap-2">
                        <Button
                            variant="outline"
                            className="min-h-11 px-4"
                            aria-label={f"Adjust {row['label']}"}
                            onClick={lambda { open_form(row, "adjust"); }}
                        >
                            Adjust
                        </Button>
                        <Button
                            variant="ghost"
                            className="min-h-11 px-4"
                            aria-label={f"Alerts for {row['label']}"}
                            onClick={lambda { open_form(row, "rules"); }}
                        >
                            Alerts
                        </Button>
                    </div>}
                {open_row == vid and mode == "adjust" and AdjustForm(row)}
                {open_row == vid and mode == "rules" and RulesForm(row)}
            </li>;
    }

    return
        <div className="flex flex-col gap-6" data-testid="snack-stock">
            <SnackSubnav slug={slug} current="stock"/>
            <div className="flex flex-col gap-1">
                <h2 className="text-xl font-semibold">Stock</h2>
                <p className="text-sm text-muted-foreground">
                    Stock for snacks with Track stock ticked, at each venue. Every change keeps its reason.
                </p>
            </div>
            <p
                role="status"
                aria-live="polite"
                data-testid="stock-message"
                className="text-sm empty:hidden"
            >
                {message}
            </p>
            <div className="flex flex-wrap items-center gap-4">
                {len(places) > 1
                    and <label className="flex min-h-11 items-center gap-2 text-sm">
                        <span className="text-muted-foreground">Venue</span>
                        <select
                            data-testid="stock-venue"
                            value={venue}
                            onChange={on_input(set_venue)}
                            className="min-h-11 rounded-md border border-input bg-background px-2 text-sm"
                        >
                            {[
                                <option key={v["id"]} value={v["id"]}>
                                    {v["name"]}
                                </option> for v in places
                            ]}
                        </select>
                    </label>}
                <label className="flex min-h-11 items-center gap-3 text-sm">
                    <input
                        type="checkbox"
                        data-testid="low-only"
                        checked={low_only}
                        onChange={lambda { set_low_only(not low_only); }}
                        className="size-5"
                    />
                    {f"Low or out only ({counts['low'] + counts['out']})"}
                </label>
            </div>
            {len(places) == 0
                and <p className="text-sm text-muted-foreground">Add a venue first.</p>}
            {len(rows) == 0
                and len(places) > 0
                and <div className="flex flex-col gap-2 rounded-lg border bg-card p-6">
                    <h3 className="text-base font-semibold">No tracked stock</h3>
                    <p className="text-sm text-muted-foreground">
                        Tick Track stock on a variant in the product editor to count it here.
                    </p>
                    <AppLink
                        to={snack_path(slug)}
                        className="w-fit text-sm font-medium underline underline-offset-4"
                    >
                        Go to products
                    </AppLink>
                </div>}
            {len(shown_rows) > 0
                and <ul className="flex flex-col gap-2" data-testid="stock-list">
                    {[Row(r) for r in shown_rows]}
                </ul>}
            {len(rows) > 0
                and len(shown_rows) == 0
                and <p className="text-sm">Nothing is low or out.</p>}
            <section
                aria-labelledby="history-title"
                className="flex flex-col gap-3 border-t pt-6"
            >
                <h2 id="history-title" className="text-lg font-semibold">
                    Stock history
                </h2>
                {len(moves) == 0
                    and <p className="text-sm text-muted-foreground">
                        No changes yet.
                    </p>}
                {len(moves) > 0
                    and <ol className="flex flex-col gap-2" data-testid="stock-history">
                        {[
                            <li
                                key={f"{m['at']}-{i}"}
                                data-testid="movement"
                                className="flex flex-wrap items-baseline justify-between gap-2 rounded-md border p-3 text-sm"
                            >
                                <span className="flex flex-col">
                                    <span className="font-medium">
                                        {f"{m['label']}: {REASON_WORDS.get(
                                            m['reason'], m['reason']
                                        )} {'+' if m['change'] > 0 else ''}{m[
                                            'change'
                                        ]}"}
                                    </span>
                                    <span className="text-muted-foreground">
                                        {f"{m['on_hand_after']} on hand after · {m[
                                            'by'
                                        ]}"
                                            + (f" · {m['note']}" if m["note"] else "")}
                                    </span>
                                </span>
                                <time
                                    dateTime={m["at"]}
                                    className="text-muted-foreground"
                                >
                                    {m["at"][:16].replace("T", " ")}
                                </time>
                            </li> for (i, m) in enumerate(moves)
                        ]}
                    </ol>}
            </section>
        </div>;
}
