"""`/app/:slug/snacks/categories`: snack categories (P12.1; design guide §6).

Each category shows how many products it has and where it sits in the storefront's
order. Managers add categories (a new catalog is offered the usual six in one tap),
rename them in place, move them up and down, and archive or restore them; an archived
category keeps its products for reports and leaves the storefront. Problems show beside
their field.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.snacks.category_api {
    list_snack_categories,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    create_snack_category,  # jac:ignore[W2037]
    add_default_snack_categories,  # jac:ignore[W2037]
    rename_snack_category,  # jac:ignore[W2037]
    reorder_snack_categories,  # jac:ignore[W2037]
    set_snack_category_status  # jac:ignore[W2037]
}
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from .form_parts { TextField, FieldError, submit_with, on_input }
import from .snack_view { SnackSubnav }

def:pub swapped(ids: list[str], at: int, step: int) -> list[str] {
    # `ids` with the one at `at` swapped with its neighbour `step` away.
    out = list(ids);
    to = at + step;
    if to < 0 or to >= len(out) {
        return out;
    }
    other = out[to];
    out[to] = out[at];
    out[at] = other;
    return out;
}

def:pub SnackCategoriesPage(slug: str, permissions: list[str]) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    [categories, set_categories] = useState(None);
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [message, set_message] = useState("");
    [errors, set_errors] = useState({});
    [new_name, set_new_name] = useState("");
    [renaming, set_renaming] = useState("");
    [rename_to, set_rename_to] = useState("");

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_snack_categories(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_snack_categories failed", e);
            set_failed(
                "We couldn't load your categories. Refresh the page to try again."
            );
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_categories(answer["categories"]);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    async def run(work: any, done: str, field_id: str = "") -> bool {  # jac:ignore[W1037]
        answer: any = None;  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        try {
            answer = await work();
        } except Exception as e {
            console.warn("category change failed", e);
            set_busy(False);
            set_message("We couldn't save that. Check your connection and try again.");
            return False;
        }
        set_busy(False);
        if not answer["ok"] {
            shown: dict[str, str] = {};
            if field_id {
                shown[field_id] = answer["error"]["message"];
            } else {
                set_message(answer["error"]["message"]);
            }
            set_errors(shown);
            return False;
        }
        set_errors({});
        # Announced once the list shows the change, never before.
        await load();
        set_message(done);
        return True;
    }

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if categories is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading categories…
            </p>;
    }
    listed: list[dict[str, any]] = categories;  # jac:ignore[W1037]
    ids = [c["category_id"] for c in listed];
    field_errors: dict[str, str] = errors;

    def send_defaults -> any {  # jac:ignore[W1037]
        return add_default_snack_categories(slug);  # jac:ignore[W2037]
    }

    async def add {
        name: str = new_name;
        def send -> any {  # jac:ignore[W1037]
            return create_snack_category(slug, name);  # jac:ignore[W2037]
        }
        if await run(send, f"Added {name.strip()}.", "new-category") {
            set_new_name("");
        }
    }

    async def rename(category_id: str) {
        name: str = rename_to;
        def send -> any {  # jac:ignore[W1037]
            return rename_snack_category(slug, category_id, name);  # jac:ignore[W2037]
        }
        if await run(send, f"Renamed to {name.strip()}.", "rename-category") {
            set_renaming("");
        }
    }

    async def move(at: int, step: int, name: str) {
        order = swapped(ids, at, step);
        def send -> any {  # jac:ignore[W1037]
            return reorder_snack_categories(slug, order);  # jac:ignore[W2037]
        }
        await run(send, f"Moved {name} {'up' if step < 0 else 'down'}.");
    }

    async def set_status(c: dict[str, any], status: str) {  # jac:ignore[W1037]
        category_id: str = c["category_id"];
        def send -> any {  # jac:ignore[W1037]
            return set_snack_category_status(slug, category_id, status);  # jac:ignore[W2037]
        }
        await run(
            send,
            f"{c['name']} is {'archived' if status == 'archived' else 'active again'}."
        );
    }

    def Row(c: dict[str, any], at: int) -> JsxElement {  # jac:ignore[W1037]
        cid: str = c["category_id"];
        count: int = c["product_count"];
        if renaming == cid {
            return
                <li key={cid} className="rounded-lg border bg-card p-4">
                    <form
                        className="flex flex-wrap items-end gap-3"
                        onSubmit={submit_with(lambda { rename(cid); })}
                    >
                        <TextField
                            field_id="rename-category"
                            label={f"Rename {c['name']}"}
                            value={rename_to}
                            error={field_errors["rename-category"] or ""}
                            on_value={set_rename_to}
                            auto_focus={True}
                        />
                        <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                            Rename
                        </Button>
                        <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11 px-5"
                            onClick={lambda { set_renaming(""); }}
                        >
                            Cancel
                        </Button>
                    </form>
                </li>;
        }
        return
            <li
                key={cid}
                data-testid="category-row"
                className="flex flex-wrap items-center gap-3 rounded-lg border bg-card p-4"
            >
                <span className="w-8 text-sm text-muted-foreground tabular-nums">
                    {at + 1}
                </span>
                <div className="flex min-w-0 flex-1 flex-col">
                    <span className="font-medium" data-testid="category-name">
                        {c["name"]}
                    </span>
                    <span className="text-sm text-muted-foreground">
                        {"1 product" if count == 1 else f"{count} products"}
                    </span>
                </div>
                {c["status"] == "archived"
                    and <Badge variant="outline">Archived</Badge>}
                {can_manage
                    and <div className="flex flex-wrap gap-2">
                        <Button
                            variant="outline"
                            className="min-h-11 px-3"
                            aria-label={f"Rename {c['name']}"}
                            onClick={lambda {
                                set_renaming(cid);
                                set_rename_to(c["name"]);
                                set_errors({});
                            }}
                        >
                            Rename
                        </Button>
                        <Button
                            variant="outline"
                            className="min-h-11 px-3"
                            aria-label={f"Move {c['name']} up"}
                            disabled={busy or at == 0}
                            onClick={lambda { move(at, -1, c["name"]); }}
                        >
                            Move up
                        </Button>
                        <Button
                            variant="outline"
                            className="min-h-11 px-3"
                            aria-label={f"Move {c['name']} down"}
                            disabled={busy or at == len(ids) - 1}
                            onClick={lambda { move(at, 1, c["name"]); }}
                        >
                            Move down
                        </Button>
                        <Button
                            variant="outline"
                            className="min-h-11 px-3"
                            aria-label={f"{'Restore'
                                if c['status'] == 'archived'
                                else 'Archive'} {c['name']}"}
                            disabled={busy}
                            onClick={lambda { set_status(
                                c, "active" if c["status"] == "archived" else "archived"
                            ); }}
                        >
                            {"Restore" if c["status"] == "archived" else "Archive"}
                        </Button>
                    </div>}
            </li>;
    }

    return
        <div className="flex flex-col gap-6" data-testid="snack-categories">
            <SnackSubnav slug={slug} current="categories"/>
            <div className="flex flex-col gap-1">
                <h2 className="text-xl font-semibold">Categories</h2>
                <p className="text-sm text-muted-foreground">
                    How your snacks are grouped for staff and customers, in the order customers see them.
                </p>
            </div>
            <p
                role="status"
                aria-live="polite"
                data-testid="categories-message"
                className="text-sm empty:hidden"
            >
                {message}
            </p>
            {len(listed) == 0
                and <div className="flex flex-col gap-3 rounded-lg border bg-card p-6">
                    <h3 className="text-base font-semibold">No categories yet</h3>
                    <p className="text-sm text-muted-foreground">
                        Start with Popcorn, Beverages, Crisps & Chips, Candy & Chocolates, Hot Food and Combos & Deals. You can rename or archive them later.
                    </p>
                    {can_manage
                        and <Button
                            className="min-h-11 w-fit px-5"
                            disabled={busy}
                            onClick={lambda { run(
                                send_defaults, "Added the usual categories."
                            ); }}
                        >
                            Add the usual categories
                        </Button>}
                </div>}
            {len(listed) > 0
                and <ol className="flex flex-col gap-2" data-testid="category-list">
                    {[Row(c, i) for (i, c) in enumerate(listed)]}
                </ol>}
            {can_manage
                and <form
                    data-testid="add-category"
                    className="flex flex-col gap-1.5 border-t pt-6"
                    onSubmit={submit_with(lambda { add(); })}
                >
                    <Label htmlFor="new-category">New category</Label>
                    <div className="flex flex-wrap items-center gap-3">
                        <Input
                            id="new-category"
                            value={new_name}
                            aria-invalid={"true"
                                if field_errors["new-category"]
                                else "false"}
                            aria-describedby="new-category-hint"
                            onChange={on_input(set_new_name)}
                            className="min-h-11 w-full max-w-xs"
                        />
                        <Button
                            type="submit"
                            variant="outline"
                            className="min-h-11 px-5"
                            disabled={busy or not new_name.strip()}
                        >
                            Add category
                        </Button>
                    </div>
                    <p id="new-category-hint" className="text-sm text-muted-foreground">
                        Like Ice cream or Hot drinks.
                    </p>
                    {field_errors["new-category"]
                        and <FieldError
                            field_id="new-category"
                            error={field_errors["new-category"]}
                        />}
                </form>}
        </div>;
}
