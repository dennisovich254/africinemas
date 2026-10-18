"""`/app/:slug/snacks/import`: import and export the snack catalog as CSV (P12.5; design
guide §4C).

Four steps, as the guide sets out:
1. Upload: choose a CSV file (or download the template, or export the catalog).
2. Map: each field's column, found by its usual name and changeable.
3. Preview: the products and variants that will be created or updated, and every bad
   row with its row number and what to fix. Nothing is saved yet.
4. Import: only when the preview has no problems; the result says what changed.

"Make missing categories" makes categories the file names that the cinema doesn't have
yet; otherwise those rows are problems.
"""

import from react { useState }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from core.snacks.tools_api {
    preview_snack_import,  # jac:ignore[W2037] authenticated endpoint
    import_snack_catalog,  # jac:ignore[W2037]
    export_snack_catalog  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from .form_parts { on_input }
import from .snack_view { SnackSubnav, snack_path, price_text, with_field }

glob FIELD_LABELS: list[tuple[str, str, bool]] = [
         ("product_name", "Product name", True),
         ("category", "Category", True),
         ("sku", "SKU", True),
         ("price", "Price", True),
         ("variant", "Variant (size or flavour)", False),
         ("option", "Option name (Size)", False),
         ("brand", "Brand", False),
         ("currency", "Currency", False)
     ],
     TEMPLATE_CSV: str = "product_name,category,brand,option,variant,sku,price,currency\nPopcorn,Popcorn,,Size,Small,POP-SM,200,KES\nPopcorn,Popcorn,,Size,Medium,POP-MD,300,KES\nCoca-Cola,Beverages,Coca-Cola,Size,500 ml,COKE-500,150,KES\nBottled Water,Beverages,,,,WATER-500,100,KES\n",
     SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm";

def save_file(name: str, text: str) {
    # Hands the visitor a file (the template or the export).
    win: any = window;  # jac:ignore[W1037,W2001]
    blob: any = new(win.Blob, [text], {"type": "text/csv"});  # jac:ignore[W1037]
    url: str = win.URL.createObjectURL(blob);
    link: any = win.document.createElement("a");  # jac:ignore[W1037,W6001]
    link.href = url;
    link.download = name;
    link.click();
    win.URL.revokeObjectURL(url);
}

def read_text(file: any) -> any {  # jac:ignore[W1037]
    # A promise of a chosen file's text.
    return file.text();
}

def:pub SnackImportPage(slug: str, permissions: list[str]) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    [text, set_text] = useState("");
    [file_name, set_file_name] = useState("");
    [mapping, set_mapping] = useState({});
    [create, set_create] = useState(False);
    [preview, set_preview] = useState(None);
    [result, set_result] = useState(None);
    [message, set_message] = useState("");
    [busy, set_busy] = useState(False);

    async def run_preview(csv_text: str, chosen: dict[str, str], make: bool) {
        set_busy(True);
        set_message("");
        set_result(None);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await preview_snack_import(slug, csv_text, chosen, make);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("preview_snack_import failed", e);
        }
        set_busy(False);
        if answer is None {
            set_message(
                "We couldn't read that file. Check your connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            set_preview(None);
            set_message(answer["error"]["message"]);
            return;
        }
        set_mapping(answer["mapping"]);
        set_preview(answer);
    }

    async def choose(e: any) {  # jac:ignore[W1037]
        file: any = e.target.files[0];  # jac:ignore[W1037]
        if not file {
            return;
        }
        loaded: str = "";
        try {
            loaded = await read_text(file);
        } except Exception as err {
            console.warn("reading the CSV failed", err);
            set_message("We couldn't read that file. Choose a CSV file.");
            return;
        }
        set_text(loaded);
        set_file_name(file.name);
        await run_preview(loaded, {}, create);
    }

    async def do_import {
        set_busy(True);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        chosen: dict[str, str] = mapping;
        try {
            answer = await import_snack_catalog(slug, text, chosen, create);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("import_snack_catalog failed", e);
        }
        set_busy(False);
        if answer is None {
            set_message(
                "We couldn't import that. Check your connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        set_result(answer["summary"]);
        set_preview(None);
        set_text("");
        set_file_name("");
    }

    async def export_catalog {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await export_snack_catalog(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("export_snack_catalog failed", e);
        }
        if answer is None or not answer["ok"] {
            set_message("We couldn't export the catalog. Try again.");
            return;
        }
        save_file("snack-catalog.csv", answer["csv"]);
    }

    shown: dict[str, any] | None = preview;  # jac:ignore[W1037]
    done: dict[str, int] | None = result;
    chosen: dict[str, str] = mapping;
    headers: list[str] = shown["headers"] if shown is not None else [];
    errors: list[dict[str, any]] = shown["errors"] if shown is not None else [];  # jac:ignore[W1037]
    products: list[dict[str, any]] = shown["products"] if shown is not None else [];  # jac:ignore[W1037]

    def remap(field: str, column: str) {
        changed = with_field(chosen, field, column);
        set_mapping(changed);
        run_preview(text, changed, create);
    }

    def toggle_create {
        set_create(not create);
        if text {
            run_preview(text, chosen, not create);
        }
    }

    return
        <div className="flex flex-col gap-6" data-testid="snack-import">
            <SnackSubnav slug={slug} current="import"/>
            <div className="flex flex-col gap-1">
                <h2 className="text-xl font-semibold">Import & export</h2>
                <p className="text-sm text-muted-foreground">
                    Add or update many products at once from a CSV file: one row per variant. Products already in your catalog (same name) are updated, their variants matched by SKU.
                </p>
            </div>
            <div className="flex flex-wrap gap-2">
                <Button
                    variant="outline"
                    className="min-h-11 px-4"
                    onClick={lambda { save_file("snack-template.csv", TEMPLATE_CSV); }}
                >
                    Download the template
                </Button>
                <Button
                    variant="outline"
                    className="min-h-11 px-4"
                    data-testid="export-catalog"
                    onClick={export_catalog}
                >
                    Export your catalog
                </Button>
            </div>
            <p
                role="status"
                aria-live="polite"
                data-testid="import-message"
                className="text-sm empty:hidden"
            >
                {message}
            </p>
            {done is not None
                and <Alert data-testid="import-result">
                    <AlertDescription>
                        {f"Imported: {done['products_created']} new products, {done[
                            'products_updated'
                        ]} updated; {done['variants_created']} new variants, {done[
                            'variants_updated'
                        ]} updated"
                            + (
                                f"; {done['categories_created']} new categories."
                                    if done["categories_created"]
                                    else "."
                            )}{" "}
                        <AppLink
                            to={snack_path(slug)}
                            className="font-medium underline underline-offset-4"
                        >
                            See your products
                        </AppLink>
                    </AlertDescription>
                </Alert>}
            {can_manage
                and <section
                    aria-labelledby="upload-title"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                >
                    <h3 id="upload-title" className="text-lg font-semibold">
                        1. Choose a file
                    </h3>
                    <div className="flex flex-wrap items-center gap-3">
                        <label
                            className="inline-flex min-h-11 cursor-pointer items-center rounded-md bg-primary px-5 text-sm font-medium text-primary-foreground focus-within:outline-2 focus-within:outline-ring"
                        >
                            Choose a CSV file
                            <input
                                type="file"
                                accept=".csv,text/csv"
                                data-testid="import-file"
                                className="sr-only"
                                onChange={choose}
                            />
                        </label>
                        {file_name and <span className="text-sm">{file_name}</span>}
                    </div>
                    <label className="flex min-h-11 items-center gap-3 text-sm">
                        <input
                            type="checkbox"
                            data-testid="make-categories"
                            checked={create}
                            onChange={toggle_create}
                            className="size-5"
                        />
                        Make missing categories
                    </label>
                </section>}
            {shown is not None
                and <section
                    aria-labelledby="map-title"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                >
                    <h3 id="map-title" className="text-lg font-semibold">
                        2. Check the columns
                    </h3>
                    <div className="grid gap-3 sm:grid-cols-2">
                        {[
                            <div key={field} className="flex flex-col gap-1.5">
                                <Label htmlFor={f"map-{field}"}>
                                    {f"{label}{' (needed)' if needed else ''}"}
                                </Label>
                                <select
                                    id={f"map-{field}"}
                                    value={chosen.get(field, "")}
                                    onChange={on_input(
                                        lambda (column: str) { remap(field, column); }
                                    )}
                                    className={SELECT_CLASSES}
                                >
                                    <option value="">Not in this file</option>
                                    {[
                                        <option key={h} value={h}>{h}</option>
                                        for h in headers
                                    ]}
                                </select>
                            </div> for (field, label, needed) in FIELD_LABELS
                        ]}
                    </div>
                </section>}
            {shown is not None
                and <section
                    aria-labelledby="preview-title"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                >
                    <h3 id="preview-title" className="text-lg font-semibold">
                        3. Preview
                    </h3>
                    {len(errors) > 0
                        and <div
                            role="alert"
                            data-testid="import-errors"
                            className="flex flex-col gap-2"
                        >
                            <p className="font-medium text-destructive">
                                {f"{len(errors)} {'row needs'
                                    if len(errors) == 1
                                    else 'rows need'} fixing. Nothing will be imported until they're fixed."}
                            </p>
                            <ul className="flex flex-col gap-1 text-sm">
                                {[
                                    <li
                                        key={f"{e['row']}-{e['field']}-{i}"}
                                        data-testid="import-error"
                                    >
                                        {f"Row {e['row']}, {e['field'].replace(
                                            '_', ' '
                                        )}: {e['message']}"}
                                    </li> for (i, e) in enumerate(errors)
                                ]}
                            </ul>
                        </div>}
                    {len(errors) == 0
                        and <p className="text-sm" data-testid="import-summary">
                            {f"{shown['summary']['products_created']} new products and {shown[
                                'summary'
                            ]['products_updated']} to update; {shown['summary'][
                                'variants_created'
                            ]} new variants and {shown['summary'][
                                'variants_updated'
                            ]} to update."}
                        </p>}
                    {len(products) > 0
                        and <ul
                            className="flex flex-col gap-2"
                            data-testid="import-preview"
                        >
                            {[
                                <li
                                    key={p["name"]}
                                    data-testid="import-product"
                                    className="rounded-md border p-3 text-sm"
                                >
                                    <div className="flex flex-wrap items-center gap-2">
                                        <span className="font-medium">{p["name"]}</span>
                                        <span className="text-muted-foreground">
                                            {p["category"]}
                                        </span>
                                        <Badge
                                            variant={"secondary"
                                                if p["action"] == "update"
                                                else "default"}
                                        >
                                            {"Update"
                                                if p["action"] == "update"
                                                else "New"}
                                        </Badge>
                                    </div>
                                    <p className="text-muted-foreground">
                                        {" · ".join(
                                            [
                                                f"{v['label']} ({v['sku']}) KES {price_text(
                                                    v['price_cents']
                                                )}" for v in p["variants"]
                                            ]
                                        )}
                                    </p>
                                </li> for p in products
                            ]}
                        </ul>}
                </section>}
            {shown is not None
                and can_manage
                and <section
                    aria-labelledby="import-title"
                    className="flex flex-col gap-3"
                >
                    <h3 id="import-title" className="text-lg font-semibold">
                        4. Import
                    </h3>
                    <Button
                        className="min-h-11 w-fit px-5"
                        data-testid="run-import"
                        disabled={busy or len(errors) > 0}
                        onClick={do_import}
                    >
                        Import
                    </Button>
                    <p className="text-sm text-muted-foreground">
                        New products arrive as drafts, so nothing goes on sale until you publish it.
                    </p>
                </section>}
        </div>;
}
