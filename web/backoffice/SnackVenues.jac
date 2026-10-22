"""The product editor's "At each venue" section (P12.2; design guide §3F).

One grid (improvements #9): a row per variant and a column per venue, so every venue
shows at once.
- Each venue's heading has "Sold here": managers choose which venues sell the product
  (a new venue sells it until switched off). A venue that doesn't sell it greys out.
- Each cell has "On sale" (the box office can change it at their venues) and the
  variant's price there: empty uses the variant's own price, shown as the placeholder;
  managers set it.

Nothing saves until "Save venue changes", which sends only what changed and then
announces it; the product comes back from the server and replaces the editor's copy
(on_change).
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037] authenticated endpoint
import from core.snacks.venue_api {
    set_snack_product_venues,  # jac:ignore[W2037] authenticated endpoint
    set_snack_variant_availability,  # jac:ignore[W2037]
    set_snack_venue_price  # jac:ignore[W2037]
}
import from .form_parts { FieldError, on_input }
import from .snack_view { price_text, price_cents_of, with_field }

glob CELL_INPUT: str = "min-h-11 w-28 min-w-0 rounded-md border border-input bg-background px-2 text-sm disabled:opacity-60";

def:pub SnackVenues(
    slug: str,
    product: dict[str, any],  # jac:ignore[W1037]
    permissions: list[str],
    on_change: any  # jac:ignore[W1037] (product) -> None
) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    can_flip = "concessions.availability" in permissions;
    [venues, set_venues] = useState([]);
    # What's typed or ticked and not saved yet: venues sold at, and by
    # "variant_id|venue_id" each cell's On sale and price.
    [sold_at, set_sold_at] = useState(None);
    [on_sale, set_on_sale] = useState({});
    [prices, set_prices] = useState({});
    [errors, set_errors] = useState({});
    [message, set_message] = useState("");
    [busy, set_busy] = useState(False);
    product_id: str = product["product_id"];
    off: list[str] = product["off_at"];
    variants: list[dict[str, any]] = product["variants"];  # jac:ignore[W1037]

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_venues(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_venues failed", e);
            return;
        }
        if answer["ok"] {
            set_venues(
                [{"id": v["venue_id"], "name": v["name"]} for v in answer["venues"]]
            );
        }
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, product_id]);

    places: list[dict[str, str]] = venues;
    saved_sold: list[str] = [
        v["id"]
        for v in places
        if v["id"] not in off
    ];
    chosen: list[str] = sold_at if sold_at is not None else saved_sold;
    ticks: dict[str, bool] = on_sale;
    drafts: dict[str, str] = prices;
    field_errors: dict[str, str] = errors;

    def saved_on(v: dict[str, any], venue_id: str) -> bool {  # jac:ignore[W1037]
        return venue_id not in v["off_at"];
    }

    def saved_price(v: dict[str, any], venue_id: str) -> str {  # jac:ignore[W1037]
        return price_text(v["venue_prices"].get(venue_id));
    }

    def shown_on(v: dict[str, any], venue_id: str) -> bool {  # jac:ignore[W1037]
        key = f"{v['variant_id']}|{venue_id}";
        return ticks[key] if key in ticks else saved_on(v, venue_id);
    }

    def shown_price(v: dict[str, any], venue_id: str) -> str {  # jac:ignore[W1037]
        key = f"{v['variant_id']}|{venue_id}";
        return drafts[key] if key in drafts else saved_price(v, venue_id);
    }

    # What differs from the saved product, in the order it's sent.
    # (Compared as text: in the browser two lists are never equal.)
    sold_changed = ",".join(sorted(chosen)) != ",".join(sorted(saved_sold));
    flips: list[tuple[dict[str, any], str, bool]] = [];  # jac:ignore[W1037]
    repriced: list[tuple[dict[str, any], str, str]] = [];  # jac:ignore[W1037]
    for v in variants {
        for p in places {
            if p["id"] in chosen {
                if shown_on(v, p["id"]) != saved_on(v, p["id"]) {
                    flips.append((v, p["id"], shown_on(v, p["id"])));
                }
                if shown_price(v, p["id"]).strip() != saved_price(v, p["id"]) {
                    repriced.append((v, p["id"], shown_price(v, p["id"])));
                }
            }
        }
    }
    dirty = sold_changed or len(flips) > 0 or len(repriced) > 0;

    def toggle_sold(venue_id: str) {
        set_sold_at(
            [
                x
                for x in chosen
                if x != venue_id
            ]
                if venue_id in chosen
                else chosen + [venue_id]
        );
        set_message("");
    }

    def tick(v: dict[str, any], venue_id: str) {  # jac:ignore[W1037]
        set_on_sale(
            with_field(
                ticks, f"{v['variant_id']}|{venue_id}", not shown_on(v, venue_id)
            )
        );
        set_message("");
    }

    def type_price(v: dict[str, any], venue_id: str, text: str) {  # jac:ignore[W1037]
        set_prices(with_field(drafts, f"{v['variant_id']}|{venue_id}", text));
        set_message("");
    }

    async def send(work: any) -> any {  # jac:ignore[W1037]
        # One change: the product it answers with, or None after saying what went wrong.
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await work();
        } except Exception as e {
            console.warn("venue change failed", e);
        }
        if answer is None {
            set_message("We couldn't save that. Check your connection and try again.");
            return None;
        }
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return None;
        }
        return answer["product"];
    }

    async def save {
        # Prices are checked first, so nothing is half-saved over a typing slip.
        shown: dict[str, str] = {};
        cents_of: dict[str, any] = {};  # jac:ignore[W1037]
        for (v, venue_id, text) in repriced {
            key = f"{v['variant_id']}|{venue_id}";
            cents = price_cents_of(text);
            if cents == -1 {
                shown[key] = "Enter whole shillings, like 350, or leave it empty.";
            }
            cents_of[key] = cents;
        }
        set_errors(shown);
        if len(Object.keys(shown)) > 0 {  # jac:ignore[W2001]
            set_message("Some prices need fixing: see the marked fields.");
            return;
        }
        set_busy(True);
        set_message("");
        latest: any = None;  # jac:ignore[W1037]
        failed = False;
        if sold_changed and can_manage {
            def send_sold -> any {  # jac:ignore[W1037]
                return set_snack_product_venues(slug, product_id, chosen);  # jac:ignore[W2037]
            }
            latest = await send(send_sold);
            failed = latest is None;
        }
        for (v, venue_id, available) in flips {
            if not failed {
                variant_id: str = v["variant_id"];
                def send_flip -> any {  # jac:ignore[W1037]
                    return set_snack_variant_availability(  # jac:ignore[W2037]
                        slug, product_id, variant_id, venue_id, available
                    );
                }
                latest = await send(send_flip);
                failed = latest is None;
            }
        }
        for (v, venue_id, _) in repriced {
            if not failed and can_manage {
                variant_id: str = v["variant_id"];
                cents: any = cents_of[f"{variant_id}|{venue_id}"];  # jac:ignore[W1037]
                def send_price -> any {  # jac:ignore[W1037]
                    return set_snack_venue_price(  # jac:ignore[W2037]
                        slug, product_id, variant_id, venue_id, cents
                    );
                }
                latest = await send(send_price);
                failed = latest is None;
            }
        }
        set_busy(False);
        if latest is not None {
            on_change(latest);
        }
        if not failed {
            set_sold_at(None);
            set_on_sale({});
            set_prices({});
            set_message("Saved your venue changes.");
        }
    }

    if len(places) == 0 {
        return <span className="sr-only">No venues</span>;
    }

    def Cell(v: dict[str, any], p: dict[str, str]) -> JsxElement {  # jac:ignore[W1037]
        venue_id: str = p["id"];
        sold = venue_id in chosen;
        key = f"{v['variant_id']}|{venue_id}";
        field_id = f"venue-price-{v['variant_id']}-{venue_id}";
        return
            <td key={venue_id} className="px-3 py-2 align-top">
                {not sold
                    and <span
                        className="inline-flex min-h-11 items-center text-sm text-muted-foreground"
                    >
                        Not sold here
                    </span>}{sold
                    and <div className="flex flex-col gap-1">
                        <label className="flex min-h-11 items-center gap-2 text-sm">
                            <input
                                type="checkbox"
                                data-testid="on-sale"
                                aria-label={f"{v['label']} on sale at {p['name']}"}
                                checked={shown_on(v, venue_id)}
                                disabled={busy or not can_flip}
                                onChange={lambda { tick(v, venue_id); }}
                                className="size-5"
                            />
                            On sale
                        </label>
                        <input
                            id={field_id}
                            data-testid="venue-price"
                            aria-label={f"Price in KES for {v['label']} at {p['name']}"}
                            value={shown_price(v, venue_id)}
                            placeholder={price_text(v["price_cents"]) or "No price"}
                            inputMode="decimal"
                            disabled={busy or not can_manage}
                            onChange={on_input(
                                lambda (text: str) { type_price(v, venue_id, text); }
                            )}
                            className={CELL_INPUT}
                        />
                        {field_errors[key]
                            and <FieldError
                                field_id={field_id}
                                error={field_errors[key]}
                            />}
                    </div>}
            </td>;
    }

    return
        <section
            aria-labelledby="venues-title"
            data-testid="snack-venues"
            className="flex flex-col gap-4 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-col gap-1">
                <h3 id="venues-title" className="text-lg font-semibold">
                    At each venue
                </h3>
                <p className="text-sm text-muted-foreground">
                    Choose where it's sold, and switch a size off where it has run out. A price left empty is the usual price, shown faintly; type one to charge more or less at that venue.
                </p>
            </div>
            <div className="overflow-x-auto rounded-lg border">
                <table className="w-full min-w-max text-sm">
                    <thead className="bg-muted/50">
                        <tr>
                            <th scope="col" className="px-3 py-2 text-left font-medium">
                                Variant
                            </th>
                            {[
                                <th
                                    key={p["id"]}
                                    scope="col"
                                    className="px-3 py-2 text-left align-top font-medium"
                                >
                                    <span className="block">{p["name"]}</span>
                                    {can_manage
                                        and <label
                                            className="flex min-h-11 items-center gap-2 font-normal text-muted-foreground"
                                        >
                                            <input
                                                type="checkbox"
                                                data-testid="sold-at"
                                                aria-label={f"Sold at {p['name']}"}
                                                checked={p["id"] in chosen}
                                                disabled={busy}
                                                onChange={lambda { toggle_sold(
                                                    p["id"]
                                                ); }}
                                                className="size-5"
                                            />
                                            Sold here
                                        </label>}
                                </th> for p in places
                            ]}
                        </tr>
                    </thead>
                    <tbody>
                        {[
                            <tr
                                key={v["variant_id"]}
                                data-testid="venue-variant-row"
                                className="border-t"
                            >
                                <th
                                    scope="row"
                                    className="px-3 py-2 text-left align-top font-medium"
                                >
                                    <span className="inline-flex min-h-11 items-center">
                                        {v["label"]}
                                    </span>
                                </th>
                                {[Cell(v, p) for p in places]}
                            </tr> for v in variants
                        ]}
                    </tbody>
                </table>
            </div>
            {(can_manage or can_flip)
                and <div className="flex flex-wrap items-center gap-3">
                    <Button
                        type="button"
                        className="min-h-11 px-5"
                        disabled={busy or not dirty}
                        data-testid="save-venues"
                        onClick={save}
                    >
                        {busy and <Spinner aria-hidden="true"/>}Save venue changes
                    </Button>
                    {dirty
                        and not busy
                        and <span className="text-sm text-muted-foreground">
                            Unsaved changes
                        </span>}
                </div>}
            <p
                role="status"
                aria-live="polite"
                data-testid="venues-message"
                className="text-sm empty:hidden"
            >
                {message}
            </p>
        </section>;
}
