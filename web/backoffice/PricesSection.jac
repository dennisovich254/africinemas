"""`/app/:slug/prices`: the cinema's price list (P3.7b), on the 3.6 endpoints.

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
import from core.catalog.pricing_api { get_price_list, save_price_list }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from .form_parts { FieldError, error_id, on_input, submit_with }

glob DAYS: list[str] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
     CODE_CHARS: str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
     DIGITS: str = "0123456789",
     TIMEZONE: str = "Africa/Nairobi";

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

    def add_zone {
        with_next_uid("zones", zones + [{"uid": fresh_uid(), "name": ""}]);
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
        if len(Object.keys(found)) > 0 {  # jac:ignore[W2001]
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
        negative: bool = False
    ) -> JsxElement {
        problem = field_errors[field_id] or "";
        return
            <div className="flex min-w-0 flex-col gap-1.5">
                <Label htmlFor={field_id}>{label}</Label>
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

    types_section = <section
        aria-labelledby="types-heading"
        className="flex flex-col gap-3"
    >
        <div className="flex flex-col gap-1">
            <h2 id="types-heading" className="text-lg font-semibold">Ticket types</h2>
            <p className="text-sm text-muted-foreground">
                The kinds of ticket you sell, such as Adult, Child or Student.
            </p>
        </div>
        <ul className="flex flex-col gap-2">
            {[
                <li key={t["uid"]} className="flex items-end gap-2">
                    <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                        <Label htmlFor={f"ticket-name-{i}"}>Ticket type {i + 1}</Label>
                        <Input
                            id={f"ticket-name-{i}"}
                            value={t["name"]}
                            maxLength={60}
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
        <Button
            type="button"
            variant="outline"
            className="min-h-11 w-fit px-5"
            onClick={add_type}
        >
            Add ticket type
        </Button>
    </section>;

    prices_section = <section
        aria-labelledby="prices-heading"
        className="flex flex-col gap-3"
    >
        <div className="flex flex-col gap-1">
            <h2 id="prices-heading" className="text-lg font-semibold">
                Prices by seat zone (KES)
            </h2>
            <p className="text-sm text-muted-foreground">
                Standard is every seat without a zone. Other zones match the zone names you give seats in the seat layout designer, such as Gold. Leave a price empty if that ticket isn't sold there.
            </p>
        </div>
        <ul className="flex flex-col gap-3">
            {[
                <li
                    key={z["uid"]}
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                >
                    {zi == 0 and <h3 className="font-medium">Standard</h3>}
                    {zi > 0
                        and <div className="flex items-end gap-2">
                            <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                                <Label htmlFor={f"zone-name-{zi}"}>Zone name</Label>
                                <Input
                                    id={f"zone-name-{zi}"}
                                    value={z["name"]}
                                    maxLength={40}
                                    onChange={on_input(
                                        lambda (text: str) { rename_zone(
                                            z["uid"], text
                                        ); }
                                    )}
                                    className="min-h-11"
                                />
                            </div>
                            <Button
                                type="button"
                                variant="ghost"
                                className="min-h-11 px-3"
                                aria-label={f"Remove zone {z['name'] or zi + 1}"}
                                onClick={lambda { remove_zone(z["uid"]); }}
                            >
                                Remove
                            </Button>
                        </div>}
                    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                        {[
                            <div key={t["uid"]}>
                                {money_input(
                                    f"price-{zi}-{ti}",
                                    f"{t['name'] or 'Ticket type ' + str(ti + 1)}",
                                    cells[f"{z['uid']}|{t['uid']}"] or "",
                                    lambda (text: str) { set_cell(
                                        z["uid"], t["uid"], text
                                    ); }
                                )}
                            </div> for (ti, t) in enumerate(types)
                        ]}
                    </div>
                </li> for (zi, z) in enumerate(zones)
            ]}
        </ul>
        <Button
            type="button"
            variant="outline"
            className="min-h-11 w-fit px-5"
            onClick={add_zone}
        >
            Add zone
        </Button>
    </section>;

    extras_section = <section
        aria-labelledby="extras-heading"
        className="flex flex-col gap-3"
    >
        <div className="flex flex-col gap-1">
            <h2 id="extras-heading" className="text-lg font-semibold">
                Time-of-day extras
            </h2>
            <p className="text-sm text-muted-foreground">
                An amount added to every ticket for screenings starting on the chosen days between two times, such as an evening extra. A negative amount is a discount, such as a morning matinee.
            </p>
        </div>
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
        <Button
            type="button"
            variant="outline"
            className="min-h-11 w-fit px-5"
            onClick={add_extra}
        >
            Add time-of-day extra
        </Button>
    </section>;

    return
        <form
            data-testid="prices-page"
            className="flex flex-col gap-8"
            noValidate={True}
            onSubmit={submit_with(lambda { save(); })}
        >
            <p className="text-sm text-muted-foreground">
                {f"Version {version} is in use. Changes apply to new bookings only; tickets already sold keep their price."
                    if version
                    else "No prices yet. Set them before putting screenings on sale."}
            </p>
            {types_section}
            {prices_section}
            {extras_section}
            <section
                aria-labelledby="fee-heading"
                className="flex max-w-xs flex-col gap-3"
            >
                <h2 id="fee-heading" className="text-lg font-semibold">Service fee</h2>
                {money_input(
                    "service-fee",
                    "Per ticket (KES)",
                    state["fee"],
                    lambda (text: str) { update("fee", text); }
                )}
            </section>
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
            <div className="flex flex-col gap-3">
                <Button type="submit" className="min-h-11 w-fit px-5" disabled={busy}>
                    {busy and <Spinner aria-hidden="true"/>}{"Saving…"
                        if busy
                        else "Save prices"}
                </Button>
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
