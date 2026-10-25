"""Box office › Snacks only (P12.10; improvements #21, #26): a walk-in buying snacks
without a ticket.

The agent picks the venue (when they sell at more than one), then the snacks on the
storefront's own snack step (SnackStep), priced by the server as they go
(counter_price_snacks). **Take payment** places the sale (place_snack_order: the stock
set aside), then:
- Cash: "Cash received", then "Confirm" (two steps, so a slip doesn't sell).
- M-Pesa: the customer's number gets the PIN prompt; the page follows the payment
  (counter_snack_payment) until it's paid or refused.
Paid, the page shows the pickup code and **Hand over** (the Snack counter's
hand_over_snacks), then New sale. A sale left too long ends, and its stock goes back.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.booking.snack_sale {
    counter_snack_venues,  # jac:ignore[W2037] authenticated endpoints
    counter_snack_menu,  # jac:ignore[W2037]
    counter_price_snacks,  # jac:ignore[W2037]
    place_snack_order,  # jac:ignore[W2037]
    sell_snacks_for_cash,  # jac:ignore[W2037]
    sell_snacks_with_mpesa,  # jac:ignore[W2037]
    counter_snack_payment  # jac:ignore[W2037]
}
import from core.snacks.pickup_api { hand_over_snacks }  # jac:ignore[W2037]
import from ..storefront.SnackStep { SnackStep, cart_lines }
import from ..storefront.checkout_rules { money, phone_problem, random_id }

glob POLL_MS: int = 3000,
     OFFLINE: str = "The server didn't answer. Nothing changed; try again.";

async def _call(fn: any, args: list[any]) -> any {  # jac:ignore[W1037]
    try {
        return await fn(*args);
    } except Exception as e {
        console.warn("box office call failed", e);
        return None;
    }
}

def:pub SnackOnlySale(slug: str, shift_open: bool = True) -> JsxElement {
    [venues, set_venues] = useState(None);
    [venue, set_venue] = useState("");
    [menu, set_menu] = useState([]);
    [cart, set_cart] = useState([]);
    [priced, set_priced] = useState(None);
    [holder, set_holder] = useState(random_id("counter"));
    [order, set_order] = useState(None);
    [stage, set_stage] = useState("picking");
    [confirming, set_confirming] = useState(False);
    [phone, set_phone] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [handed, set_handed] = useState(False);
    lines: list[dict[str, any]] = cart;  # jac:ignore[W1037]
    shown: dict[str, any] | None = order;  # jac:ignore[W1037]

    async def load_venues {
        got: any = await _call(counter_snack_venues, [slug]);  # jac:ignore[W1037,W2037]
        if got is None or not got["ok"] {
            set_venues([]);
            set_problem(got["error"]["message"] if got is not None else OFFLINE);
            return;
        }
        set_venues(got["venues"]);
        if len(got["venues"]) > 0 {
            set_venue(got["venues"][0]["venue_id"]);
        }
    }
    def start_venues {
        load_venues();
    }
    useEffect(start_venues, [slug, shift_open]);

    async def load_menu {
        if not venue {
            return;
        }
        got: any = await _call(counter_snack_menu, [slug, venue]);  # jac:ignore[W1037,W2037]
        set_menu(got["categories"] if got is not None and got["ok"] else []);
    }
    def start_menu {
        load_menu();
    }
    useEffect(start_menu, [venue]);

    async def reprice(next_cart: list[dict[str, any]]) {  # jac:ignore[W1037]
        set_cart(next_cart);
        if len(next_cart) == 0 {
            set_priced(None);
            return;
        }
        asked = [slug, venue, cart_lines(next_cart)];
        got: any = await _call(counter_price_snacks, asked);  # jac:ignore[W1037,W2037]
        set_priced(got);
    }

    def new_sale {
        set_holder(random_id("counter"));
        set_cart([]);
        set_priced(None);
        set_order(None);
        set_stage("picking");
        set_confirming(False);
        set_phone("");
        set_problem("");
        set_handed(False);
    }

    def picked_venue(e: any) {  # jac:ignore[W1037]
        set_venue(e.target.value);
        new_sale();
    }

    def typed_phone(e: any) {  # jac:ignore[W1037]
        set_phone(e.target.value);
    }

    async def take_payment {
        set_busy(True);
        set_problem("");
        placed: any = await _call(  # jac:ignore[W1037]
            place_snack_order,  # jac:ignore[W2037]
            [slug, venue, holder, random_id("snacks"), cart_lines(lines)]
        );
        set_busy(False);
        if placed is None or not placed["ok"] {
            set_problem(placed["error"]["message"] if placed is not None else OFFLINE);
            return;
        }
        set_order(placed["order"]);
        set_stage("paying");
    }

    def paid(found: dict[str, any]) {  # jac:ignore[W1037]
        set_order(found);
        set_stage("done");
    }

    def refused(answer: dict[str, any]) {  # jac:ignore[W1037]
        if answer["error"]["code"] in ["order_expired", "no_order"] {
            set_stage("picking");
        }
        set_problem(answer["error"]["message"]);
    }

    async def take_cash {
        set_busy(True);
        sold: any = await _call(sell_snacks_for_cash, [slug, venue, holder]);  # jac:ignore[W1037,W2037]
        set_busy(False);
        set_confirming(False);
        if sold is None {
            set_problem(OFFLINE);
        } elif sold["ok"] {
            paid(sold["order"]);
        } else {
            refused(sold);
        }
    }

    async def send_prompt(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        wrong = phone_problem(phone);
        if len(wrong) > 0 {
            set_problem(wrong);
            return;
        }
        set_busy(True);
        started: any = await _call(  # jac:ignore[W1037]
            sell_snacks_with_mpesa,  # jac:ignore[W2037]
            [slug, venue, holder, phone, "", random_id("pay")]
        );
        set_busy(False);
        if started is None {
            set_problem(OFFLINE);
        } elif started["ok"] {
            set_problem("");
            set_stage("waiting");
        } else {
            refused(started);
        }
    }

    async def check {
        got: any = await _call(counter_snack_payment, [slug, venue, holder]);  # jac:ignore[W1037,W2037]
        if got is None or not got["ok"] or got["payment"] is None {
            return;
        }
        state: str = got["payment"]["state"];
        if state == "success" and got["order"]["status"] == "confirmed" {
            paid(got["order"]);
        } elif state in ["failed", "cancelled"] {
            set_stage("paying");
            set_problem(got["payment"]["message"]);
        }
    }

    def poll -> any {  # jac:ignore[W1037]
        if stage != "waiting" {
            return lambda {};
        }
        timer = setInterval(lambda { check(); }, POLL_MS);  # jac:ignore[W2001]
        return lambda { clearInterval(timer); };  # jac:ignore[W2001]
    }
    useEffect(poll, [stage]);

    async def hand_over {
        set_busy(True);
        done: any = await _call(hand_over_snacks, [slug, shown["pickup_reference"]]);  # jac:ignore[W1037,W2037]
        set_busy(False);
        if done is None or not done["ok"] {
            set_problem(done["error"]["message"] if done is not None else OFFLINE);
            return;
        }
        set_handed(True);
    }

    if venues is None {
        return <Spinner aria-label="Loading"/>;
    }
    places: list[dict[str, str]] = venues;
    if len(places) == 0 {
        return
            <p
                role="alert"
                className="text-destructive"
                data-testid="snack-sale-problem"
            >
                {problem or "You can't sell at any venue."}
            </p>;
    }
    cost: dict[str, any] | None = priced;  # jac:ignore[W1037]
    # Test absence explicitly: an empty dict from Jac's `and` is truthy in JS.
    total: int = cost["total_cents"] if cost is not None and cost["ok"] else 0;
    return
        <div data-testid="snack-sale" className="flex flex-col gap-4">
            {len(places) > 1
                and stage == "picking"
                and <div className="flex flex-col gap-1.5">
                    <Label htmlFor="snack-sale-venue">Venue</Label>
                    <select
                        id="snack-sale-venue"
                        value={venue}
                        onChange={picked_venue}
                        className="min-h-11 w-fit rounded-md border bg-background px-3"
                    >
                        {[
                            <option key={v["venue_id"]} value={v["venue_id"]}>
                                {v["name"]}
                            </option> for v in places
                        ]}
                    </select>
                </div>}{stage == "picking"
                and <>
                    <SnackStep
                        slug={slug}
                        menu={menu}
                        cart={lines}
                        on_cart={reprice}
                        priced={priced}
                        busy={busy}
                    />
                    <div
                        className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card p-4"
                    >
                        <p
                            className="text-2xl font-semibold"
                            data-testid="snack-sale-total"
                        >
                            {money(total, "KES")}
                        </p>
                        <Button
                            className="min-h-11 px-5"
                            disabled={busy or len(lines) == 0 or total == 0}
                            data-testid="snack-sale-pay"
                            onClick={lambda { take_payment(); }}
                        >
                            {busy and <Spinner aria-hidden="true"/>}Take payment
                        </Button>
                    </div>
                </>}{(stage == "paying" or stage == "waiting")
                and shown is not None
                and <section
                    data-testid="snack-sale-payment"
                    aria-labelledby="snack-sale-heading"
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <div
                        className="flex flex-wrap items-baseline justify-between gap-2"
                    >
                        <h3 id="snack-sale-heading" className="text-lg font-semibold">
                            Take payment
                        </h3>
                        <p
                            className="text-2xl font-semibold"
                            data-testid="snack-sale-amount"
                        >
                            {money(shown["total_cents"], shown["currency"])}
                        </p>
                    </div>
                    <ul className="text-sm text-muted-foreground">
                        {[
                            <li key={f"{i}"}>{f"{s['quantity']} × {s['name']}"}</li>
                            for (i, s) in enumerate(shown["snacks"])
                        ]}
                    </ul>
                    {(
                        <p
                            role="status"
                            className="flex items-center gap-2"
                            data-testid="snack-sale-waiting"
                        >
                            <Spinner aria-hidden="true"/>
                            Waiting for the customer to enter their M-Pesa PIN…
                        </p>
                    )
                        if stage == "waiting"
                        else <div className="grid gap-4 sm:grid-cols-2">
                            <div className="flex flex-col gap-2 rounded-md border p-3">
                                <p className="font-medium">Cash</p>
                                {(
                                    <div className="flex flex-wrap gap-2">
                                        <Button
                                            data-testid="snack-sale-confirm-cash"
                                            className="min-h-11 px-4"
                                            disabled={busy}
                                            onClick={lambda { take_cash(); }}
                                        >
                                            Confirm
                                        </Button>
                                        <Button
                                            variant="outline"
                                            className="min-h-11 px-4"
                                            onClick={lambda { set_confirming(False); }}
                                        >
                                            Back
                                        </Button>
                                    </div>
                                )
                                    if confirming
                                    else <Button
                                        variant="outline"
                                        className="min-h-11 w-fit px-4"
                                        data-testid="snack-sale-cash"
                                        onClick={lambda { set_confirming(True); }}
                                    >
                                        Cash received
                                    </Button>}
                            </div>
                            <form
                                className="flex flex-col gap-2 rounded-md border p-3"
                                onSubmit={send_prompt}
                            >
                                <Label htmlFor="snack-sale-phone">M-Pesa number</Label>
                                <Input
                                    id="snack-sale-phone"
                                    type="tel"
                                    inputMode="tel"
                                    autoComplete="off"
                                    placeholder="0712 345 678"
                                    value={phone}
                                    onChange={typed_phone}
                                    className="h-11 max-w-xs text-base"
                                />
                                <Button
                                    type="submit"
                                    className="min-h-11 w-fit px-4"
                                    disabled={busy}
                                >
                                    Send M-Pesa prompt
                                </Button>
                            </form>
                        </div>}
                </section>}{stage == "done"
                and shown is not None
                and <section
                    data-testid="snack-sale-done"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                >
                    <h3 className="text-lg font-semibold">Paid</h3>
                    <p>
                        Pickup code
                        <strong
                            className="ml-2 font-mono text-xl"
                            data-testid="snack-sale-code"
                        >
                            {shown["pickup_reference"]}
                        </strong>
                    </p>
                    <div className="flex flex-wrap gap-2">
                        {(
                            <p
                                role="status"
                                className="font-medium"
                                data-testid="snack-sale-handed"
                            >
                                Handed over.
                            </p>
                        )
                            if handed
                            else <Button
                                className="min-h-11 px-5"
                                disabled={busy}
                                data-testid="snack-sale-hand-over"
                                onClick={lambda { hand_over(); }}
                            >
                                Hand over the snacks
                            </Button>}
                        <Button
                            variant="outline"
                            className="min-h-11 px-5"
                            data-testid="snack-sale-new"
                            onClick={new_sale}
                        >
                            New sale
                        </Button>
                    </div>
                </section>}{problem
                and <p
                    role="alert"
                    className="text-sm text-destructive"
                    data-testid="snack-sale-problem"
                >
                    {problem}
                </p>}
        </div>;
}
