"""Per-venue 3D-glasses setup (P12.13)."""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037]
import from core.snacks.glasses_api {
    list_3d_glasses,  # jac:ignore[W2037]
    configure_3d_glasses  # jac:ignore[W2037]
}
import from .snack_view { SnackSubnav, price_text, price_cents_of, snack_path }
import from ..shell.AppLink { AppLink }

def config_for(configs: list[dict[str, any]], venue_id: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    for row in configs {
        if row["venue_id"] == venue_id {
            return row;
        }
    }
    return None;
}

def VenueGlasses(
    slug: str,
    venue: dict[str, any],  # jac:ignore[W1037]
    current: any,  # jac:ignore[W1037]
    can_manage: bool,
    on_saved: any  # jac:ignore[W1037]
) -> JsxElement {
    [sold, set_sold] = useState(current["sold"] if current is not None else False);
    [price, set_price] = useState(
        price_text(current["price_cents"]) if current is not None else ""
    );
    [busy, set_busy] = useState(False);
    [error, set_error] = useState("");

    async def save {
        cents = price_cents_of(price);
        if cents is None or cents < 1 {
            set_error("Enter the price in shillings, for example 150.");
            return;
        }
        set_busy(True);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await configure_3d_glasses(slug, venue["venue_id"], sold, cents);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("saving 3D glasses failed", e);
        }
        set_busy(False);
        if answer is None or not answer["ok"] {
            set_error(
                answer["error"]["message"]
                    if answer is not None
                    else "We couldn't save. Check your connection and try again."
            );
            return;
        }
        set_error("");
        on_saved(answer["glasses"]);
    }

    return
        <li className="flex flex-col gap-4 rounded-lg border bg-card p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                    <h3 className="font-semibold">{venue["name"]}</h3>
                    <p className="text-sm text-muted-foreground">
                        {f"{current['available']} in stock"
                            if current is not None
                            else "Set a price, then receive stock before selling."}
                    </p>
                </div>
                <label className="flex min-h-11 items-center gap-2 text-sm font-medium">
                    <input
                        type="checkbox"
                        checked={sold}
                        disabled={not can_manage or busy}
                        onChange={lambda (e: any) { set_sold(e.target.checked); }}  # jac:ignore[W1037]
                        className="size-5 accent-primary"
                    />
                    Sell at this venue
                </label>
            </div>
            <div className="flex flex-wrap items-end gap-3">
                <div className="flex min-w-48 flex-1 flex-col gap-1.5">
                    <Label htmlFor={f"glasses-price-{venue['venue_id']}"}>
                        Price (KES)
                    </Label>
                    <input
                        id={f"glasses-price-{venue['venue_id']}"}
                        inputMode="decimal"
                        value={price}
                        disabled={not can_manage or busy}
                        onChange={lambda (e: any) { set_price(e.target.value); }}  # jac:ignore[W1037]
                        className="min-h-11 rounded-md border border-input bg-background px-3"
                    />
                </div>
                {can_manage
                    and <Button
                        onClick={save}
                        disabled={busy}
                        className="min-h-11 px-5"
                    >
                        {"Saving…" if busy else "Save"}
                    </Button>}
                {current is not None
                    and <Button asChild={True} variant="outline" className="min-h-11">
                        <AppLink to={snack_path(slug, "stock")}>Manage stock</AppLink>
                    </Button>}
            </div>
            {error and <p role="alert" className="text-sm text-destructive">{error}</p>}
        </li>;
}

def:pub SnackGlassesPage(slug: str, permissions: list[str]) -> JsxElement {
    can_manage = "concessions.manage" in permissions;
    [venues, set_venues] = useState(None);
    [configs, set_configs] = useState([]);
    [failed, set_failed] = useState("");
    settings: list[dict[str, any]] = configs;  # jac:ignore[W1037]
    shown_venues: list[dict[str, any]] = venues or [];  # jac:ignore[W1037]

    async def load {
        try {
            places = await list_venues(slug);  # jac:ignore[W2037]
            setup = await list_3d_glasses(slug);  # jac:ignore[W2037]
            if not places["ok"] or not setup["ok"] {
                set_failed("We couldn't load the 3D glasses setup.");
                return;
            }
            set_venues(places["venues"]);
            set_configs(setup["venues"]);
        } except Exception as e {
            console.warn("loading 3D glasses failed", e);
            set_failed("We couldn't load the 3D glasses setup.");
        }
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    def saved(row: dict[str, any]) {  # jac:ignore[W1037]
        set_configs(
            [
                c
                for c in settings
                if c["venue_id"] != row["venue_id"]
            ]
                + [row]
        );
    }

    return
        <div className="flex flex-col gap-6" data-testid="glasses-page">
            <SnackSubnav slug={slug} current="glasses"/>
            <div>
                <h2 className="text-xl font-semibold">3D glasses</h2>
                <p className="mt-1 text-sm text-muted-foreground">
                    Choose where you sell glasses and set each venue's price. Stock and sales use the normal snacks inventory and reports.
                </p>
            </div>
            {failed
                and <Alert variant="destructive">
                    <AlertDescription>{failed}</AlertDescription>
                </Alert>}
            {venues is None
                and not failed
                and <p
                    role="status"
                    className="flex items-center gap-2 text-muted-foreground"
                >
                    <Spinner aria-hidden="true"/>{" "}
                    Loading venues…
                </p>}
            {venues is not None
                and <ul className="grid gap-3">
                    {[
                        <VenueGlasses
                            key={v["venue_id"]}
                            slug={slug}
                            venue={v}
                            current={config_for(settings, str(v["venue_id"]))}
                            can_manage={can_manage}
                            on_saved={saved}
                        /> for v in shown_venues
                    ]}
                </ul>}
        </div>;
}
