"""`/app/:slug/prices`: the cinema's price list (P3.7b), on the 3.6 endpoints.

Four tabs along the top (#8), like the Snacks page: Ticket types, Seat zone prices (a
grid of zones by ticket type, offering the zone names drawn in the seat layouts),
Time-of-day extras and Service fee. They are parts of one price list, so the Save bar
stays at the foot of every tab, and a refused save opens the first tab with a problem.

Ticket types (Adult, Child, …), a price for each type in each seat zone (Standard, plus
the zones given to seats in the seat layout designer), time-of-day extras (a named
amount added, or taken off, on chosen days between two times) and a service fee per
ticket. Amounts are entered in shillings and stored in cents. Ticket type codes are
made from the names, and kept once saved. A refused list shows every problem at once.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.pricing_api { get_price_list, save_price_list }  # jac:ignore[W2037] authenticated endpoint
import from .form_parts { FieldError, error_id, on_input, submit_with }

glob DAYS: list[str] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
     CODE_CHARS: str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
     DIGITS: str = "0123456789",
     TIMEZONE: str = "Africa/Nairobi",
     TABS: list[tuple[str, str]] = [
         ("types", "Ticket types"),
         ("zones", "Seat zone prices"),
         ("extras", "Time-of-day extras"),
         ("fee", "Service fee")
     ];

def two(n: int) -> str {
    return f"0{n}" if n < 10 else str(n);
}

def:pub shillings(cents: int) -> str {
    # 80000 -> "800", -30000 -> "-300" (prices are whole shillings; cents, never used
    # in Kenya, would still show as "850.50").
    sign = "-" if cents < 0 else "";
    size = 0 - cents if cents < 0 else cents;
    whole = int(size / 100);
    rest = size - whole * 100;
    return f"{sign}{whole}" if rest == 0 else f"{sign}{whole}.{two(rest)}";
}

def:pub cents_of(text: str, allow_negative: bool) -> any {  # jac:ignore[W1037]
    # "1,200" -> 120000; None unless it is a whole number of shillings (Kenya doesn't
    # use cents, and M-Pesa charges whole shillings). "800.00" is accepted as 800.
    cleaned = text.strip().replace(",", "");
    negative = False;
    if cleaned.startswith("-") {
        if not allow_negative {
            return None;
        }
        negative = True;
        cleaned = cleaned[1:];
    }
    parts = cleaned.split(".");
    if len(parts) > 2 or not parts[0] {
        return None;
    }
    for part in parts {
        for ch in part {
            if ch not in DIGITS {
                return None;
            }
        }
    }
    if len(parts) == 2 and parts[1].strip("0") != "" {
        return None;
    }
    total = int(parts[0]) * 100;
    return 0 - total if negative else total;
}

def:pub code_for(name: str, taken: list[str]) -> str {
    # A ticket type code from its name: "Senior 60+" -> "SENIOR_60", unique among `taken`.
    code = "";
    for ch in name.upper() {
        if ch in CODE_CHARS {
            code += ch;
        } elif code and not code.endswith("_") {
            code += "_";
        }
    }
    code = code.strip("_")[:18];
    if not code or code[0] in DIGITS {
        code = "T" + code;
    }
    base = code;
    n = 2;
    while code in taken {
        code = f"{base}_{n}";
        n += 1;
    }
    return code;
}

def tab_of(field_id: str) -> str {
    # The tab holding a marked field.
    if field_id.startswith("price-") {
        return "zones";
    }
    return "extras" if field_id.startswith("surcharge-") else "fee";
}

def start_list -> dict[str, any] {  # jac:ignore[W1037]
    # A cinema's first price list: one ticket type in the standard zone, nothing else.
    return {
        "types": [{"uid": 1, "code": "ADULT", "name": "Adult"}],
        "zones": [{"uid": 0, "name": ""}],
        "cells": {},
        "extras": [],
        "fee": "0",
        "next_uid": 2
    };
}

def from_saved(saved: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # The editor's state for a saved price list (get_price_list's shape).
    uid = 1;
    types: list[dict[str, any]] = [];  # jac:ignore[W1037]
    by_code: dict[str, int] = {};
    for t in saved["ticket_types"] {
        types.append({"uid": uid, "code": t["code"], "name": t["name"]});
        by_code[t["code"]] = uid;
        uid += 1;
    }
    zones: list[dict[str, any]] = [{"uid": 0, "name": ""}];  # jac:ignore[W1037]
    by_zone: dict[str, int] = {"": 0};
    cells: dict[str, str] = {};
    for p in saved["prices"] {
        if p["zone"] not in by_zone {
            zones.append({"uid": uid, "name": p["zone"]});
            by_zone[p["zone"]] = uid;
            uid += 1;
        }
        if p["ticket_type"] in by_code {
            cells[f"{by_zone[p['zone']]}|{by_code[p['ticket_type']]}"] = shillings(
                p["price_cents"]
            );
        }
    }
    extras: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in saved["surcharges"] {
        extras.append(
            {
                "uid": uid,
                "name": s["name"],
                "days": s["days"],
                "start": s["start"],
                "end": "00:00" if s["end"] == "24:00" else s["end"],
                "amount": shillings(s["amount_cents"])
            }
        );
        uid += 1;
    }
    return {
        "types": types,
        "zones": zones,
        "cells": cells,
        "extras": extras,
        "fee": shillings(saved["service_fee_cents"]),
        "next_uid": uid
    };
}

def:pub PricesSection(slug: str) -> JsxElement {
    [draft, set_draft] = useState(None);
    [version, set_version] = useState(0);
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [errors, set_errors] = useState({});
    [problems, set_problems] = useState([]);
    [message, set_message] = useState("");
    [view, set_view] = useState("types");
    [layout_zones, set_layout_zones] = useState([]);
    [dirty, set_dirty] = useState(False);

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await get_price_list(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("get_price_list failed", e);
            set_failed("We couldn't load your prices. Refresh the page to try again.");
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_layout_zones(answer["layout_zones"]);
        saved: dict[str, any] | None = answer["price_list"];  # jac:ignore[W1037]
        if saved is None {
            set_draft(start_list());
            set_version(0);
        } else {
            set_draft(from_saved(saved));
            set_version(saved["version"]);
        }
    }

    # A named function, not a one-statement lambda (JI-028).
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if draft is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading your prices…
            </p>;
    }
    state: dict[str, any] = draft;  # jac:ignore[W1037]
    types: list[dict[str, any]] = state["types"];  # jac:ignore[W1037]
    zones: list[dict[str, any]] = state["zones"];  # jac:ignore[W1037]
    cells: dict[str, str] = state["cells"];
    extras: list[dict[str, any]] = state["extras"];  # jac:ignore[W1037]
    field_errors: dict[str, str] = errors;
    listed_problems: list[str] = problems;

    def update(key: str, value: any) {  # jac:ignore[W1037]
        # A copy of the draft with one part replaced.
        changed: dict[str, any] = {};  # jac:ignore[W1037]
        for k in state {
            changed[k] = state[k];
        }
        changed[key] = value;
        set_draft(changed);
        set_dirty(True);
        set_message("");
    }

    def fresh_uid -> int {
        uid: int = state["next_uid"];
        return uid;
    }

    def with_next_uid(key: str, value: any) {  # jac:ignore[W1037]
        changed: dict[str, any] = {};  # jac:ignore[W1037]
        for k in state {
            changed[k] = state[k];
        }
        changed[key] = value;
        changed["next_uid"] = state["next_uid"] + 1;
        set_draft(changed);
        set_dirty(True);
        set_message("");
    }

    def rename_type(uid: int, name: str) {
        update(
            "types",
            [
                {"uid": t["uid"], "code": t["code"], "name": name}
                    if t["uid"] == uid
                    else t for t in types
            ]
        );
    }

    def add_type {
        with_next_uid("types", types + [{"uid": fresh_uid(), "code": "", "name": ""}]);
    }

    def remove_type(uid: int) {
        update(
            "types",
            [
                t
                for t in types
                if t["uid"] != uid
            ]
        );
    }

    def rename_zone(uid: int, name: str) {
        update(
            "zones",
            [{"uid": z["uid"], "name": name} if z["uid"] == uid else z for z in zones]
        );
    }

    def add_zone(name: str = "") {
        with_next_uid("zones", zones + [{"uid": fresh_uid(), "name": name}]);
    }

    def remove_zone(uid: int) {
        update(
            "zones",
            [
                z
                for z in zones
                if z["uid"] != uid
            ]
        );
    }

    def set_cell(zone_uid: int, type_uid: int, text: str) {
        changed: dict[str, str] = {};
        for k in cells {
            changed[k] = cells[k];
        }
        changed[f"{zone_uid}|{type_uid}"] = text;
        update("cells", changed);
    }

    def change_extra(uid: int, key: str, value: any) {  # jac:ignore[W1037]
        rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for x in extras {
            if x["uid"] == uid {
                row: dict[str, any] = {};  # jac:ignore[W1037]
                for k in x {
                    row[k] = x[k];
                }
                row[key] = value;
                rows.append(row);
            } else {
                rows.append(x);
            }
        }
        update("extras", rows);
    }

    def toggle_day(x: dict[str, any], day: int) {  # jac:ignore[W1037]
        days: list[int] = x["days"];
        chosen = [
            d
            for d in days
            if d != day
        ]
            if day in days
            else sorted(days + [day]);
        change_extra(x["uid"], "days", chosen);
    }

    def add_extra {
        with_next_uid(
            "extras",
            extras
                + [
                    {
                        "uid": fresh_uid(),
                        "name": "",
                        "days": [0, 1, 2, 3, 4, 5, 6],
                        "start": "18:00",
                        "end": "00:00",
                        "amount": ""
                    }
                ]
        );
    }

    def remove_extra(uid: int) {
        update(
            "extras",
            [
                x
                for x in extras
                if x["uid"] != uid
            ]
        );
    }

    def build -> any {  # jac:ignore[W1037]
        # The price list to send, or None after marking every amount that isn't one.
        found: dict[str, str] = {};
        taken: list[str] = [
            t["code"]
            for t in types
            if t["code"]
        ];
        codes: dict[int, str] = {};
        out_types: list[dict[str, str]] = [];
        for t in types {
            code: str = t["code"];
            if not code {
                code = code_for(t["name"], taken);
                taken.append(code);
            }
            codes[t["uid"]] = code;
            out_types.append({"code": code, "name": t["name"]});
        }
        out_prices: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for (zi, z) in enumerate(zones) {
            for (ti, t) in enumerate(types) {
                text = cells[f"{z['uid']}|{t['uid']}"] or "";
                if text.strip() {
                    cents = cents_of(text, False);
                    if cents is None {
                        found[f"price-{zi}-{ti}"] = "Enter a whole number of shillings, like 800.";
                    } else {
                        out_prices.append(
                            {
                                "zone": z["name"],
                                "ticket_type": codes[t["uid"]],
                                "price_cents": cents
                            }
                        );
                    }
                }
            }
        }
        out_extras: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for (k, x) in enumerate(extras) {
            cents = cents_of(x["amount"], True);
            if cents is None {
                found[f"surcharge-amount-{k}"] = "Enter whole shillings; use a minus sign for a discount, like -100.";
            } else {
                out_extras.append(
                    {
                        "name": x["name"],
                        "days": x["days"],
                        "start": x["start"],
                        "end": "24:00" if x["end"] == "00:00" else x["end"],
                        "amount_cents": cents
                    }
                );
            }
        }
        fee = cents_of(state["fee"] or "0", False);
        if fee is None {
            found["service-fee"] = "Enter the fee in whole shillings, like 30.";
        }
        set_errors(found);
        marked: list[str] = Object.keys(found);  # jac:ignore[W2001]
        if len(marked) > 0 {
            # Open the first tab, in tab order, with a marked field.
            first = "";
            for (key, _) in TABS {
                for f in marked {
                    if not first and tab_of(f) == key {
                        first = key;
                    }
                }
            }
            set_view(first);
            return None;
        }
        return {
            "types": out_types,
            "prices": out_prices,
            "extras": out_extras,
            "fee": fee
        };
    }

    async def save {
        answer: any = None;  # jac:ignore[W1037]
        set_problems([]);
        set_message("");
        payload: any = build();  # jac:ignore[W1037]
        if payload is None {
            set_message("Some amounts need fixing: see the marked fields.");
            return;
        }
        set_busy(True);
        try {
            answer = await save_price_list(  # jac:ignore[W2037]
                slug,
                TIMEZONE,
                payload["types"],
                payload["prices"],
                payload["extras"],
                payload["fee"]
            );
        } except Exception as e {
            console.warn("save_price_list failed", e);
            set_busy(False);
            set_message("We couldn't save. Check your connection and try again.");
            return;
        }
        set_busy(False);
        if not answer["ok"] {
            if answer["error"]["code"] == "invalid_price_list" {
                set_problems([p["message"] for p in answer["error"]["problems"]]);
            } else {
                set_message(answer["error"]["message"]);
            }
            return;
        }
        set_draft(from_saved(answer["price_list"]));
        set_version(answer["price_list"]["version"]);
        set_dirty(False);
        set_message(
            f"Saved. New bookings use these prices (version {answer['price_list'][
                'version'
            ]})."
        );
    }

    def money_input(
        field_id: str,
        label: str,
        value: str,
        on_text: any,  # jac:ignore[W1037]
        negative: bool = False,
        hide_label: bool = False
    ) -> JsxElement {
        problem = field_errors[field_id] or "";
        return
            <div className="flex min-w-0 flex-col gap-1.5">
                <Label htmlFor={field_id} className={"sr-only" if hide_label else ""}>
                    {label}
                </Label>
                <Input
                    id={field_id}
                    value={value}
                    inputMode={"text" if negative else "numeric"}
                    placeholder={"-100" if negative else "Not sold"}
                    aria-invalid={"true" if problem else "false"}
                    aria-describedby={error_id(field_id) if problem else None}
                    onChange={on_input(on_text)}
                    className="min-h-11"
                />
                {problem and <FieldError field_id={field_id} error={problem}/>}
            </div>;
    }

    def heading(key: str, title: str, hint: str) -> JsxElement {
        return
            <div className="flex flex-col gap-1">
                <h2 id={f"{key}-heading"} className="text-lg font-semibold">{title}</h2>
                <p className="max-w-prose text-sm text-muted-foreground">{hint}</p>
            </div>;
    }

    def next_button(key: str, label: str) -> JsxElement {
        # The way on to the next tab, so a first visit runs through all four.
        return
            <Button
                type="button"
                variant="ghost"
                className="min-h-11 w-fit px-3"
                onClick={lambda { set_view(key); }}
            >
                {f"Next: {label} →"}
            </Button>;
    }

    zone_names: list[str] = [z["name"] for z in zones];
    known_zones: list[str] = layout_zones;
    unpriced: list[str] = [
        name
        for name in known_zones
        if name not in zone_names
    ];
    marked_tabs: list[str] = [tab_of(f) for f in Object.keys(field_errors)];  # jac:ignore[W2001]

    types_panel = <section
        aria-labelledby="types-heading"
        className="flex flex-col gap-4"
    >
        {heading(
            "types",
            "Ticket types",
            "The kinds of ticket you sell, such as Adult, Child or Student. You set what each one costs in Seat zone prices."
        )}
        <ul className="flex max-w-xl flex-col gap-2">
            {[
                <li key={t["uid"]} className="flex items-end gap-2">
                    <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                        <Label htmlFor={f"ticket-name-{i}"}>Ticket type {i + 1}</Label>
                        <Input
                            id={f"ticket-name-{i}"}
                            value={t["name"]}
                            maxLength={60}
                            placeholder="e.g. Child"
                            onChange={on_input(
                                lambda (text: str) { rename_type(t["uid"], text); }
                            )}
                            className="min-h-11"
                        />
                    </div>
                    {len(types) > 1
                        and <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11 px-3"
                            aria-label={f"Remove {t['name'] or 'this ticket type'}"}
                            onClick={lambda { remove_type(t["uid"]); }}
                        >
                            Remove
                        </Button>}
                </li> for (i, t) in enumerate(types)
            ]}
        </ul>
        <div className="flex flex-wrap items-center gap-2">
            <Button
                type="button"
                variant="outline"
                className="min-h-11 w-fit px-5"
                onClick={add_type}
            >
                Add ticket type
            </Button>
            {next_button("zones", "Seat zone prices")}
        </div>
    </section>;

    zones_panel = <section
        aria-labelledby="zones-heading"
        className="flex flex-col gap-4"
    >
        {heading(
            "zones",
            "Seat zone prices (KES)",
            "One row for each seat zone, one column for each ticket type. Standard is every seat without a zone; other zones match the names given to seats in the seat layout designer. Leave a price empty if that ticket isn't sold there."
        )}
        {len(unpriced) > 0
            and <div
                className="flex flex-wrap items-center gap-2 rounded-lg border border-dashed p-3"
                data-testid="unpriced-zones"
            >
                <span className="text-sm text-muted-foreground">
                    In your seat layouts but not priced yet:
                </span>
                {[
                    <Button
                        key={name}
                        type="button"
                        variant="outline"
                        size="sm"
                        className="min-h-11 px-3"
                        onClick={lambda { add_zone(name); }}
                    >
                        {f"+ {name}"}
                    </Button> for name in unpriced
                ]}
            </div>}
        <div className="overflow-x-auto rounded-lg border">
            <table className="w-full min-w-max text-sm">
                <thead className="bg-muted/50">
                    <tr>
                        <th scope="col" className="px-3 py-2 text-left font-medium">
                            Zone
                        </th>
                        {[
                            <th
                                key={t["uid"]}
                                scope="col"
                                className="px-3 py-2 text-left font-medium"
                            >
                                {t["name"] or f"Ticket type {ti + 1}"}
                            </th> for (ti, t) in enumerate(types)
                        ]}
                        <th scope="col" className="px-3 py-2">
                            <span className="sr-only">Remove</span>
                        </th>
                    </tr>
                </thead>
                <tbody>
                    {[
                        <tr key={z["uid"]} className="border-t align-top">
                            <th scope="row" className="px-3 py-2 text-left font-medium">
                                {zi == 0
                                    and <span
                                        className="inline-flex min-h-11 items-center"
                                    >
                                        Standard
                                    </span>}{zi > 0
                                    and <div className="flex flex-col gap-1">
                                        <Label
                                            htmlFor={f"zone-name-{zi}"}
                                            className="sr-only"
                                        >
                                            Zone name
                                        </Label>
                                        <Input
                                            id={f"zone-name-{zi}"}
                                            value={z["name"]}
                                            maxLength={40}
                                            placeholder="e.g. Gold"
                                            onChange={on_input(
                                                lambda (text: str) { rename_zone(
                                                    z["uid"], text
                                                ); }
                                            )}
                                            className="min-h-11 w-36"
                                        />
                                        {z["name"]
                                            and z["name"] not in known_zones
                                            and <span
                                                className="text-xs text-muted-foreground"
                                            >
                                                No seats use this zone yet
                                            </span>}
                                    </div>}
                            </th>
                            {[
                                <td key={t["uid"]} className="w-32 px-3 py-2">
                                    {money_input(
                                        f"price-{zi}-{ti}",
                                        f"{z['name'] or 'Standard'} {t['name']
                                            or 'ticket type ' + str(ti + 1)} price",
                                        cells[f"{z['uid']}|{t['uid']}"] or "",
                                        lambda (text: str) { set_cell(
                                            z["uid"], t["uid"], text
                                        ); },
                                        False,
                                        True
                                    )}
                                </td> for (ti, t) in enumerate(types)
                            ]}
                            <td className="px-3 py-2 text-right">
                                {zi > 0
                                    and <Button
                                        type="button"
                                        variant="ghost"
                                        className="min-h-11 px-3"
                                        aria-label={f"Remove zone {z['name']
                                            or zi + 1}"}
                                        onClick={lambda { remove_zone(z["uid"]); }}
                                    >
                                        Remove
                                    </Button>}
                            </td>
                        </tr> for (zi, z) in enumerate(zones)
                    ]}
                </tbody>
            </table>
        </div>
        <div className="flex flex-wrap items-center gap-2">
            <Button
                type="button"
                variant="outline"
                className="min-h-11 w-fit px-5"
                onClick={lambda { add_zone(""); }}
            >
                Add zone
            </Button>
            {next_button("extras", "Time-of-day extras")}
        </div>
    </section>;

    extras_panel = <section
        aria-labelledby="extras-heading"
        className="flex flex-col gap-4"
    >
        {heading(
            "extras",
            "Time-of-day extras",
            "An amount added to every ticket for screenings starting on the chosen days between two times, such as an evening extra. A negative amount is a discount, such as a morning matinee. Optional."
        )}
        {len(extras) == 0
            and <p className="text-sm text-muted-foreground">None yet.</p>}
        <ul className="flex flex-col gap-3">
            {[
                <li
                    key={x["uid"]}
                    className="grid gap-3 rounded-lg border bg-card p-4 sm:grid-cols-2 lg:grid-cols-4"
                >
                    <div className="flex flex-col gap-1.5 sm:col-span-2 lg:col-span-4">
                        <Label htmlFor={f"surcharge-name-{k}"}>Name</Label>
                        <Input
                            id={f"surcharge-name-{k}"}
                            value={x["name"]}
                            maxLength={40}
                            placeholder="e.g. Evening"
                            onChange={on_input(
                                lambda (text: str) { change_extra(
                                    x["uid"], "name", text
                                ); }
                            )}
                            className="min-h-11"
                        />
                    </div>
                    <div
                        role="group"
                        aria-labelledby={f"surcharge-days-{k}"}
                        className="flex flex-col gap-1.5 sm:col-span-2 lg:col-span-4"
                    >
                        <span
                            id={f"surcharge-days-{k}"}
                            className="text-sm font-medium"
                        >
                            Days
                        </span>
                        <div className="flex flex-wrap gap-2">
                            {[
                                <Button
                                    key={d}
                                    type="button"
                                    variant={"default" if d in x["days"] else "outline"}
                                    aria-pressed={"true" if d in x["days"] else "false"}
                                    className="min-h-11 min-w-11 px-3"
                                    onClick={lambda { toggle_day(x, d); }}
                                >
                                    {DAYS[d]}
                                </Button> for d in range(7)
                            ]}
                        </div>
                    </div>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor={f"surcharge-start-{k}"}>From</Label>
                        <Input
                            id={f"surcharge-start-{k}"}
                            type="time"
                            value={x["start"]}
                            onChange={on_input(
                                lambda (text: str) { change_extra(
                                    x["uid"], "start", text
                                ); }
                            )}
                            className="min-h-11"
                        />
                    </div>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor={f"surcharge-end-{k}"}>
                            Until (midnight runs to the end of the day)
                        </Label>
                        <Input
                            id={f"surcharge-end-{k}"}
                            type="time"
                            value={x["end"]}
                            onChange={on_input(
                                lambda (text: str) { change_extra(
                                    x["uid"], "end", text
                                ); }
                            )}
                            className="min-h-11"
                        />
                    </div>
                    {money_input(
                        f"surcharge-amount-{k}",
                        "Amount (KES)",
                        x["amount"],
                        lambda (text: str) { change_extra(x["uid"], "amount", text); },
                        True
                    )}
                    <div className="flex items-end">
                        <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11 px-3"
                            aria-label={f"Remove {x['name'] or 'this extra'}"}
                            onClick={lambda { remove_extra(x["uid"]); }}
                        >
                            Remove
                        </Button>
                    </div>
                </li> for (k, x) in enumerate(extras)
            ]}
        </ul>
        <div className="flex flex-wrap items-center gap-2">
            <Button
                type="button"
                variant="outline"
                className="min-h-11 w-fit px-5"
                onClick={add_extra}
            >
                Add time-of-day extra
            </Button>
            {next_button("fee", "Service fee")}
        </div>
    </section>;

    fee_panel = <section aria-labelledby="fee-heading" className="flex flex-col gap-4">
        {heading(
            "fee",
            "Service fee",
            "A fixed amount added to each ticket on top of its price. Enter 0 for none."
        )}
        <div className="max-w-xs">
            {money_input(
                "service-fee",
                "Per ticket (KES)",
                state["fee"],
                lambda (text: str) { update("fee", text); }
            )}
        </div>
    </section>;

    return
        <form
            data-testid="prices-page"
            className="flex flex-col gap-6"
            noValidate={True}
            onSubmit={submit_with(lambda { save(); })}
        >
            <p className="text-sm text-muted-foreground">
                {f"Version {version} is in use. Changes apply to new bookings only; tickets already sold keep their price."
                    if version
                    else "No prices yet. Set them before putting screenings on sale."}
            </p>
            <div
                role="tablist"
                aria-label="Prices"
                className="flex gap-1 overflow-x-auto border-b [scrollbar-width:thin]"
            >
                {[
                    <button
                        key={key}
                        type="button"
                        role="tab"
                        id={f"prices-tab-{key}"}
                        data-testid={f"prices-tab-{key}"}
                        aria-selected={"true" if view == key else "false"}
                        aria-controls={f"prices-panel-{key}"}
                        onClick={lambda { set_view(key); }}
                        className={"-mb-px inline-flex min-h-11 shrink-0 items-center gap-2 whitespace-nowrap border-b-2 px-3 text-sm sm:px-4 "
                            + (
                                "border-primary font-semibold"
                                    if view == key
                                    else "border-transparent text-muted-foreground hover:text-foreground"
                            )}
                    >
                        {label}{key in marked_tabs
                            and <span
                                className="size-2 rounded-full bg-destructive"
                                aria-label="has problems"
                            />}
                    </button> for (key, label) in TABS
                ]}
            </div>
            <div
                role="tabpanel"
                id={f"prices-panel-{view}"}
                aria-labelledby={f"prices-tab-{view}"}
                className="min-w-0"
            >
                {view == "types" and types_panel}{view == "zones" and zones_panel}{view
                    == "extras"
                    and extras_panel}{view == "fee" and fee_panel}
            </div>
            {len(listed_problems) > 0
                and <Alert
                    variant="destructive"
                    role="alert"
                    data-testid="price-problems"
                >
                    <AlertTitle>Fix these before saving</AlertTitle>
                    <AlertDescription>
                        <ul className="list-disc pl-4">
                            {[
                                <li key={i}>{p}</li>
                                for (i, p) in enumerate(listed_problems)
                            ]}
                        </ul>
                    </AlertDescription>
                </Alert>}
            <div
                className="sticky bottom-0 z-10 -mx-1 flex flex-wrap items-center gap-3 border-t bg-background/95 px-1 py-3 backdrop-blur"
            >
                <Button type="submit" className="min-h-11 w-fit px-5" disabled={busy}>
                    {busy and <Spinner aria-hidden="true"/>}{"Saving…"
                        if busy
                        else "Save prices"}
                </Button>
                {dirty
                    and not message
                    and <span className="text-sm text-muted-foreground">
                        Unsaved changes
                    </span>}
                <p
                    role="status"
                    aria-live="polite"
                    className="text-sm empty:hidden"
                    data-testid="prices-message"
                >
                    {message}
                </p>
            </div>
        </form>;
}
