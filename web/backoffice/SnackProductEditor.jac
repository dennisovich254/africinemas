"""`/app/:slug/snacks/new` and `/app/:slug/snacks/:id`: the product editor (P12.1; design
guide §3).

One page with clear sections:
1. Product information: name, category (from the Categories page), brand, description,
   tags.
2. Images (after the first save): up to five, the first is the main one.
3. Variants & pricing: "Single item" or "Has variants". With variants, up to two options
   (Size, Flavour) each with its values ("Small, Medium, Large"); "Create variants" adds
   the missing combinations as rows, never removing one; each row has its SKU, barcode,
   price, Available and Track stock, and can be removed (a combination the cinema
   doesn't sell). A new product in Popcorn or Beverages starts with the usual sizes.
4. For a combo, what it includes; for any product, its add-ons (SnackExtrasParts.jac,
   P12.3). At each venue (SnackVenues.jac, P12.2): where it's sold, and each variant's
   availability and price at a venue.
5. The side panel (below the form on a phone, where a bar fixed to the bottom of the
   screen keeps Save and Publish in reach): status, the storefront preview (main image, name, "From KES 200"),
   and the actions for the status: Save draft and Publish (draft), Save changes and
   Unpublish (active), Restore (archived), Archive, and Delete (drafts only, asks first).

Saving keeps the page and what was typed; problems come back by field and show beside
it ("variants[1].price_cents" under that row's price). Leaving with unsaved changes
asks first.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useNavigate, useLocation }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.snacks.product_api {
    get_snack_product,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    save_snack_product,  # jac:ignore[W2037]
    publish_snack_product,  # jac:ignore[W2037]
    unpublish_snack_product,  # jac:ignore[W2037]
    archive_snack_product,  # jac:ignore[W2037]
    restore_snack_product,  # jac:ignore[W2037]
    delete_snack_product,  # jac:ignore[W2037]
    upload_snack_image,  # jac:ignore[W2037]
    remove_snack_image  # jac:ignore[W2037]
}
import from core.snacks.category_api { list_snack_categories }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from ..shell.AppLink { AppLink }
import from .form_parts {
    TextField,
    FieldError,
    ConfirmDelete,
    on_input,
    read_as_base64
}
import from .snack_view {
    snack_path,
    status_label,
    problem_id,
    price_text,
    price_cents_of,
    split_values,
    blank_row,
    generate_rows,
    with_field,
    template_form,
    TEMPLATES
}
import from core.snacks.tools_api { duplicate_snack_product }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from .SnackProductsPage { ProductThumb }
import from .SnackVenues { SnackVenues }
import from .SnackExtrasParts { SnackAddonPicker, SnackComponents }

glob IMAGE_TYPES: str = "image/png,image/jpeg,image/webp",
     IMAGES_MAX: int = 5,
     SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm",
     CELL_INPUT: str = "min-h-11 w-full min-w-0 rounded-md border border-input bg-background px-2 text-sm",
     # Sizes a new product starts with, by category name (the user can change them).
     SUGGESTED: dict[str, list[str]] = {
         "popcorn": ["Small", "Medium", "Large"],
         "beverages": ["300 ml", "500 ml", "1 litre"]
     };

def _blank_form -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "name": "",
        "brand": "",
        "description": "",
        "tags": "",
        "category_id": "",
        "kind": "single",
        "options": [],
        "rows": [blank_row([])]
    };
}

def _form_of(p: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    variants: list[dict[str, any]] = p["variants"];  # jac:ignore[W1037]
    names: list[str] = p["option_names"];
    return {
        "name": p["name"],
        "brand": p["brand"],
        "description": p["description"],
        "tags": ", ".join(p["tags"]),
        "category_id": p["category_id"],
        "kind": p["kind"],
        "options": [
            {
                "name": n,
                "values": ", ".join(
                    list(
                        dict.fromkeys(
                            [
                                v["option_values"][i]
                                for v in variants
                                if len(v["option_values"]) > i
                            ]
                        )
                    )
                )
            } for (i, n) in enumerate(names)
        ],
        "rows": [
            {
                "variant_id": v["variant_id"],
                "option_values": v["option_values"],
                "sku": v["sku"],
                "barcode": v["barcode"],
                "price": price_text(v["price_cents"]),
                "available": v["available"],
                "track_stock": v["track_stock"]
            } for v in variants
        ]
            or [blank_row([])]
    };
}

def:pub SnackProductEditor(
    slug: str, product_id: str, permissions: list[str]
) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    is_new = product_id == "new";
    nav: any = useNavigate();  # jac:ignore[W1037,W1051]
    [product, set_product] = useState(None);
    [categories, set_categories] = useState([]);
    [form, set_form] = useState(_blank_form());
    [dirty, set_dirty] = useState(False);
    [errors, set_errors] = useState({});
    # A new product's first save moves to its own address, which builds a fresh editor;
    # what the save said comes along in the navigation's state.
    arrived: any = useLocation();  # jac:ignore[W1037,W1051]
    [message, set_message] = useState(
        arrived.state["message"] if arrived.state and arrived.state["message"] else ""
    );
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [asking, set_asking] = useState(False);
    [loaded, set_loaded] = useState(False);
    # A new product starts from a template (P12.5): asked in the address ("Add another"
    # keeps the category), or chosen first on the page.
    win: any = window;  # jac:ignore[W1037,W2001]
    query: any = new(win.URLSearchParams, win.location.search);  # jac:ignore[W1037]
    asked_template: str = query.get("template") or "";
    asked_category: str = query.get("category") or "";
    [started, set_started] = useState(not is_new or bool(asked_template));

    async def load {
        found: any = None;  # jac:ignore[W1037]
        got: any = None;  # jac:ignore[W1037]
        try {
            found = await list_snack_categories(slug);  # jac:ignore[W2037]
            if not is_new {
                got = await get_snack_product(slug, product_id);  # jac:ignore[W2037]
            }
        } except Exception as e {
            console.warn("loading the product failed", e);
            set_failed("We couldn't load this product. Refresh the page to try again.");
            return;
        }
        kinds: list[dict[str, any]] = found["categories"] if found["ok"] else [];  # jac:ignore[W1037]
        set_categories(
            [
                c
                for c in kinds
                if c["status"] == "active"
            ]
        );
        if got is not None {
            if not got["ok"] {
                set_failed(got["error"]["message"]);
                return;
            }
            set_product(got["product"]);
            set_form(_form_of(got["product"]));
        } elif asked_template {
            set_form(
                template_form(
                    asked_template if asked_template != "blank" else "",
                    kinds,
                    asked_category
                )
            );
        }
        set_loaded(True);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, product_id]);

    def warn_on_leave -> any {  # jac:ignore[W1037]
        # Leaving (closing or reloading the tab) with unsaved changes asks first.
        win: any = window;  # jac:ignore[W1037,W2001]
        def handler(e: any) {  # jac:ignore[W1037]
            if dirty {
                e.preventDefault();
                e.returnValue = "";
            }
        }
        win.addEventListener("beforeunload", handler);
        return lambda { win.removeEventListener("beforeunload", handler); };
    }
    useEffect(warn_on_leave, [dirty]);

    values: dict[str, any] = form;  # jac:ignore[W1037]
    kinds: list[dict[str, any]] = categories;  # jac:ignore[W1037]
    options: list[dict[str, str]] = values["options"];
    rows: list[dict[str, any]] = values["rows"];  # jac:ignore[W1037]
    field_errors: dict[str, str] = errors;
    shown_product: dict[str, any] | None = product;  # jac:ignore[W1037]
    status: str = shown_product["status"] if shown_product is not None else "draft";
    editable = can_manage and status != "archived";

    # Every change applies to the latest form (React's functional update), never to a
    # copy from the last render, so quick edits one after another can't undo each other.
    def change(update: any) {  # jac:ignore[W1037]
        set_form(update);
        set_dirty(True);
    }

    def put(key: str, value: any) {  # jac:ignore[W1037]
        def update(prev: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
            changed: dict[str, any] = dict(prev);  # jac:ignore[W1037]
            changed[key] = value;
            return changed;
        }
        change(update);
    }

    def put_option(i: int, key: str, text: str) {
        def update(prev: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
            changed: dict[str, any] = dict(prev);  # jac:ignore[W1037]
            changed["options"] = [
                with_field(o, key, text) if n == i else o
                for (n, o) in enumerate(prev["options"])
            ];
            return changed;
        }
        change(update);
    }

    def put_row(i: int, key: str, value: any) {  # jac:ignore[W1037]
        def update(prev: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
            changed: dict[str, any] = dict(prev);  # jac:ignore[W1037]
            changed["rows"] = [
                with_field(r, key, value) if n == i else r
                for (n, r) in enumerate(prev["rows"])
            ];
            return changed;
        }
        change(update);
    }

    def choose_kind(kind: str) {
        def update(prev: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
            return kind_change(prev, kind);
        }
        change(update);
    }

    def kind_change(values: dict[str, any], kind: str) -> dict[str, any] {  # jac:ignore[W1037]
        rows: list[dict[str, any]] = values["rows"];  # jac:ignore[W1037]
        options: list[dict[str, str]] = values["options"];
        changed: dict[str, any] = dict(values);  # jac:ignore[W1037]
        changed["kind"] = kind;
        if kind in ["single", "combo"] {
            first = dict(rows[0]) if rows else blank_row([]);
            first["option_values"] = [];
            changed["options"] = [];
            changed["rows"] = [first];
        } elif not options {
            names = [
                c["name"].lower()
                for c in kinds
                if c["category_id"] == values["category_id"]
            ];
            suggested = SUGGESTED.get(names[0] if names else "", []);
            changed["options"] = [{"name": "Size", "values": ", ".join(suggested)}];
            changed["rows"] = generate_rows([suggested], []) if suggested else [];
        }
        return changed;
    }

    def add_option {
        put("options", options + [{"name": "", "values": ""}]);
    }

    def create_variants {
        lists = [split_values(o["values"]) for o in options];
        kept = [
            r
            for r in rows
            if len(r["option_values"]) == len(options)
        ];
        put("rows", generate_rows(lists, kept));
    }

    def payload -> any {  # jac:ignore[W1037]
        # The editor's fields as the server takes them, or None after showing a price
        # that can't be read.
        shown: dict[str, str] = {};
        variants: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for (i, r) in enumerate(rows) {
            cents = price_cents_of(r["price"]);
            if cents == -1 {
                shown[problem_id(f"variants[{i}].price_cents")] = "Enter the price in whole shillings, like 300.";
            }
            variants.append(
                {
                    "variant_id": r["variant_id"],
                    "option_values": r["option_values"]
                        if values["kind"] == "variants"
                        else [],
                    "sku": r["sku"],
                    "barcode": r["barcode"],
                    "price_cents": cents if cents != -1 else None,
                    "available": r["available"],
                    "track_stock": r["track_stock"]
                }
            );
        }
        if shown {
            set_errors(shown);
            return None;
        }
        return variants;
    }

    def show_refusal(answer: dict[str, any]) {  # jac:ignore[W1037]
        shown: dict[str, str] = {};
        problems: list[dict[str, str]] = answer["error"].get("problems", []) or [];
        for p in problems {
            shown[problem_id(p["field"])] = p["message"];
        }
        set_errors(shown);
        count = len(problems);
        set_message(
            answer["error"]["message"]
                if count == 0
                else f"{answer['error']['message']} {'1 thing needs'
                    if count == 1
                    else f'{count} things need'} fixing below."
        );
    }

    async def call(work: any) -> any {  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await work();
        } except Exception as e {
            console.warn("snack product change failed", e);
            set_message("We couldn't save that. Check your connection and try again.");
        }
        set_busy(False);
        if answer is not None and not answer["ok"] {
            show_refusal(answer);
            return None;
        }
        return answer;
    }

    async def save(then_publish: bool) {
        variants = payload();
        if variants is None {
            return;
        }
        def send -> any {  # jac:ignore[W1037]
            return save_snack_product(  # jac:ignore[W2037]
                slug,
                "" if is_new else product_id,
                values["name"],
                values["brand"],
                values["description"],
                split_values(values["tags"]),
                values["category_id"],
                values["kind"],
                [o["name"] for o in options],
                variants
            );
        }
        saved: any = await call(send);  # jac:ignore[W1037]
        if saved is None {
            return;
        }
        set_errors({});
        set_dirty(False);
        made: dict[str, any] = saved["product"];  # jac:ignore[W1037]
        set_product(made);
        set_form(_form_of(made));
        said = "Saved.";
        set_message(said);
        if then_publish {
            made_id: str = made["product_id"];
            def send_publish -> any {  # jac:ignore[W1037]
                return publish_snack_product(slug, made_id);  # jac:ignore[W2037]
            }
            published: any = await call(send_publish);  # jac:ignore[W1037]
            if published is not None {
                set_product(published["product"]);
                said = "Published. It's ready to sell.";
                set_message(said);
            }
        }
        if is_new {
            nav(  # jac:ignore[W1051]
                snack_path(slug, made["product_id"]),
                {"replace": True, "state": {"message": said}}
            );
        }
    }

    async def move(work: any, done: str) {  # jac:ignore[W1037]
        moved: any = await call(work);  # jac:ignore[W1037]
        if moved is not None {
            set_product(moved["product"]);
            set_message(done);
        }
    }

    async def remove {
        set_asking(False);
        def send -> any {  # jac:ignore[W1037]
            return delete_snack_product(slug, product_id);  # jac:ignore[W2037]
        }
        gone: any = await call(send);  # jac:ignore[W1037]
        if gone is not None {
            set_dirty(False);
            nav(snack_path(slug), {"replace": True});  # jac:ignore[W1051]
        }
    }

    async def add_image(e: any) {  # jac:ignore[W1037]
        file: any = e.target.files[0];  # jac:ignore[W1037]
        if not file {
            return;
        }
        encoded: str = "";
        try {
            encoded = await read_as_base64(file);
        } except Exception as err {
            console.warn("reading the image failed", err);
            set_message("We couldn't read that file. Try another.");
            return;
        }
        e.target.value = "";
        kind: str = file.type;
        def send -> any {  # jac:ignore[W1037]
            return upload_snack_image(slug, product_id, kind, encoded);  # jac:ignore[W2037]
        }
        added: any = await call(send);  # jac:ignore[W1037]
        if added is not None {
            set_product(added["product"]);
            set_message("Image added.");
        }
    }

    async def drop_image(image_id: str) {
        def send -> any {  # jac:ignore[W1037]
            return remove_snack_image(slug, product_id, image_id);  # jac:ignore[W2037]
        }
        gone: any = await call(send);  # jac:ignore[W1037]
        if gone is not None {
            set_product(gone["product"]);
            set_message("Image removed.");
        }
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
                Loading…
            </p>;
    }

    def start_with(key: str) {
        kinds_now: list[dict[str, any]] = categories;  # jac:ignore[W1037]
        set_form(template_form(key, kinds_now, asked_category));
        set_started(True);
    }

    if is_new and not started {
        return
            <div className="flex flex-col gap-4" data-testid="template-picker">
                <AppLink
                    to={snack_path(slug)}
                    className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline underline-offset-4"
                >
                    ← Products
                </AppLink>
                <h2 className="text-xl font-semibold">What would you like to add?</h2>
                <p className="text-sm text-muted-foreground">
                    Start from a template and change anything you like.
                </p>
                <div className="grid gap-3 sm:grid-cols-2">
                    {[
                        <button
                            key={t["key"]}
                            type="button"
                            data-testid={f"template-{t['key']}"}
                            onClick={lambda { start_with(t["key"]); }}
                            className="flex min-h-20 flex-col items-start justify-center gap-1 rounded-lg border bg-card p-4 text-left hover:bg-muted/50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                        >
                            <span className="font-semibold">{t["title"]}</span>
                            <span className="text-sm text-muted-foreground">
                                {t["detail"]}
                            </span>
                        </button> for t in TEMPLATES
                    ]}
                </div>
                <Button
                    variant="outline"
                    className="min-h-11 w-fit px-5"
                    data-testid="template-blank"
                    onClick={lambda { start_with(""); }}
                >
                    Start with a blank product
                </Button>
            </div>;
    }

    async def duplicate {
        def send -> any {  # jac:ignore[W1037]
            return duplicate_snack_product(slug, product_id);  # jac:ignore[W2037]
        }
        copy: any = await call(send);  # jac:ignore[W1037]
        if copy is not None {
            set_dirty(False);
            nav(snack_path(slug, copy["product"]["product_id"]));  # jac:ignore[W1051]
        }
    }

    def err(field: str) -> str {
        return field_errors[problem_id(field)] or "";
    }

    images: list[dict[str, str]] = shown_product["images"]
        if shown_product is not None
        else [];
    prices = [price_cents_of(r["price"]) for r in rows];
    priced = [
        c
        for c in prices
        if c is not None and c != -1
    ];
    preview_price = (
        ("From " if len(rows) > 1 else "") + f"KES {price_text(min(priced))}"
    )
        if priced
        else "No price yet";

    info = <section
        aria-labelledby="info-title"
        className="flex flex-col gap-4 rounded-lg border bg-card p-4"
    >
        <h3 id="info-title" className="text-lg font-semibold">Product information</h3>
        <TextField
            field_id={problem_id("name")}
            label="Product name"
            value={values["name"]}
            error={err("name")}
            on_value={lambda (text: str) { put("name", text); }}
            auto_focus={is_new}
        />
        <div className="grid gap-4 sm:grid-cols-2">
            <div className="flex min-w-0 flex-col gap-1.5">
                <Label htmlFor={problem_id("category_id")}>Category</Label>
                <select
                    id={problem_id("category_id")}
                    value={values["category_id"]}
                    disabled={not editable}
                    onChange={on_input(
                        lambda (text: str) { put("category_id", text); }
                    )}
                    className={SELECT_CLASSES}
                >
                    <option value="">Choose a category</option>
                    {[
                        <option key={c["category_id"]} value={c["category_id"]}>
                            {c["name"]}
                        </option> for c in kinds
                    ]}
                </select>
                {err("category_id")
                    and <FieldError
                        field_id={problem_id("category_id")}
                        error={err("category_id")}
                    />}
                {len(kinds) == 0
                    and <AppLink
                        to={snack_path(slug, "categories")}
                        className="text-sm font-medium underline underline-offset-4"
                    >
                        Add categories first
                    </AppLink>}
            </div>
            <TextField
                field_id={problem_id("brand")}
                label="Brand (optional)"
                value={values["brand"]}
                error={err("brand")}
                on_value={lambda (text: str) { put("brand", text); }}
            />
        </div>
        <TextField
            field_id={problem_id("description")}
            label="Description (optional)"
            value={values["description"]}
            error={err("description")}
            on_value={lambda (text: str) { put("description", text); }}
            multiline={True}
            hint="What customers see under the name."
        />
        <TextField
            field_id={problem_id("tags")}
            label="Tags (optional)"
            value={values["tags"]}
            error={err("tags")}
            on_value={lambda (text: str) { put("tags", text); }}
            hint="Separate with commas, like salty, vegan. They help staff search."
        />
    </section>;

    gallery = <section
        aria-labelledby="images-title"
        className="flex flex-col gap-3 rounded-lg border bg-card p-4"
    >
        <h3 id="images-title" className="text-lg font-semibold">Images</h3>
        {is_new
            and <p className="text-sm text-muted-foreground">
                Save the draft first, then add images here.
            </p>}
        {not is_new
            and <div className="flex flex-wrap items-center gap-3">
                {[
                    <div
                        key={i["image_id"]}
                        className="flex flex-col items-center gap-1"
                    >
                        <ProductThumb
                            slug={slug}
                            product_id={product_id}
                            image_id={i["image_id"]}
                            size="size-20"
                        />
                        {n == 0
                            and <span className="text-xs text-muted-foreground">
                                Main
                            </span>}
                        {editable
                            and <Button
                                type="button"
                                variant="ghost"
                                className="min-h-11 px-3"
                                aria-label={f"Remove image {n + 1}"}
                                disabled={busy}
                                onClick={lambda { drop_image(i["image_id"]); }}
                            >
                                Remove
                            </Button>}
                    </div> for (n, i) in enumerate(images)
                ]}
                {editable
                    and len(images) < IMAGES_MAX
                    and <label
                        className="inline-flex min-h-11 cursor-pointer items-center rounded-md border px-4 text-sm font-medium hover:bg-muted focus-within:outline-2 focus-within:outline-ring"
                    >
                        Add image
                        <input
                            type="file"
                            accept={IMAGE_TYPES}
                            data-testid="product-image-file"
                            className="sr-only"
                            onChange={add_image}
                        />
                    </label>}
                <p className="w-full text-sm text-muted-foreground">
                    JPEG, PNG or WebP, at least 200 x 200 pixels, up to 5 MB. The first image is the main one.
                </p>
            </div>}
    </section>;

    # Each variant is a row on a wide screen and a card on a phone: the same fields,
    # labelled on the phone, under the column headings on a wide screen.
    GRID = "grid gap-2 md:grid-cols-[minmax(7rem,1fr)_8rem_8rem_7rem_5.5rem_5.5rem_auto] md:items-start md:gap-3";
    CELL = "flex flex-col gap-1";
    LABEL = "text-xs font-medium text-muted-foreground md:sr-only";

    def RowCells(r: dict[str, any], i: int) -> JsxElement {  # jac:ignore[W1037]
        label = " · ".join(r["option_values"]) if r["option_values"] else "This item";
        def field(key: str, title: str, mode: str) -> JsxElement {
            fid = problem_id(f"variants[{i}].{key}");
            source = "price" if key == "price_cents" else key;
            return
                <div className={CELL}>
                    <label htmlFor={fid} className={LABEL}>{title}</label>
                    <input
                        id={fid}
                        aria-label={f"{title} for {label}"}
                        value={r[source]}
                        inputMode={mode}
                        disabled={not editable}
                        onChange={on_input(
                            lambda (text: str) { put_row(i, source, text); }
                        )}
                        className={CELL_INPUT}
                    />
                    {err(f"variants[{i}].{key}")
                        and <FieldError
                            field_id={fid}
                            error={err(f"variants[{i}].{key}")}
                        />}
                </div>;
        }
        def tick(key: str, title: str) -> JsxElement {
            return
                <label
                    className="flex min-h-11 items-center gap-2 text-sm md:justify-center"
                >
                    <input
                        type="checkbox"
                        aria-label={f"{title} for {label}"}
                        checked={r[key]}
                        disabled={not editable}
                        onChange={lambda { put_row(i, key, not r[key]); }}
                        className="size-5"
                    />
                    <span className="md:sr-only">{title}</span>
                </label>;
        }
        return
            <li
                key={f"row-{i}"}
                data-testid="variant-row"
                className={GRID
                    + " rounded-md border p-3 md:rounded-none md:border-0 md:border-t md:px-0 md:py-2"}
            >
                <div className="flex items-center justify-between gap-2 md:block">
                    <span className="text-sm font-semibold md:font-medium">
                        {label}
                    </span>
                    {editable
                        and values["kind"] == "variants"
                        and <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11 px-3 md:hidden"
                            aria-label={f"Remove {label}"}
                            onClick={lambda { put(
                                "rows",
                                [
                                    x
                                    for (n, x) in enumerate(rows)
                                    if n != i
                                ]
                            ); }}
                        >
                            Remove
                        </Button>}
                </div>
                <div className="grid grid-cols-2 gap-2 md:contents">
                    {field("sku", "SKU", "text")}{field(
                        "barcode", "Barcode", "numeric"
                    )}{field("price_cents", "Price (KES)", "decimal")}
                </div>
                <div className="flex flex-wrap gap-x-6 md:contents">
                    {tick("available", "Available")}{tick("track_stock", "Track stock")}
                </div>
                <div className="hidden md:block">
                    {editable
                        and values["kind"] == "variants"
                        and <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11 px-3"
                            aria-label={f"Remove {label}"}
                            onClick={lambda { put(
                                "rows",
                                [
                                    x
                                    for (n, x) in enumerate(rows)
                                    if n != i
                                ]
                            ); }}
                        >
                            Remove
                        </Button>}
                </div>
                {err(f"variants[{i}].option_values")
                    and <div className="md:col-span-7">
                        <FieldError
                            field_id={problem_id(f"variants[{i}].option_values")}
                            error={err(f"variants[{i}].option_values")}
                        />
                    </div>}
            </li>;
    }

    variants_section = <section
        aria-labelledby="variants-title"
        className="flex flex-col gap-4 rounded-lg border bg-card p-4"
    >
        <h3 id="variants-title" className="text-lg font-semibold">
            Variants & pricing
        </h3>
        <fieldset className="flex flex-col gap-2">
            <legend className="mb-1 text-sm font-medium">
                Does this product come in different sizes or flavours?
            </legend>
            {[
                <label key={kind} className="flex min-h-11 items-center gap-3 text-sm">
                    <input
                        type="radio"
                        name="kind"
                        data-testid={f"kind-{kind}"}
                        checked={values["kind"] == kind}
                        disabled={not editable}
                        onChange={lambda { choose_kind(kind); }}
                        className="size-5"
                    />
                    {words}
                </label>
                for (kind, words) in [
                    ("single", "No, it's a single item"),
                    ("variants", "Yes, it has variants (sizes or flavours)"),
                    ("combo", "It's a combo (several products at one price)")
                ]
            ]}
            {err("option_names")
                and <FieldError
                    field_id={problem_id("option_names")}
                    error={err("option_names")}
                />}
        </fieldset>
        {values["kind"] == "variants"
            and <div className="flex flex-col gap-3">
                {[
                    <div
                        key={f"option-{i}"}
                        className="grid gap-3 sm:grid-cols-[12rem_1fr]"
                    >
                        <TextField
                            field_id={f"option-name-{i}"}
                            label={f"Option {i + 1}"}
                            value={o["name"]}
                            on_value={lambda (text: str) { put_option(
                                i, "name", text
                            ); }}
                            hint="Like Size or Flavour."
                        />
                        <TextField
                            field_id={f"option-values-{i}"}
                            label="Values"
                            value={o["values"]}
                            on_value={lambda (text: str) { put_option(
                                i, "values", text
                            ); }}
                            hint="Separate with commas, like Small, Medium, Large."
                        />
                    </div> for (i, o) in enumerate(options)
                ]}
                {editable
                    and <div className="flex flex-wrap gap-2">
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            onClick={create_variants}
                        >
                            Create variants
                        </Button>
                        {len(options) < 2
                            and <Button
                                type="button"
                                variant="ghost"
                                className="min-h-11 px-4"
                                onClick={add_option}
                            >
                                Add another option
                            </Button>}
                    </div>}
                <p className="text-sm text-muted-foreground">
                    Create variants adds a row for each combination you don't have yet. Remove the ones you don't sell.
                </p>
            </div>}
        {err("variants")
            and <FieldError field_id={problem_id("variants")} error={err("variants")}/>}
        {len(rows) > 0
            and <div data-testid="variant-table" className="flex flex-col">
                <div
                    aria-hidden="true"
                    className={"hidden text-sm text-muted-foreground md:grid " + GRID}
                >
                    <span className="py-2 font-medium">Variant</span>
                    <span className="py-2 font-medium">SKU</span>
                    <span className="py-2 font-medium">Barcode</span>
                    <span className="py-2 font-medium">Price (KES)</span>
                    <span className="py-2 text-center font-medium">Available</span>
                    <span className="py-2 text-center font-medium">Track stock</span>
                    <span/>
                </div>
                <ul className="flex flex-col gap-3 md:gap-0">
                    {[RowCells(r, i) for (i, r) in enumerate(rows)]}
                </ul>
            </div>}
        <p className="text-sm text-muted-foreground">
            A draft can leave SKUs and prices empty; publishing needs them. Tick Track stock to count a variant on the Stock page.
        </p>
    </section>;

    def send_unpublish -> any {  # jac:ignore[W1037]
        return unpublish_snack_product(slug, product_id);  # jac:ignore[W2037]
    }

    def send_restore -> any {  # jac:ignore[W1037]
        return restore_snack_product(slug, product_id);  # jac:ignore[W2037]
    }

    def send_archive -> any {  # jac:ignore[W1037]
        return archive_snack_product(slug, product_id);  # jac:ignore[W2037]
    }

    actions = <div className="flex flex-col gap-2">
        {editable
            and status == "draft"
            and <Button
                className="min-h-11"
                disabled={busy}
                data-testid="publish"
                onClick={lambda { save(True); }}
            >
                Publish
            </Button>}{editable
            and <Button
                variant={"outline" if status == "draft" else "default"}
                className="min-h-11"
                disabled={busy}
                data-testid="save-product"
                onClick={lambda { save(False); }}
            >
                {"Save draft" if status == "draft" else "Save changes"}
            </Button>}{can_manage
            and status == "active"
            and <Button
                variant="outline"
                className="min-h-11"
                disabled={busy}
                onClick={lambda { move(
                    send_unpublish, "Unpublished: it's a draft again."
                ); }}
            >
                Unpublish
            </Button>}{can_manage
            and status == "archived"
            and <Button
                className="min-h-11"
                disabled={busy}
                onClick={lambda { move(send_restore, "Restored as a draft."); }}
            >
                Restore
            </Button>}{can_manage
            and not is_new
            and status != "archived"
            and <Button
                variant="ghost"
                className="min-h-11"
                disabled={busy}
                onClick={lambda { move(
                    send_archive,
                    "Archived: it's off the storefront and stays in your reports."
                ); }}
            >
                Archive
            </Button>}{can_manage
            and not is_new
            and status == "draft"
            and not asking
            and <Button
                variant="ghost"
                className="min-h-11"
                disabled={busy}
                onClick={lambda { set_asking(True); }}
            >
                Delete draft
            </Button>}{asking
            and <ConfirmDelete
                question={f"Delete {values['name'] or 'this draft'}?"}
                detail="It's gone for good. Archive it instead to keep it for your reports."
                confirm_label="Delete draft"
                on_confirm={remove}
                on_cancel={lambda { set_asking(False); }}
                busy={busy}
            />}
    </div>;

    side = <aside className="flex flex-col gap-4">
        <section
            aria-labelledby="publishing-title"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h3 id="publishing-title" className="text-lg font-semibold">Publishing</h3>
            <p className="flex items-center gap-2 text-sm">
                Status
                <Badge
                    variant={"default" if status == "active" else "secondary"}
                    data-testid="editor-status"
                >
                    {"New" if is_new else status_label(status)}
                </Badge>
            </p>
            {actions}
            {can_manage
                and not is_new
                and <div className="flex flex-col gap-2 border-t pt-3">
                    <Button
                        variant="outline"
                        className="min-h-11"
                        disabled={busy}
                        data-testid="duplicate-product"
                        onClick={duplicate}
                    >
                        Duplicate
                    </Button>
                    <AppLink
                        to={snack_path(
                            slug, f"new?category={values['category_id']}&template=blank"
                        )}
                        testid="add-another"
                        className="inline-flex min-h-11 items-center justify-center rounded-md px-4 text-sm font-medium underline underline-offset-4"
                    >
                        {"Add another product"
                            + (
                                f" in {[
                                    c['name']
                                    for c in kinds
                                    if c['category_id'] == values['category_id']
                                ][0]}"
                                    if [
                                        c
                                        for c in kinds
                                        if c["category_id"] == values["category_id"]
                                    ]
                                    else ""
                            )}
                    </AppLink>
                </div>}
        </section>
        <section
            aria-labelledby="preview-title"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h3 id="preview-title" className="text-lg font-semibold">
                Storefront preview
            </h3>
            <div className="flex items-center gap-3">
                {len(images) > 0
                    and <ProductThumb
                        slug={slug}
                        product_id={product_id}
                        image_id={images[0]["image_id"]}
                        size="size-16"
                    />}
                <div className="flex flex-col">
                    <span className="font-medium">
                        {values["name"] or "Product name"}
                    </span>
                    <span
                        className="text-sm text-muted-foreground"
                        data-testid="preview-price"
                    >
                        {preview_price}
                    </span>
                </div>
            </div>
        </section>
    </aside>;

    return
        <div className="flex flex-col gap-4" data-testid="snack-editor">
            <AppLink
                to={snack_path(slug)}
                className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline underline-offset-4"
            >
                ← Products
            </AppLink>
            <div className="flex flex-wrap items-center gap-3">
                <h2 className="text-xl font-semibold">
                    {"Add product" if is_new else values["name"] or "Product"}
                </h2>
                {dirty
                    and <span className="text-sm text-muted-foreground">
                        Unsaved changes
                    </span>}
            </div>
            <p
                role="status"
                aria-live="polite"
                data-testid="editor-message"
                className="text-sm empty:hidden"
            >
                {message}
            </p>
            <div className="grid gap-4 pb-24 lg:grid-cols-[1fr_20rem] lg:pb-0">
                <div className="flex min-w-0 flex-col gap-4">
                    {info}{gallery}{variants_section}{shown_product is not None
                        and not dirty
                        and shown_product["kind"] == "combo"
                        and <SnackComponents
                            slug={slug}
                            product={shown_product}
                            permissions={permissions}
                            on_change={set_product}
                        />}{shown_product is not None
                        and not dirty
                        and <SnackAddonPicker
                            slug={slug}
                            product={shown_product}
                            permissions={permissions}
                            on_change={set_product}
                        />}{shown_product is not None
                        and not dirty
                        and <SnackVenues
                            slug={slug}
                            product={shown_product}
                            permissions={permissions}
                            on_change={set_product}
                        />}{dirty
                        and not is_new
                        and <p className="text-sm text-muted-foreground">
                            Save your changes to set availability and prices at each venue.
                        </p>}
                </div>
                {side}
            </div>
            {editable
                and <div
                    data-testid="mobile-save-bar"
                    className="fixed inset-x-0 bottom-0 z-20 flex gap-2 border-t bg-card/95 p-3 backdrop-blur lg:hidden"
                >
                    <Button
                        variant={"outline" if status == "draft" else "default"}
                        className="min-h-11 flex-1"
                        disabled={busy}
                        data-testid="mobile-save"
                        onClick={lambda { save(False); }}
                    >
                        {"Save draft" if status == "draft" else "Save changes"}
                    </Button>
                    {status == "draft"
                        and <Button
                            className="min-h-11 flex-1"
                            disabled={busy}
                            data-testid="mobile-publish"
                            onClick={lambda { save(True); }}
                        >
                            Publish
                        </Button>}
                </div>}
        </div>;
}
