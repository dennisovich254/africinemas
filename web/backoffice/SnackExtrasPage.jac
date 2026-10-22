"""`/app/:slug/snacks/extras`: Combos & Add-ons (P12.3; design guide §5).

- Add-on groups: extras customers add to a product ("Popcorn extras": butter +KES 30,
  caramel +KES 50; optional, up to 2). Managers add, edit and delete groups (one offered
  with a product can't be deleted); each says how many products offer it. Each add-on
  has an "On sale at <venue>" box for every venue (improvements #9: ticked means sold
  there), saved at once and announced, for the box office too. Groups are given to products in the product editor.
- Combos: the cinema's combo products, each opening in the product editor, and "Add
  combo" (a product whose type is Combo).

The group editor lists add-ons as rows (a name and an extra price in shillings), with
"Add an add-on" and a Remove button per row; problems show beside their field.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.snacks.extras_api {
    list_snack_addon_groups,  # jac:ignore[W2037] authenticated endpoint
    save_snack_addon_group,  # jac:ignore[W2037]
    delete_snack_addon_group,  # jac:ignore[W2037]
    set_snack_addon_availability  # jac:ignore[W2037]
}
import from core.snacks.product_api { list_snack_products }  # jac:ignore[W2037] authenticated endpoint
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037] authenticated endpoint
import from ..shell.AppLink { AppLink }
import from .form_parts { TextField, FieldError, ConfirmDelete, submit_with, on_input }
import from .snack_view {
    SnackSubnav,
    snack_path,
    problem_id,
    price_text,
    price_cents_of,
    whole_number,
    with_field
}

glob OPTIONS_MAX: int = 20;

def:pub picks_words(min_picks: int, max_picks: int, repeatable: bool) -> str {
    # "Optional, up to 2", "Pick 1", "Pick 1 to 3", plus "(can repeat)".
    words = f"Pick {max_picks}"
        if min_picks == max_picks
        else (
            f"Optional, up to {max_picks}"
                if min_picks == 0
                else f"Pick {min_picks} to {max_picks}"
        );
    return f"{words} (can repeat)" if repeatable else words;
}

def _blank -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "name": "",
        "label": "",
        "min": "0",
        "max": "1",
        "repeatable": False,
        "options": [{"option_id": "", "name": "", "price": ""}]
    };
}

def _form_of(g: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "name": g["name"],
        "label": g["label"],
        "min": str(g["min_picks"]),
        "max": str(g["max_picks"]),
        "repeatable": g["repeatable"],
        "options": [
            {
                "option_id": o["option_id"],
                "name": o["name"],
                "price": price_text(o["price_cents"]) if o["price_cents"] else ""
            } for o in g["options"]
        ]
    };
}

def:pub SnackExtrasPage(slug: str, permissions: list[str]) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    can_flip = "concessions.availability" in permissions;
    [groups, set_groups] = useState(None);
    [combos, set_combos] = useState([]);
    [venues, set_venues] = useState([]);
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [message, set_message] = useState("");
    [errors, set_errors] = useState({});
    [editing, set_editing] = useState("");
    [form, set_form] = useState(_blank());
    [confirming, set_confirming] = useState(None);

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        products: any = None;  # jac:ignore[W1037]
        places: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_snack_addon_groups(slug);  # jac:ignore[W2037]
            products = await list_snack_products(slug, "", "", "");  # jac:ignore[W2037]
            places = await list_venues(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("loading combos and add-ons failed", e);
            set_failed(
                "We couldn't load your combos and add-ons. Refresh the page to try again."
            );
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_groups(answer["groups"]);
        set_combos(
            [
                p
                for p in products["products"]
                if p["kind"] == "combo"
            ]
                if products["ok"]
                else []
        );
        if places["ok"] {
            found = [
                {"id": v["venue_id"], "name": v["name"]} for v in places["venues"]
            ];
            set_venues(found);
        }
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    async def run(work: any, done: str, problems_too: bool = False) -> bool {  # jac:ignore[W1037]
        answer: any = None;  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        try {
            answer = await work();
        } except Exception as e {
            console.warn("add-on change failed", e);
            set_busy(False);
            set_message("We couldn't save that. Check your connection and try again.");
            return False;
        }
        set_busy(False);
        if not answer["ok"] {
            shown: dict[str, str] = {};
            if problems_too {
                for p in answer["error"].get("problems", []) or [] {
                    shown[problem_id(f"group.{p['field']}")] = p["message"];
                }
            }
            set_errors(shown);
            if not shown {
                set_message(answer["error"]["message"]);
            }
            return False;
        }
        set_errors({});
        # Announced once the list shows the change, never before.
        await load();
        set_message(done);
        return True;
    }

    values: dict[str, any] = form;  # jac:ignore[W1037]
    rows: list[dict[str, str]] = values["options"];
    field_errors: dict[str, str] = errors;

    def put(key: str, value: any) {  # jac:ignore[W1037]
        set_form(with_field(values, key, value));
    }

    def put_row(i: int, key: str, text: str) {
        put(
            "options",
            [with_field(r, key, text) if n == i else r for (n, r) in enumerate(rows)]
        );
    }

    def start(group_id: str, g: any) {  # jac:ignore[W1037]
        set_editing(group_id);
        set_form(_blank() if g is None else _form_of(g));
        set_confirming(None);
        set_errors({});
    }

    async def save {
        shown: dict[str, str] = {};
        options: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for (i, r) in enumerate(rows) {
            cents = price_cents_of(r["price"]);
            if cents == -1 {
                shown[problem_id(f"group.options[{i}].price_cents")] = "Enter whole shillings, like 30, or leave it empty for free.";
            }
            options.append(
                {
                    "option_id": r["option_id"],
                    "name": r["name"],
                    "price_cents": cents if cents is not None and cents != -1 else 0
                }
            );
        }
        if shown {
            set_errors(shown);
            return;
        }
        low = whole_number(values["min"], -1);
        high = whole_number(values["max"], 0);
        group_id: str = "" if editing == "new" else editing;
        def send -> any {  # jac:ignore[W1037]
            return save_snack_addon_group(  # jac:ignore[W2037]
                slug,
                group_id,
                values["name"],
                values["label"],
                low,
                high,
                values["repeatable"],
                options
            );
        }
        if await run(send, f"Saved {values['name'].strip()}.", True) {
            set_editing("");
        }
    }

    async def flip(
        group_id: str,
        o: dict[str, any],  # jac:ignore[W1037]
        place: dict[str, str],
        available: bool
    ) {
        option_id: str = o["option_id"];
        venue_id: str = place["id"];
        def send -> any {  # jac:ignore[W1037]
            return set_snack_addon_availability(  # jac:ignore[W2037]
                slug, group_id, option_id, venue_id, available
            );
        }
        await run(
            send,
            f"{o['name']} is {'on sale' if available else 'off sale'} at {place[
                'name'
            ]}."
        );
    }

    async def confirm_delete {
        target: dict[str, str] = confirming;
        set_confirming(None);
        group_id: str = target["id"];
        def send -> any {  # jac:ignore[W1037]
            return delete_snack_addon_group(slug, group_id);  # jac:ignore[W2037]
        }
        await run(send, f"Deleted {target['name']}.");
    }

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if groups is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading combos and add-ons…
            </p>;
    }
    listed: list[dict[str, any]] = groups;  # jac:ignore[W1037]
    combo_list: list[dict[str, any]] = combos;  # jac:ignore[W1037]
    places: list[dict[str, str]] = venues;
    asking: dict[str, str] | None = confirming;

    def err(field: str) -> str {
        return field_errors[problem_id(f"group.{field}")] or "";
    }

    editor = <form
        data-testid="edit-addon-group"
        className="flex flex-col gap-4 rounded-lg border bg-card p-4"
        onSubmit={submit_with(lambda { save(); })}
    >
        <h3 className="text-lg font-semibold">
            {"Add an add-on group" if editing == "new" else f"Edit {values['name']}"}
        </h3>
        <div className="grid gap-3 sm:grid-cols-2">
            <TextField
                field_id={problem_id("group.name")}
                label="Name (for staff)"
                value={values["name"]}
                error={err("name")}
                on_value={lambda (text: str) { put("name", text); }}
                hint="Like Popcorn extras."
                auto_focus={True}
            />
            <TextField
                field_id={problem_id("group.label")}
                label="What customers see"
                value={values["label"]}
                error={err("label")}
                on_value={lambda (text: str) { put("label", text); }}
                hint="Like Choose your extras."
            />
            <TextField
                field_id={problem_id("group.min_picks")}
                label="Customers pick at least"
                value={values["min"]}
                error={err("min_picks")}
                on_value={lambda (text: str) { put("min", text); }}
                input_mode="numeric"
                hint="0 makes it optional."
            />
            <TextField
                field_id={problem_id("group.max_picks")}
                label="Customers pick at most"
                value={values["max"]}
                error={err("max_picks")}
                on_value={lambda (text: str) { put("max", text); }}
                input_mode="numeric"
            />
        </div>
        <label className="flex min-h-11 items-center gap-3 text-sm">
            <input
                type="checkbox"
                checked={values["repeatable"]}
                onChange={lambda { put("repeatable", not values["repeatable"]); }}
                className="size-5"
            />
            Customers can pick the same add-on more than once (like two dips)
        </label>
        <fieldset className="flex flex-col gap-3">
            <legend className="mb-2 text-sm font-medium">Add-ons</legend>
            {[
                <div
                    key={f"row-{i}"}
                    data-testid="addon-row"
                    className="grid grid-cols-[1fr_auto] items-start gap-2 rounded-md border p-3 sm:grid-cols-[1fr_8rem_auto] sm:rounded-none sm:border-0 sm:p-0"
                >
                    <div className="col-span-2 sm:col-span-1">
                        <TextField
                            field_id={problem_id(f"group.options[{i}].name")}
                            label={f"Add-on {i + 1}"}
                            value={r["name"]}
                            error={err(f"options[{i}].name")}
                            on_value={lambda (text: str) { put_row(i, "name", text); }}
                        />
                    </div>
                    <TextField
                        field_id={problem_id(f"group.options[{i}].price_cents")}
                        label="Extra (KES)"
                        value={r["price"]}
                        error={err(f"options[{i}].price_cents")}
                        on_value={lambda (text: str) { put_row(i, "price", text); }}
                        input_mode="decimal"
                    />
                    <Button
                        type="button"
                        variant="ghost"
                        className="min-h-11 self-end px-3"
                        aria-label={f"Remove add-on {i + 1}"}
                        disabled={len(rows) == 1}
                        onClick={lambda { put(
                            "options",
                            [
                                x
                                for (n, x) in enumerate(rows)
                                if n != i
                            ]
                        ); }}
                    >
                        Remove
                    </Button>
                </div> for (i, r) in enumerate(rows)
            ]}
            {err("options")
                and <FieldError
                    field_id={problem_id("group.options")}
                    error={err("options")}
                />}
            <Button
                type="button"
                variant="outline"
                className="min-h-11 w-fit px-4"
                disabled={len(rows) >= OPTIONS_MAX}
                onClick={lambda { put(
                    "options", rows + [{"option_id": "", "name": "", "price": ""}]
                ); }}
            >
                Add an add-on
            </Button>
        </fieldset>
        <div className="flex flex-wrap gap-3">
            <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                Save add-ons
            </Button>
            <Button
                type="button"
                variant="ghost"
                className="min-h-11 px-5"
                onClick={lambda {
                    set_editing("");
                    set_errors({});
                }}
            >
                Cancel
            </Button>
        </div>
    </form>;

    def GroupCard(g: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        gid: str = g["group_id"];
        if editing == gid {
            return <li key={gid}>{editor}</li>;
        }
        used: int = g["used_by"];
        return
            <li
                key={gid}
                data-testid="addon-group"
                className="flex flex-col gap-3 rounded-lg border bg-card p-4"
            >
                <div className="flex flex-col gap-1">
                    <h3 className="font-semibold">{g["name"]}</h3>
                    <p className="text-sm text-muted-foreground">
                        {f"Customers see “{g['label']}” · {picks_words(
                            g['min_picks'], g['max_picks'], g['repeatable']
                        )} · "}{"Not offered yet"
                            if used == 0
                            else (
                                "Offered with 1 product"
                                    if used == 1
                                    else f"Offered with {used} products"
                            )}
                    </p>
                </div>
                <ul className="flex flex-col gap-2">
                    {[
                        <li
                            key={o["option_id"]}
                            data-testid="addon"
                            className="flex flex-wrap items-center justify-between gap-2"
                        >
                            <span className="text-sm">
                                {o["name"]}
                                <span className="ml-2 text-muted-foreground">
                                    {f"+KES {price_text(o['price_cents'])}"
                                        if o["price_cents"]
                                        else "Free"}
                                </span>
                            </span>
                            <div className="flex flex-wrap gap-x-4">
                                {[
                                    <label
                                        key={v["id"]}
                                        className="flex min-h-11 items-center gap-2 text-sm"
                                    >
                                        <input
                                            type="checkbox"
                                            data-testid="addon-on-sale"
                                            aria-label={f"{o['name']} on sale at {v[
                                                'name'
                                            ]}"}
                                            checked={v["id"] not in o["off_at"]}
                                            disabled={busy or not can_flip}
                                            onChange={lambda { flip(
                                                gid, o, v, v["id"] in o["off_at"]
                                            ); }}
                                            className="size-5"
                                        />
                                        {f"On sale at {v['name']}"}
                                    </label> for v in places
                                ]}
                            </div>
                        </li> for o in g["options"]
                    ]}
                </ul>
                {can_manage
                    and <div className="flex flex-wrap gap-2">
                        <Button
                            variant="outline"
                            className="min-h-11 px-4"
                            aria-label={f"Edit {g['name']}"}
                            onClick={lambda { start(gid, g); }}
                        >
                            Edit
                        </Button>
                        <Button
                            variant="outline"
                            className="min-h-11 px-4"
                            aria-label={f"Delete {g['name']}"}
                            onClick={lambda { set_confirming(
                                {"id": gid, "name": g["name"]}
                            ); }}
                        >
                            Delete
                        </Button>
                    </div>}
                {asking is not None
                    and asking["id"] == gid
                    and <ConfirmDelete
                        question={f"Delete {asking['name']}?"}
                        detail="Products that offer these add-ons must have them removed first."
                        confirm_label="Delete add-ons"
                        on_confirm={confirm_delete}
                        on_cancel={lambda { set_confirming(None); }}
                        busy={busy}
                    />}
            </li>;
    }

    return
        <div className="flex flex-col gap-6" data-testid="snack-extras">
            <SnackSubnav slug={slug} current="extras"/>
            <p
                role="status"
                aria-live="polite"
                data-testid="extras-message"
                className="text-sm empty:hidden"
            >
                {message}
            </p>
            <section aria-labelledby="addons-title" className="flex flex-col gap-4">
                <div className="flex flex-col gap-1">
                    <h2 id="addons-title" className="text-xl font-semibold">Add-ons</h2>
                    <p className="text-sm text-muted-foreground">
                        Extras customers add to a product, like butter or caramel on popcorn. Make a group once, then offer it with any product in the product editor.
                    </p>
                </div>
                {len(listed) == 0
                    and editing != "new"
                    and <p className="text-sm text-muted-foreground">
                        No add-ons yet.
                    </p>}
                {can_manage
                    and editing != "new"
                    and <Button
                        className="min-h-11 w-fit px-5"
                        onClick={lambda { start("new", None); }}
                    >
                        Add an add-on group
                    </Button>}
                {editing == "new" and editor}
                {len(listed) > 0
                    and <ul
                        className="grid gap-3 lg:grid-cols-2"
                        data-testid="addon-groups"
                    >
                        {[GroupCard(g) for g in listed]}
                    </ul>}
            </section>
            <section
                aria-labelledby="combos-title"
                className="flex flex-col gap-4 border-t pt-6"
            >
                <div className="flex flex-col gap-1">
                    <h2 id="combos-title" className="text-xl font-semibold">Combos</h2>
                    <p className="text-sm text-muted-foreground">
                        Several products sold together at one price, like popcorn and two drinks. Customers choose where a combo lets them.
                    </p>
                </div>
                {len(combo_list) == 0
                    and <p className="text-sm text-muted-foreground">No combos yet.</p>}
                {len(combo_list) > 0
                    and <ul className="flex flex-col gap-2" data-testid="combo-list">
                        {[
                            <li key={c["product_id"]}>
                                <AppLink
                                    to={snack_path(slug, c["product_id"])}
                                    className="flex min-h-11 items-center justify-between gap-3 rounded-lg border bg-card p-3 hover:bg-muted/50"
                                >
                                    <span className="font-medium">{c["name"]}</span>
                                    <span className="flex items-center gap-2 text-sm">
                                        {c["price_from_cents"] is not None
                                            and f"KES {price_text(
                                                c['price_from_cents']
                                            )}"}
                                        <Badge
                                            variant={"default"
                                                if c["status"] == "active"
                                                else "secondary"}
                                        >
                                            {c["status"].capitalize()}
                                        </Badge>
                                    </span>
                                </AppLink>
                            </li> for c in combo_list
                        ]}
                    </ul>}
                {can_manage
                    and <AppLink
                        to={snack_path(slug, "new")}
                        className="inline-flex min-h-11 w-fit items-center rounded-md border px-5 text-sm font-medium hover:bg-muted"
                    >
                        Add combo
                    </AppLink>}
                {can_manage
                    and <p className="text-sm text-muted-foreground">
                        In the product editor, choose Combo as the type, save it, then choose what it includes.
                    </p>}
            </section>
        </div>;
}
