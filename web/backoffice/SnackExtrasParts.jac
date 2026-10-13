"""The product editor's add-on and combo sections (P12.3; design guide §5).

- SnackAddonPicker: which add-on groups customers can choose from with this product (a
  checkbox per group, made on the Combos & Add-ons page), saved by managers.
- SnackComponents: what a combo includes. Each row is a label ("Drinks"), a quantity,
  and the products it can be: one (always included) or several (the customer chooses).
  Rows are added and removed, then saved together; problems show beside their row.

Both save as soon as asked and hand the product the server returns to the editor
(on_change).
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from core.snacks.extras_api {
    list_snack_addon_groups,  # jac:ignore[W2037] authenticated endpoint
    list_snack_variants,  # jac:ignore[W2037]
    set_snack_product_addons,  # jac:ignore[W2037]
    set_snack_combo_components  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from .form_parts { TextField, FieldError }
import from .snack_view { snack_path, problem_id }

glob COMPONENTS_MAX: int = 6;

def:pub SnackAddonPicker(
    slug: str,
    product: dict[str, any],  # jac:ignore[W1037]
    permissions: list[str],
    on_change: any  # jac:ignore[W1037] (product) -> None
) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    [groups, set_groups] = useState([]);
    [chosen, set_chosen] = useState(product["addon_group_ids"]);
    [message, set_message] = useState("");
    [busy, set_busy] = useState(False);
    product_id: str = product["product_id"];

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_snack_addon_groups(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_snack_addon_groups failed", e);
            return;
        }
        if answer["ok"] {
            set_groups(answer["groups"]);
        }
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, product_id]);

    picked: list[str] = chosen;
    listed: list[dict[str, any]] = groups;  # jac:ignore[W1037]

    async def save {
        set_busy(True);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await set_snack_product_addons(slug, product_id, picked);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("set_snack_product_addons failed", e);
        }
        set_busy(False);
        if answer is None or not answer["ok"] {
            set_message(
                answer["error"]["message"]
                    if answer is not None
                    else "We couldn't save that. Try again."
            );
            return;
        }
        set_message("Saved the add-ons.");
        on_change(answer["product"]);
    }

    return
        <section
            aria-labelledby="addons-title"
            data-testid="product-addons"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h3 id="addons-title" className="text-lg font-semibold">Add-ons</h3>
            <p role="status" aria-live="polite" className="text-sm empty:hidden">
                {message}
            </p>
            {len(listed) == 0
                and <p className="text-sm text-muted-foreground">
                    No add-on groups yet.{" "}
                    <AppLink
                        to={snack_path(slug, "extras")}
                        className="font-medium underline underline-offset-4"
                    >
                        Make them on Combos & Add-ons
                    </AppLink>
                </p>}
            {[
                <label
                    key={g["group_id"]}
                    className="flex min-h-11 items-center gap-3 text-sm"
                >
                    <input
                        type="checkbox"
                        data-testid="product-addon"
                        checked={g["group_id"] in picked}
                        disabled={not can_manage}
                        onChange={lambda { set_chosen(
                            [
                                x
                                for x in picked
                                if x != g["group_id"]
                            ]
                                if g["group_id"] in picked
                                else picked + [g["group_id"]]
                        ); }}
                        className="size-5"
                    />
                    <span>
                        {g["name"]}
                        <span className="text-muted-foreground">
                            {f" · {', '.join([o['name'] for o in g['options']][:4])}"}
                        </span>
                    </span>
                </label> for g in listed
            ]}
            {can_manage
                and len(listed) > 0
                and <Button
                    type="button"
                    variant="outline"
                    className="min-h-11 w-fit px-4"
                    disabled={busy}
                    onClick={save}
                >
                    Save add-ons
                </Button>}
        </section>;
}

def _rows_of(product: dict[str, any]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return [
        {
            "label": c["label"],
            "quantity": str(c["quantity"]),
            "variant_ids": list(c["variant_ids"])
        } for c in product["components"]
    ]
        or [{"label": "", "quantity": "1", "variant_ids": []}];
}

def:pub SnackComponents(
    slug: str,
    product: dict[str, any],  # jac:ignore[W1037]
    permissions: list[str],
    on_change: any  # jac:ignore[W1037] (product) -> None
) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    [variants, set_variants] = useState([]);
    [rows, set_rows] = useState(_rows_of(product));
    [errors, set_errors] = useState({});
    [message, set_message] = useState("");
    [busy, set_busy] = useState(False);
    product_id: str = product["product_id"];

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_snack_variants(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_snack_variants failed", e);
            return;
        }
        if answer["ok"] {
            set_variants(answer["variants"]);
        }
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, product_id]);

    parts: list[dict[str, any]] = rows;  # jac:ignore[W1037]
    choices: list[dict[str, str]] = variants;
    field_errors: dict[str, str] = errors;

    def put_row(i: int, key: str, value: any) {  # jac:ignore[W1037]
        set_rows(
            [dict(r, **{key: value}) if n == i else r for (n, r) in enumerate(parts)]
        );
    }

    def toggle(i: int, variant_id: str) {
        picked: list[str] = parts[i]["variant_ids"];
        put_row(
            i,
            "variant_ids",
            [
                x
                for x in picked
                if x != variant_id
            ]
                if variant_id in picked
                else picked + [variant_id]
        );
    }

    def err(field: str) -> str {
        return field_errors[problem_id(field)] or "";
    }

    async def save {
        components = [
            {
                "label": r["label"],
                "quantity": int(r["quantity"])
                    if r["quantity"].strip().isdigit()
                    else 0,
                "variant_ids": r["variant_ids"]
            } for r in parts
        ];
        set_busy(True);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await set_snack_combo_components(slug, product_id, components);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("set_snack_combo_components failed", e);
        }
        set_busy(False);
        if answer is None {
            set_message("We couldn't save that. Try again.");
            return;
        }
        if not answer["ok"] {
            shown: dict[str, str] = {};
            for p in answer["error"].get("problems", []) or [] {
                shown[problem_id(p["field"])] = p["message"];
            }
            set_errors(shown);
            if not shown {
                set_message(answer["error"]["message"]);
            }
            return;
        }
        set_errors({});
        set_message("Saved what the combo includes.");
        on_change(answer["product"]);
    }

    def Part(r: dict[str, any], i: int) -> JsxElement {  # jac:ignore[W1037]
        picked: list[str] = r["variant_ids"];
        return
            <li
                key={f"part-{i}"}
                data-testid="combo-component"
                className="flex flex-col gap-3 rounded-md border p-3"
            >
                <div className="grid gap-3 sm:grid-cols-[1fr_8rem_auto] sm:items-end">
                    <TextField
                        field_id={problem_id(f"components[{i}].label")}
                        label={f"Item {i + 1}"}
                        value={r["label"]}
                        error={err(f"components[{i}].label")}
                        on_value={lambda (text: str) { put_row(i, "label", text); }}
                        hint="Like Popcorn or Drinks."
                    />
                    <TextField
                        field_id={problem_id(f"components[{i}].quantity")}
                        label="How many"
                        value={r["quantity"]}
                        error={err(f"components[{i}].quantity")}
                        on_value={lambda (text: str) { put_row(i, "quantity", text); }}
                        input_mode="numeric"
                    />
                    {can_manage
                        and <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11 px-3"
                            aria-label={f"Remove item {i + 1}"}
                            disabled={len(parts) == 1}
                            onClick={lambda { set_rows(
                                [
                                    x
                                    for (n, x) in enumerate(parts)
                                    if n != i
                                ]
                            ); }}
                        >
                            Remove
                        </Button>}
                </div>
                <fieldset className="flex flex-col gap-1">
                    <legend className="mb-1 text-sm font-medium">
                        {"Always this product"
                            if len(picked) == 1
                            else "Customers choose from these"}
                    </legend>
                    <div
                        className="grid max-h-56 gap-x-4 overflow-y-auto sm:grid-cols-2"
                    >
                        {[
                            <label
                                key={v["variant_id"]}
                                className="flex min-h-11 items-center gap-3 text-sm"
                            >
                                <input
                                    type="checkbox"
                                    data-testid="combo-choice"
                                    checked={v["variant_id"] in picked}
                                    disabled={not can_manage}
                                    onChange={lambda { toggle(i, v["variant_id"]); }}
                                    className="size-5"
                                />
                                {v["name"]}
                            </label> for v in choices
                        ]}
                    </div>
                    {err(f"components[{i}].variant_ids")
                        and <FieldError
                            field_id={problem_id(f"components[{i}].variant_ids")}
                            error={err(f"components[{i}].variant_ids")}
                        />}
                </fieldset>
            </li>;
    }

    return
        <section
            aria-labelledby="components-title"
            data-testid="combo-components"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h3 id="components-title" className="text-lg font-semibold">
                What the combo includes
            </h3>
            <p className="text-sm text-muted-foreground">
                Tick one product to always include it, or several to let customers choose. The combo sells only where each item can be filled.
            </p>
            <p
                role="status"
                aria-live="polite"
                data-testid="components-message"
                className="text-sm empty:hidden"
            >
                {message}
            </p>
            {err("components")
                and <FieldError
                    field_id={problem_id("components")}
                    error={err("components")}
                />}
            <ol className="flex flex-col gap-3">
                {[Part(r, i) for (i, r) in enumerate(parts)]}
            </ol>
            {can_manage
                and <div className="flex flex-wrap gap-2">
                    <Button
                        type="button"
                        variant="outline"
                        className="min-h-11 px-4"
                        disabled={len(parts) >= COMPONENTS_MAX}
                        onClick={lambda { set_rows(
                            parts + [{"label": "", "quantity": "1", "variant_ids": []}]
                        ); }}
                    >
                        Add an item
                    </Button>
                    <Button
                        type="button"
                        className="min-h-11 px-4"
                        disabled={busy}
                        onClick={save}
                    >
                        Save what it includes
                    </Button>
                </div>}
        </section>;
}
