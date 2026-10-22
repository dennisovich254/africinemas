"""The "Add snacks" step of checkout (P12.8; design guide §5): between the tickets and
paying, when the showtime's venue sells snacks.

The menu (public_snacks, read by Checkout) shows every category as a heading over a row
of snack posters (picture, name, price, "Few left"), swiping sideways like the
storefront's movie posters, so the snacks sell themselves. A poster opens the snack's
choices in place, not in a floating sheet that a cinema's design could push off screen:
its size, extras (within the group's limits) and, for a combo, what goes in it, with a
quantity; the price on its Add button is for guidance only. "← All snacks" goes back. The cart below lists what was added with the server's
prices (price_snacks, also called by Checkout) and a Remove for each. Checkout draws the
bar with the total, Skip and Continue.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from core.snacks.menu_api { public_snack_image }
import from .checkout_rules { money }

glob CURRENCY: str = "KES";

def:pub cart_lines(cart: list[dict[str, any]]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The cart as price_snacks and place_order take it (without the page's own keys).
    return [
        {
            "variant_id": c["variant_id"],
            "quantity": c["quantity"],
            "addons": c["addons"],
            "choices": c["choices"]
        } for c in cart
    ];
}

def:pub has_snacks(menu: any) -> bool {  # jac:ignore[W1037]
    if menu is None {
        return False;
    }
    found: list[dict[str, any]] = menu;  # jac:ignore[W1037]
    return len(found) > 0;
}

def SnackImage(slug: str, product: dict[str, any], size: str) -> JsxElement {  # jac:ignore[W1037]
    # A product's main image filling `size` (a frame's classes), or its name on a tinted
    # card, so a snack without a photo still reads as a poster.
    [src, set_src] = useState("");

    async def load {
        image_id: str = product["image_id"];
        if not image_id {
            return;
        }
        try {
            got: any = await public_snack_image(slug, product["product_id"], image_id);  # jac:ignore[W1037]
            if got["ok"] {
                set_src(f"data:{got['content_type']};base64,{got['data_base64']}");
            }
        } except Exception as e {
            console.warn("public_snack_image failed", e);
        }
    }

    def start {
        load();
    }
    useEffect(start, [product["product_id"]]);

    if src {
        return
            <img
                src={src}
                alt=""
                loading="lazy"
                className={f"{size} shrink-0 rounded-md object-cover"}
            />;
    }
    return
        <span
            aria-hidden="true"
            className={f"{size} flex shrink-0 items-center justify-center rounded-md bg-gradient-to-br from-primary/30 via-muted to-muted p-2 text-center font-display text-lg leading-tight text-foreground"}
        >
            {product["name"]}
        </span>;
}

def:pub SnackStep(
    slug: str,
    menu: list[dict[str, any]],  # jac:ignore[W1037]
    cart: list[dict[str, any]],  # jac:ignore[W1037]
    on_cart: any,  # jac:ignore[W1037] (new cart) -> None
    priced: any,  # jac:ignore[W1037] price_snacks' answer, or None while it's on its way
    busy: bool
) -> JsxElement {
    [open, set_open] = useState(None);
    [variant, set_variant] = useState("");
    [addons, set_addons] = useState([]);
    [choices, set_choices] = useState([]);
    [quantity, set_quantity] = useState(1);
    [next_key, set_next_key] = useState(1);
    lines: list[dict[str, any]] = cart;  # jac:ignore[W1037]
    picked: list[str] = addons;
    chosen: list[list[str]] = choices;

    def start_product(p: dict[str, any]) {  # jac:ignore[W1037]
        set_open(p);
        set_variant(p["variants"][0]["variant_id"]);
        set_addons([]);
        set_choices(
            [
                [
                    c["choices"][0]["variant_id"] if c["kind"] == "fixed" else ""
                    for _ in range(c["quantity"])
                ] for c in p["components"]
            ]
        );
        set_quantity(1);
        # The choices replace the posters: bring the step's top into view.
        win: any = window;  # jac:ignore[W1037,W2001]
        heading: any = win.document.getElementById("snacks-heading");  # jac:ignore[W1037,W6001] client-only
        if heading {
            heading.scrollIntoView({"block": "start", "behavior": "smooth"});
        }
    }

    def toggle_addon(group: dict[str, any], option_id: str) {  # jac:ignore[W1037]
        if option_id in picked {
            set_addons(
                [
                    a
                    for a in picked
                    if a != option_id
                ]
            );
            return;
        }
        mine = [
            o["option_id"]
            for o in group["options"]
            if o["option_id"] in picked
        ];
        if group["max_picks"] == 1 {
            # One at most: picking another replaces it, like a radio button.
            set_addons(
                [
                    a
                    for a in picked
                    if a not in mine
                ]
                    + [option_id]
            );
        } elif len(mine) < group["max_picks"] {
            set_addons(picked + [option_id]);
        }
    }

    def choose(at: int, unit: int, variant_id: str) {
        set_choices(
            [
                [
                    variant_id if n == at and u == unit else v
                    for (u, v) in enumerate(row)
                ] for (n, row) in enumerate(chosen)
            ]
        );
    }

    def add_to_cart {
        p: dict[str, any] = open;  # jac:ignore[W1037]
        on_cart(
            lines
                + [
                    {
                        "key": next_key,
                        "product": p["name"],
                        "variant_id": variant,
                        "quantity": quantity,
                        "addons": picked,
                        "choices": chosen if len(p["components"]) > 0 else []
                    }
                ]
        );
        set_next_key(next_key + 1);
        set_open(None);
    }

    def remove(key: int) {
        on_cart(
            [
                c
                for c in lines
                if c["key"] != key
            ]
        );
    }

    def Sheet_body(p: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        variants: list[dict[str, any]] = p["variants"];  # jac:ignore[W1037]
        current: dict[str, any] = (  # jac:ignore[W1037]
            [
                v
                for v in variants
                if v["variant_id"] == variant
            ]
            + [variants[0]]
        )[0];
        # (Plain loops: sum and nested generators aren't in the browser's runtime.)
        extras_cents = 0;
        groups_ok = True;
        for g in p["addon_groups"] {
            count = 0;
            for o in g["options"] {
                if o["option_id"] in picked {
                    extras_cents += o["price_cents"];
                    count += 1;
                }
            }
            if count < g["min_picks"] {
                groups_ok = False;
            }
        }
        filled = True;
        for row in chosen {
            for v in row {
                if v == "" {
                    filled = False;
                }
            }
        }
        unit = current["price_cents"] + extras_cents;
        return
            <div className="flex flex-col gap-5" data-testid="snack-options">
                {len(variants) > 1
                    and <fieldset className="flex flex-col gap-2">
                        <legend className="mb-1 text-sm font-semibold">
                            {(p["option_names"] + ["Size"])[0]}
                        </legend>
                        <div className="flex flex-wrap gap-2">
                            {[
                                <Button
                                    key={v["variant_id"]}
                                    type="button"
                                    variant={"default"
                                        if v["variant_id"] == variant
                                        else "outline"}
                                    aria-pressed={"true"
                                        if v["variant_id"] == variant
                                        else "false"}
                                    data-testid="snack-variant"
                                    className="min-h-11 px-4"
                                    onClick={lambda { set_variant(v["variant_id"]); }}
                                >
                                    {f"{v['label']} · {money(
                                        v['price_cents'], CURRENCY
                                    )}"}
                                </Button> for v in variants
                            ]}
                        </div>
                        {current["left"] is not None
                            and <p className="text-sm text-muted-foreground">
                                {f"Only {current['left']} left"}
                            </p>}
                    </fieldset>}
                {[
                    <fieldset key={g["group_id"]} className="flex flex-col gap-1">
                        <legend className="mb-1 text-sm font-semibold">
                            {g["label"]}
                            <span className="ml-2 font-normal text-muted-foreground">
                                {(
                                    f"Choose {g['min_picks']}"
                                        if g["min_picks"] == g["max_picks"]
                                        else (
                                            f"Up to {g['max_picks']}"
                                                if g["min_picks"] == 0
                                                else f"Choose {g['min_picks']} to {g[
                                                    'max_picks'
                                                ]}"
                                        )
                                )}
                            </span>
                        </legend>
                        {[
                            <label
                                key={o["option_id"]}
                                className="flex min-h-11 items-center justify-between gap-3 text-sm"
                            >
                                <span className="flex items-center gap-3">
                                    <input
                                        type="checkbox"
                                        data-testid="snack-addon"
                                        checked={o["option_id"] in picked}
                                        onChange={lambda { toggle_addon(
                                            g, o["option_id"]
                                        ); }}
                                        className="size-5"
                                    />
                                    {o["name"]}
                                </span>
                                <span className="tabular-nums text-muted-foreground">
                                    {f"+{money(o['price_cents'], CURRENCY)}"
                                        if o["price_cents"] > 0
                                        else "Free"}
                                </span>
                            </label> for o in g["options"]
                        ]}
                    </fieldset> for g in p["addon_groups"]
                ]}
                {[
                    <fieldset key={f"part-{n}"} className="flex flex-col gap-2">
                        <legend className="mb-1 text-sm font-semibold">
                            {f"{c['label']}"
                                + (f" ({c['quantity']})" if c["quantity"] > 1 else "")}
                        </legend>
                        {c["kind"] == "fixed"
                            and <p className="text-sm">{c["choices"][0]["name"]}</p>}
                        {c["kind"] != "fixed"
                            and <div className="flex flex-col gap-2">
                                {[
                                    <select
                                        key={f"unit-{u}"}
                                        aria-label={f"{c['label']} {u + 1}"}
                                        data-testid="snack-choice"
                                        value={chosen[n][u]}
                                        onChange={lambda (e: any) { choose(  # jac:ignore[W1037]
                                            n, u, e.target.value
                                        ); }}
                                        className="min-h-11 rounded-md border border-input bg-background px-3 text-sm"
                                    >
                                        <option value="">Choose…</option>
                                        {[
                                            <option
                                                key={x["variant_id"]}
                                                value={x["variant_id"]}
                                            >
                                                {x["name"]}
                                            </option> for x in c["choices"]
                                        ]}
                                    </select> for u in range(c["quantity"])
                                ]}
                            </div>}
                    </fieldset> for (n, c) in enumerate(p["components"])
                ]}
                <div className="flex items-center gap-3">
                    <span className="text-sm font-semibold">How many</span>
                    <Button
                        type="button"
                        variant="outline"
                        className="size-11"
                        aria-label="One fewer"
                        disabled={quantity <= 1}
                        onClick={lambda { set_quantity(quantity - 1); }}
                    >
                        −
                    </Button>
                    <span
                        className="min-w-6 text-center tabular-nums"
                        data-testid="snack-quantity"
                    >
                        {quantity}
                    </span>
                    <Button
                        type="button"
                        variant="outline"
                        className="size-11"
                        aria-label="One more"
                        disabled={quantity >= 20}
                        onClick={lambda { set_quantity(quantity + 1); }}
                    >
                        +
                    </Button>
                </div>
                <Button
                    type="button"
                    data-testid="snack-add"
                    disabled={not groups_ok or not filled}
                    onClick={add_to_cart}
                    className="min-h-11 w-full"
                >
                    {f"Add to order · {money(unit * quantity, CURRENCY)}"}
                </Button>
            </div>;
    }

    priced_lines: list[dict[str, any]] = priced["lines"]  # jac:ignore[W1037]
        if priced is not None
        else [];
    shown_product: dict[str, any] | None = open;  # jac:ignore[W1037]
    return
        <section
            aria-labelledby="snacks-heading"
            data-testid="snack-step"
            className="flex flex-col gap-4 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-col gap-1">
                <h3 id="snacks-heading" className="text-lg font-semibold">
                    Add snacks
                </h3>
                <p className="text-sm text-muted-foreground">
                    Collect them at the snack counter. Or skip this.
                </p>
            </div>
            {shown_product is not None
                and <div className="flex flex-col gap-4" data-testid="snack-chooser">
                    <Button
                        type="button"
                        variant="ghost"
                        data-testid="snack-back"
                        className="min-h-11 w-fit px-3"
                        onClick={lambda { set_open(None); }}
                    >
                        ← All snacks
                    </Button>
                    <div className="flex items-start gap-4">
                        <SnackImage
                            slug={slug}
                            product={shown_product}
                            size="aspect-[4/5] w-28 sm:w-36"
                        />
                        <div className="flex min-w-0 flex-col gap-1">
                            <h4 className="font-display text-2xl leading-tight">
                                {shown_product["name"]}
                            </h4>
                            {shown_product["description"]
                                and <p className="text-sm text-muted-foreground">
                                    {shown_product["description"]}
                                </p>}
                        </div>
                    </div>
                    {Sheet_body(shown_product)}
                </div>}
            {shown_product is None
                and <div className="flex flex-col gap-6">
                    {[
                        <div key={c["category_id"]} className="flex flex-col gap-3">
                            <h4
                                className="text-base font-semibold"
                                data-testid="snack-category"
                            >
                                {c["name"]}
                            </h4>
                            <ul
                                className="-mx-1 flex snap-x gap-4 overflow-x-auto px-1 pb-2"
                            >
                                {[
                                    <li
                                        key={p["product_id"]}
                                        className="w-36 shrink-0 snap-start sm:w-40"
                                    >
                                        <button
                                            type="button"
                                            data-testid="snack-product"
                                            onClick={lambda { start_product(p); }}
                                            className="group flex w-full flex-col gap-2 rounded-md text-left focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                                        >
                                            <span className="relative block">
                                                <SnackImage
                                                    slug={slug}
                                                    product={p}
                                                    size="aspect-[4/5] w-full transition group-hover:opacity-90"
                                                />
                                                {any(
                                                    v["left"] is not None
                                                    for v in p["variants"]
                                                )
                                                    and <span
                                                        className="absolute top-2 left-2 rounded-full bg-background/90 px-2 py-0.5 text-xs font-semibold"
                                                    >
                                                        Few left
                                                    </span>}
                                            </span>
                                            <span className="font-medium leading-tight">
                                                {p["name"]}
                                            </span>
                                            <span
                                                className="text-sm text-muted-foreground tabular-nums"
                                            >
                                                {(
                                                    "From "
                                                        if len(p["variants"]) > 1
                                                        else ""
                                                )
                                                    + money(p["from_cents"], CURRENCY)}
                                            </span>
                                        </button>
                                    </li> for p in c["products"]
                                ]}
                            </ul>
                        </div> for c in menu
                    ]}
                </div>}
            {len(lines) > 0
                and <div className="flex flex-col gap-2 border-t pt-3">
                    <h4 className="text-sm font-semibold">Your snacks</h4>
                    <ul className="flex flex-col divide-y" data-testid="snack-cart">
                        {[
                            <li
                                key={c["key"]}
                                className="flex items-center justify-between gap-3 py-2"
                            >
                                <span className="flex min-w-0 flex-col">
                                    <span>
                                        {f"{c['quantity']} × {priced_lines[n]['name']}"
                                            if n < len(priced_lines)
                                            else f"{c['quantity']} × {c['product']}"}
                                    </span>
                                    {n < len(priced_lines)
                                        and len(priced_lines[n]["addons"]) > 0
                                        and <span
                                            className="text-xs text-muted-foreground"
                                        >
                                            {", ".join(
                                                [
                                                    a["name"]
                                                    for a in priced_lines[n]["addons"]
                                                ]
                                            )}
                                        </span>}
                                </span>
                                <span className="flex items-center gap-2">
                                    <span className="tabular-nums">
                                        {money(priced_lines[n]["line_cents"], CURRENCY)
                                            if n < len(priced_lines)
                                            else "…"}
                                    </span>
                                    <Button
                                        type="button"
                                        variant="ghost"
                                        className="min-h-11 px-3"
                                        aria-label={f"Remove {c['product']}"}
                                        disabled={busy}
                                        onClick={lambda { remove(c["key"]); }}
                                    >
                                        Remove
                                    </Button>
                                </span>
                            </li> for (n, c) in enumerate(lines)
                        ]}
                    </ul>
                </div>}
        </section>;
}
