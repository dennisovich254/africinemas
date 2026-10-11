"""The product editor's "At each venue" section (P12.2; design guide §3F).

- Sold at: a checkbox per venue; managers save which venues sell the product (a new
  venue sells it until switched off).
- Per venue (chosen when the caller works at more than one): each variant's "Available
  here" switch (a button whose pressed state matches its label), which the box office
  can flip at their venues, and its price there: empty uses the variant's price;
  managers set it.

Changes save one at a time and are announced; the product comes back from the server
and replaces the editor's copy (on_change).
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from core.snacks.venue_api {
    set_snack_product_venues,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    set_snack_variant_availability,  # jac:ignore[W2037]
    set_snack_venue_price  # jac:ignore[W2037]
}
import from .form_parts { FieldError, on_input }
import from .snack_view { price_text, price_cents_of, with_field }

glob CELL_INPUT: str = "min-h-11 w-full min-w-0 rounded-md border border-input bg-background px-2 text-sm md:w-28",
     # A variant is a row on a wide screen and a card on a phone.
     ROW: str = "grid gap-2 md:grid-cols-[minmax(7rem,1fr)_auto_minmax(12rem,1fr)] md:items-start md:gap-3";

def:pub SnackVenues(
    slug: str,
    product: dict[str, any],  # jac:ignore[W1037]
    permissions: list[str],
    on_change: any  # jac:ignore[W1037] (product) -> None
) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    can_flip = "concessions.availability" in permissions;
    [venues, set_venues] = useState([]);
    [venue, set_venue] = useState("");
    [sold_at, set_sold_at] = useState([]);
    [prices, set_prices] = useState({});
    [errors, set_errors] = useState({});
    [message, set_message] = useState("");
    [busy, set_busy] = useState(False);
    product_id: str = product["product_id"];
    off: list[str] = product["off_at"];

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_venues(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_venues failed", e);
            return;
        }
        if answer["ok"] {
            found = [
                {"id": v["venue_id"], "name": v["name"]} for v in answer["venues"]
            ];
            set_venues(found);
            set_sold_at(
                [
                    v["id"]
                    for v in found
                    if v["id"] not in off
                ]
            );
            if found {
                set_venue(found[0]["id"]);
            }
        }
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, product_id]);

    async def run(work: any, done: str, field_id: str = "") {  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await work();
        } except Exception as e {
            console.warn("venue change failed", e);
        }
        set_busy(False);
        if answer is None {
            set_message("We couldn't save that. Check your connection and try again.");
            return;
        }
        if not answer["ok"] {
            shown: dict[str, str] = {};
            if field_id {
                shown[field_id] = answer["error"]["message"];
            } else {
                set_message(answer["error"]["message"]);
            }
            set_errors(shown);
            return;
        }
        set_errors({});
        on_change(answer["product"]);
        set_message(done);
    }

    places: list[dict[str, str]] = venues;
    chosen: list[str] = sold_at;
    here: str = venue;
    here_name: str = (
        [
            v["name"]
            for v in places
            if v["id"] == here
        ]
        + [""]
    )[0];
    drafts: dict[str, str] = prices;
    field_errors: dict[str, str] = errors;
    variants: list[dict[str, any]] = product["variants"];  # jac:ignore[W1037]

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
    }

    def send_sold -> any {  # jac:ignore[W1037]
        return set_snack_product_venues(slug, product_id, chosen);  # jac:ignore[W2037]
    }

    async def flip(v: dict[str, any], available: bool) {  # jac:ignore[W1037]
        variant_id: str = v["variant_id"];
        def send -> any {  # jac:ignore[W1037]
            return set_snack_variant_availability(  # jac:ignore[W2037]
                slug, product_id, variant_id, here, available
            );
        }
        await run(
            send,
            f"{v['label']} is {'available' if available else 'unavailable'} at {here_name}."
        );
    }

    async def save_price(v: dict[str, any]) {  # jac:ignore[W1037]
        variant_id: str = v["variant_id"];
        key = f"{variant_id}|{here}";
        typed: str = drafts[key]
            if key in drafts
            else price_text(v["venue_prices"].get(here));
        cents = price_cents_of(typed);
        field_id = f"venue-price-{variant_id}";
        if cents == -1 {
            shown: dict[str, str] = {};
            shown[field_id] = "Enter whole shillings, like 350, or leave it empty.";
            set_errors(shown);
            return;
        }
        def send -> any {  # jac:ignore[W1037]
            return set_snack_venue_price(slug, product_id, variant_id, here, cents);  # jac:ignore[W2037]
        }
        await run(
            send,
            f"{v['label']} costs KES {price_text(cents)} at {here_name}."
                if cents is not None
                else f"{v['label']} uses its own price at {here_name}.",
            field_id
        );
    }

    if len(places) == 0 {
        return <span className="sr-only">No venues</span>;
    }

    def VariantRow(v: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        variant_id: str = v["variant_id"];
        on = here not in v["off_at"];
        key = f"{variant_id}|{here}";
        typed: str = drafts[key]
            if key in drafts
            else price_text(v["venue_prices"].get(here));
        field_id = f"venue-price-{variant_id}";
        return
            <li
                key={variant_id}
                data-testid="venue-variant-row"
                className={ROW
                    + " rounded-md border p-3 md:rounded-none md:border-0 md:border-t md:px-0 md:py-2"}
            >
                <span className="text-sm font-semibold md:font-medium">
                    {v["label"]}
                </span>
                <div>
                    <Button
                        type="button"
                        variant={"outline" if on else "default"}
                        aria-pressed={"false" if on else "true"}
                        data-testid="venue-unavailable-switch"
                        className="min-h-11 px-3"
                        disabled={busy or not can_flip}
                        onClick={lambda { flip(v, not on); }}
                    >
                        {f"Unavailable at {here_name}"}
                    </Button>
                </div>
                <div className="flex flex-col gap-1">
                    <label
                        htmlFor={field_id}
                        className="text-xs font-medium text-muted-foreground md:sr-only"
                    >
                        {f"Price at {here_name} (KES)"}
                    </label>
                    <div className="flex items-center gap-2">
                        <input
                            id={field_id}
                            aria-label={f"Price in KES for {v['label']} at {here_name}"}
                            value={typed}
                            placeholder={price_text(v["price_cents"]) or "No price"}
                            inputMode="decimal"
                            disabled={not can_manage}
                            onChange={on_input(
                                lambda (text: str) { set_prices(
                                    with_field(drafts, key, text)
                                ); }
                            )}
                            className={CELL_INPUT}
                        />
                        {can_manage
                            and <Button
                                type="button"
                                variant="outline"
                                className="min-h-11 px-3"
                                aria-label={f"Save the price of {v['label']} at {here_name}"}
                                disabled={busy}
                                onClick={lambda { save_price(v); }}
                            >
                                Save
                            </Button>}
                    </div>
                    {field_errors[field_id]
                        and <FieldError
                            field_id={field_id}
                            error={field_errors[field_id]}
                        />}
                </div>
            </li>;
    }

    return
        <section
            aria-labelledby="venues-title"
            data-testid="snack-venues"
            className="flex flex-col gap-4 rounded-lg border bg-card p-4"
        >
            <h3 id="venues-title" className="text-lg font-semibold">At each venue</h3>
            <p
                role="status"
                aria-live="polite"
                data-testid="venues-message"
                className="text-sm empty:hidden"
            >
                {message}
            </p>
            {can_manage
                and <fieldset className="flex flex-col gap-1">
                    <legend className="mb-1 text-sm font-medium">Sold at</legend>
                    {[
                        <label
                            key={v["id"]}
                            className="flex min-h-11 items-center gap-3 text-sm"
                        >
                            <input
                                type="checkbox"
                                data-testid="sold-at"
                                checked={v["id"] in chosen}
                                onChange={lambda { toggle_sold(v["id"]); }}
                                className="size-5"
                            />
                            {v["name"]}
                        </label> for v in places
                    ]}
                    <Button
                        type="button"
                        variant="outline"
                        className="min-h-11 w-fit px-4"
                        disabled={busy}
                        onClick={lambda { run(send_sold, "Saved where it's sold."); }}
                    >
                        Save venues
                    </Button>
                </fieldset>}
            {len(places) > 1
                and <label className="flex min-h-11 w-fit items-center gap-2 text-sm">
                    <span className="text-muted-foreground">Venue</span>
                    <select
                        data-testid="venue-choice"
                        value={here}
                        onChange={on_input(set_venue)}
                        className="min-h-11 rounded-md border border-input bg-background px-2 text-sm"
                    >
                        {[
                            <option key={v["id"]} value={v["id"]}>{v["name"]}</option>
                            for v in places
                        ]}
                    </select>
                </label>}
            {here in off
                and <p className="text-sm text-muted-foreground">
                    {f"This product isn't sold at {here_name}. Tick it under Sold at to sell it there."}
                </p>}
            <div className="flex flex-col">
                <div
                    aria-hidden="true"
                    className={"hidden text-sm text-muted-foreground md:grid " + ROW}
                >
                    <span className="py-2 font-medium">Variant</span>
                    <span className="py-2 font-medium">Availability</span>
                    <span className="py-2 font-medium">
                        {f"Price at {here_name} (KES)"}
                    </span>
                </div>
                <ul className="flex flex-col gap-3 md:gap-0">
                    {[VariantRow(v) for v in variants]}
                </ul>
            </div>
            <p className="text-sm text-muted-foreground">
                An empty price uses the variant's own price.
            </p>
        </section>;
}
