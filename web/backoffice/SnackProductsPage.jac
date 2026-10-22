"""`/app/:slug/snacks`: the snack catalog's product list (P12.1; design guide §2B).

The cinema's products, with counts (all, active, drafts), a prominent search (name,
brand, SKU or barcode) and filters (category, status) that keep the page in place.
Each product shows its main image, name, "3 variants · POP-SM", category, its lowest
price ("From KES 200"), its status, and opens in the product editor. Managers tick
products to publish, archive or restore them together (P12.5); each answers for itself. Managers get "Add
product"; everyone with access can search and open products. On a phone the table
becomes a list of cards.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.snacks.tools_api { bulk_snack_products }  # jac:ignore[W2037] authenticated endpoint
import from core.snacks.product_api {
    list_snack_products,  # jac:ignore[W2037] authenticated endpoint
    get_snack_image  # jac:ignore[W2037]
}
import from core.snacks.category_api { list_snack_categories }  # jac:ignore[W2037] authenticated endpoint
import from ..shell.AppLink { AppLink }
import from .form_parts { on_input }
import from .snack_view { SnackSubnav, snack_path, status_label, price_text }

glob SELECT_CLASSES: str = "min-h-11 rounded-md border border-input bg-background px-3 text-sm";

def:pub ProductThumb(
    slug: str, product_id: str, image_id: str, size: str = "size-12"
) -> JsxElement {
    # A product's image (its main one unless `image_id` says), or a plain tile.
    [src, set_src] = useState("");

    async def load {
        if not image_id {
            set_src("");
            return;
        }
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await get_snack_image(slug, product_id, image_id);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("get_snack_image failed", e);
            return;
        }
        if answer["ok"] {
            set_src(f"data:{answer['content_type']};base64,{answer['data_base64']}");
        }
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [product_id, image_id]);
    return
        <span className={f"{size} shrink-0 overflow-hidden rounded-md border bg-muted"}>
            {src
                and <img
                    src={src}
                    alt=""
                    data-testid="product-image"
                    className="size-full object-cover"
                />}
        </span>;
}

def StatusBadge(status: str) -> JsxElement {
    variant = "default"
        if status == "active"
        else ("secondary" if status == "draft" else "outline");
    return
        <Badge variant={variant} data-testid="product-status">
            {status_label(status)}
        </Badge>;
}

def:pub SnackProductsPage(slug: str, permissions: list[str]) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    [products, set_products] = useState(None);
    [categories, set_categories] = useState([]);
    [search, set_search] = useState("");
    [category, set_category] = useState("");
    [status, set_status] = useState("");
    [failed, set_failed] = useState("");
    # Bulk actions (P12.5): the products ticked, and what the last action said.
    [selected, set_selected] = useState([]);
    [bulk_note, set_bulk_note] = useState("");
    [bulk_busy, set_bulk_busy] = useState(False);

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        found: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_snack_products(slug, "", "", "");  # jac:ignore[W2037]
            found = await list_snack_categories(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_snack_products failed", e);
            set_failed(
                "We couldn't load your products. Refresh the page to try again."
            );
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_products(answer["products"]);
        set_categories(found["categories"] if found["ok"] else []);
    }

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
    if products is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading products…
            </p>;
    }
    every: list[dict[str, any]] = products;  # jac:ignore[W1037]
    kinds: list[dict[str, any]] = categories;  # jac:ignore[W1037]
    wanted = search.strip().lower();

    def shown(p: dict[str, any]) -> bool {  # jac:ignore[W1037]
        # The same search the server runs, on the loaded list, so typing feels instant.
        if category and p["category_id"] != category {
            return False;
        }
        if status and p["status"] != status {
            return False;
        }
        if not wanted {
            return True;
        }
        texts = [p["name"], p["brand"], p["first_sku"]] + p.get("skus", []);
        return any(wanted in (t or "").lower() for t in texts);
    }

    listed = [
        p
        for p in every
        if shown(p)
    ];
    active = len(
        [
            p
            for p in every
            if p["status"] == "active"
        ]
    );
    drafts = len(
        [
            p
            for p in every
            if p["status"] == "draft"
        ]
    );

    def facts(p: dict[str, any]) -> str {  # jac:ignore[W1037]
        count: int = p["variant_count"];
        words = "1 variant" if count == 1 else f"{count} variants";
        # A SKU names one variant, so only a single item's is shown (each size has its
        # own; search finds a product by any of them).
        return f"{words} · {p['first_sku']}"
            if count == 1 and p["first_sku"]
            else words;
    }

    def price(p: dict[str, any]) -> str {  # jac:ignore[W1037]
        if p["price_from_cents"] is None {
            return "No price yet";
        }
        prefix = "From " if p["variant_count"] > 1 else "";
        return f"{prefix}KES {price_text(p['price_from_cents'])}";
    }

    ticked: list[str] = selected;

    def tick(product_id: str) {
        set_selected(
            [
                x
                for x in ticked
                if x != product_id
            ]
                if product_id in ticked
                else ticked + [product_id]
        );
    }

    async def bulk(action: str, words: str) {
        ids: list[str] = ticked;
        set_bulk_busy(True);
        set_bulk_note("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await bulk_snack_products(slug, ids, action);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("bulk_snack_products failed", e);
        }
        set_bulk_busy(False);
        if answer is None or not answer["ok"] {
            set_bulk_note(
                answer["error"]["message"]
                    if answer is not None
                    else "We couldn't do that. Try again."
            );
            return;
        }
        names = {p["product_id"]: p["name"] for p in every};
        failures = [
            f"{names.get(r['product_id'], 'A product')}: {r['message']}"
            for r in answer["results"]
            if not r["ok"]
        ];
        set_bulk_note(
            f"{words} {answer['done']} of {len(ids)}."
                + (" " + " ".join(failures) if failures else "")
        );
        set_selected([]);
        await load();
    }

    def Row(p: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        return
            <li
                key={p["product_id"]}
                data-testid="product-row"
                className="flex items-center gap-2"
            >
                {can_manage
                    and <input
                        type="checkbox"
                        data-testid="select-product"
                        aria-label={f"Select {p['name']}"}
                        checked={p["product_id"] in ticked}
                        onChange={lambda { tick(p["product_id"]); }}
                        className="size-5 shrink-0"
                    />}
                <AppLink
                    to={snack_path(slug, p["product_id"])}
                    className="grid min-h-16 min-w-0 flex-1 grid-cols-[auto_1fr_auto] items-center gap-3 rounded-lg border bg-card p-3 hover:bg-muted/50 md:grid-cols-[auto_2fr_1fr_1fr_auto]"
                >
                    <ProductThumb
                        slug={slug}
                        product_id={p["product_id"]}
                        image_id={p["image_id"]}
                    />
                    <span className="flex min-w-0 flex-col">
                        <span
                            className="truncate font-medium"
                            data-testid="product-name"
                        >
                            {p["name"]}
                        </span>
                        <span className="truncate text-sm text-muted-foreground">
                            {facts(p)}
                        </span>
                        <span className="text-sm text-muted-foreground md:hidden">
                            {f"{p['category_name']} · {price(p)}"}
                        </span>
                    </span>
                    <span className="hidden text-sm md:block">
                        {p["category_name"]}
                    </span>
                    <span
                        className="hidden text-sm md:block"
                        data-testid="product-price"
                    >
                        {price(p)}
                    </span>
                    <StatusBadge status={p["status"]}/>
                </AppLink>
            </li>;
    }

    return
        <div className="flex flex-col gap-6" data-testid="snack-products">
            <SnackSubnav slug={slug} current=""/>
            <div className="flex flex-wrap items-end justify-between gap-3">
                <div className="flex flex-col gap-1">
                    <h2 className="text-xl font-semibold">Product catalog</h2>
                    <p className="text-sm text-muted-foreground">
                        Your snacks, their sizes and prices.
                    </p>
                </div>
                {can_manage
                    and <AppLink
                        to={snack_path(slug, "new")}
                        testid="add-product"
                        className="inline-flex min-h-11 items-center rounded-md bg-primary px-5 text-sm font-medium text-primary-foreground"
                    >
                        Add product
                    </AppLink>}
            </div>
            <dl className="grid grid-cols-3 gap-3">
                {[
                    <div
                        key={label}
                        className="flex flex-col rounded-lg border bg-card p-3"
                    >
                        <dt className="text-sm text-muted-foreground">{label}</dt>
                        <dd className="text-2xl font-semibold tabular-nums">{value}</dd>
                    </div>
                    for (label, value) in [
                        ("Products", len(every)),
                        ("Active", active),
                        ("Drafts", drafts)
                    ]
                ]}
            </dl>
            <div className="flex flex-col gap-3">
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="product-search">Search</Label>
                    <Input
                        id="product-search"
                        type="search"
                        value={search}
                        placeholder="Name, brand, SKU or barcode"
                        onChange={on_input(set_search)}
                        className="min-h-11"
                    />
                </div>
                <div className="flex flex-wrap gap-3">
                    <label className="flex items-center gap-2 text-sm">
                        <span className="text-muted-foreground">Category</span>
                        <select
                            data-testid="filter-category"
                            value={category}
                            onChange={on_input(set_category)}
                            className={SELECT_CLASSES}
                        >
                            <option value="">All</option>
                            {[
                                <option key={c["category_id"]} value={c["category_id"]}>
                                    {c["name"]}
                                </option> for c in kinds
                            ]}
                        </select>
                    </label>
                    <label className="flex items-center gap-2 text-sm">
                        <span className="text-muted-foreground">Status</span>
                        <select
                            data-testid="filter-status"
                            value={status}
                            onChange={on_input(set_status)}
                            className={SELECT_CLASSES}
                        >
                            <option value="">All</option>
                            <option value="active">Active</option>
                            <option value="draft">Draft</option>
                            <option value="archived">Archived</option>
                        </select>
                    </label>
                </div>
            </div>
            <p
                role="status"
                aria-live="polite"
                className="text-sm text-muted-foreground"
            >
                {f"{len(listed)} of {len(every)} products"
                    if len(listed) != len(every)
                    else ""}
            </p>
            {len(every) == 0
                and <div className="flex flex-col gap-3 rounded-lg border bg-card p-6">
                    <h3 className="text-base font-semibold">No products yet</h3>
                    <p className="text-sm text-muted-foreground">
                        {"Add your popcorn, drinks and snacks: each product can come in several sizes, each with its own price and SKU."
                            if can_manage
                            else "Your managers haven't added any products yet."}
                    </p>
                </div>}
            {len(every) > 0
                and len(listed) == 0
                and <p className="text-sm">
                    No products match. Try another search or filter.
                </p>}
            <p
                role="status"
                aria-live="polite"
                data-testid="bulk-note"
                className="text-sm empty:hidden"
            >
                {bulk_note}
            </p>
            {can_manage
                and len(ticked) > 0
                and <div
                    role="group"
                    aria-label="Selected products"
                    data-testid="bulk-actions"
                    className="flex flex-wrap items-center gap-2 rounded-lg border bg-muted/40 p-3"
                >
                    <span className="text-sm font-medium">
                        {f"{len(ticked)} selected"}
                    </span>
                    <Button
                        className="min-h-11 px-4"
                        disabled={bulk_busy}
                        onClick={lambda { bulk("publish", "Published"); }}
                    >
                        Publish
                    </Button>
                    <Button
                        variant="outline"
                        className="min-h-11 px-4"
                        disabled={bulk_busy}
                        onClick={lambda { bulk("archive", "Archived"); }}
                    >
                        Archive
                    </Button>
                    <Button
                        variant="outline"
                        className="min-h-11 px-4"
                        disabled={bulk_busy}
                        onClick={lambda { bulk("restore", "Restored"); }}
                    >
                        Restore
                    </Button>
                    <Button
                        variant="ghost"
                        className="min-h-11 px-4"
                        onClick={lambda { set_selected([]); }}
                    >
                        Clear
                    </Button>
                </div>}
            {len(listed) > 0
                and <ul className="flex flex-col gap-2" data-testid="product-list">
                    {[Row(p) for p in listed]}
                </ul>}
        </div>;
}
