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

import from react { useState, useEffect, useRef }
import from core.booking.more_snacks_api { more_snacks, counter_more_snacks }
import from ..storefront.PayPanel { PickupCard }
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
import from core.snacks.pickup_api { hand_over_snacks, snack_pickup }  # jac:ignore[W2037]
import from ..storefront.SnackStep { SnackStep, cart_lines }
import from ..storefront.checkout_rules {
    money,
    phone_problem,
    email_problem,
    random_id
}

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

def:pub SnackOnlySale(
    slug: str,
    shift_open: bool = True,
    booking_token: str = "",
    booking_reference: str = "",
    on_paid: any = None  # jac:ignore[W1037]
) -> JsxElement {  # jac:ignore[W1037]
    extra: bool = len(booking_token) > 0 or len(booking_reference) > 0;
    online: bool = len(booking_token) > 0;
    [email, set_email] = useState("");
    [request_key, set_request_key] = useState(random_id("extra"));
    [payment_key, set_payment_key] = useState(random_id("payment"));
    [booking_name, set_booking_name] = useState("");
    price_version = useRef(0);
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
    [pickup_ready, set_pickup_ready] = useState(None);
    booking_label: str = booking_name;
    ready_view: dict[str, any] | None = pickup_ready;  # jac:ignore[W1037]
    lines: list[dict[str, any]] = cart;  # jac:ignore[W1037]
    shown: dict[str, any] | None = order;  # jac:ignore[W1037]

    async def extra_call(action: str, asked: list[any] = []) -> any {  # jac:ignore[W1037,W3036]
        return await _call(
            more_snacks if online else counter_more_snacks,
            [
                slug,
                booking_token if online else booking_reference,
                action,
                holder,
                payment_key if action == "pay" else request_key,
                asked,
                phone,
                email
            ]
        );
    }

    async def load_venues {
        if extra {
            got_extra: any = await extra_call("menu");  # jac:ignore[W1037]
            if got_extra is None or not got_extra["ok"] {
                set_venues([]);
                set_problem(
                    got_extra["error"]["message"] if got_extra is not None else OFFLINE
                );
                return;
            }
            if not got_extra["can_add"] {
                set_venues([]);
                set_problem(
                    "Extra snacks can only be bought before the showtime starts."
                );
                return;
            }
            set_booking_name(
                got_extra["booking"]["movie_title"]
                    + " · "
                    + got_extra["booking"]["reference"]
            );
            set_menu(got_extra["categories"]);
            set_venues(
                [{"venue_id": "booking", "name": got_extra["booking"]["venue"]}]
            );
            return;
        }
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
        if extra or not venue {
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
        set_priced(None);
        price_version.current += 1;
        version = price_version.current;
        if len(next_cart) == 0 {
            set_priced(None);
            return;
        }
        asked = [slug, venue, cart_lines(next_cart)];
        got: any = await extra_call("price", cart_lines(next_cart))  # jac:ignore[W1037]
            if extra
            else await _call(counter_price_snacks, asked);  # jac:ignore[W1037,W2037]
        if version == price_version.current {
            set_priced(got);
        }
    }

    def new_sale {
        set_holder(random_id("counter"));
        set_request_key(random_id("extra"));
        set_payment_key(random_id("payment"));
        set_cart([]);
        set_priced(None);
        set_order(None);
        set_stage("picking");
        set_confirming(False);
        set_phone("");
        set_problem("");
        set_handed(False);
        set_pickup_ready(None);
        if extra {
            load_venues();
        }
    }

    def picked_venue(e: any) {  # jac:ignore[W1037]
        set_venue(e.target.value);
        new_sale();
    }

    def typed_phone(e: any) {  # jac:ignore[W1037]
        set_phone(e.target.value);
    }

    def typed_email(e: any) {  # jac:ignore[W1037]
        set_email(e.target.value);
    }

    async def take_payment {
        set_busy(True);
        set_problem("");
        placed: any = await extra_call("place", cart_lines(lines))  # jac:ignore[W1037]
            if extra
            else await _call(  # jac:ignore[W1037]
                place_snack_order,  # jac:ignore[W2037]
                [slug, venue, holder, request_key, cart_lines(lines)]
            );
        set_busy(False);
        if placed is None or not placed["ok"] {
            set_problem(placed["error"]["message"] if placed is not None else OFFLINE);
            return;
        }
        set_order(placed["order"]);
        set_stage("paying");
    }

    async def paid(found: dict[str, any]) {  # jac:ignore[W1037]
        set_order(found);
        set_stage("done");
        if on_paid is not None {
            on_paid();
        }
        if extra and not online {
            ready: any = await _call(snack_pickup, [slug, found["pickup_reference"]]);  # jac:ignore[W1037]
            if ready is not None and ready["ok"] {
                set_pickup_ready(ready["pickup"]);
            } else {
                set_problem(
                    "Look up this pickup code at the Snack counter to hand over the snacks."
                );
            }
        }
    }

    def refused(answer: dict[str, any]) {  # jac:ignore[W1037]
        if answer["error"]["code"] in ["order_expired", "no_order"] {
            new_sale();
        }
        set_problem(answer["error"]["message"]);
    }

    async def take_cash {
        set_busy(True);
        sold: any = await extra_call("cash")  # jac:ignore[W1037]
            if extra
            else await _call(sell_snacks_for_cash, [slug, venue, holder]);  # jac:ignore[W1037,W2037]
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
        wrong = phone_problem(phone) or (email_problem(email) if online else "");
        if len(wrong) > 0 {
            set_problem(wrong);
            return;
        }
        set_busy(True);
        started: any = await extra_call("pay")  # jac:ignore[W1037]
            if extra
            else await _call(  # jac:ignore[W1037]
                sell_snacks_with_mpesa,  # jac:ignore[W2037]
                [slug, venue, holder, phone, "", payment_key]
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
        got: any = await extra_call("status")  # jac:ignore[W1037]
            if extra
            else await _call(counter_snack_payment, [slug, venue, holder]);  # jac:ignore[W1037,W2037]
        if got is None or not got["ok"] or got["payment"] is None {
            return;
        }
        state: str = got["payment"]["state"];
        if state == "success" and got["order"]["status"] == "confirmed" {
            paid(got["order"]);
        } elif state in ["failed", "cancelled"] {
            set_payment_key(random_id("payment"));
            set_stage("paying");
            set_problem(got["payment"]["message"]);
        } elif state == "needs_attention" {
            set_stage("attention");
            set_problem(
                "This payment needs staff attention. Please contact the cinema before paying again."
            );
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
        ready: any = pickup_ready;  # jac:ignore[W1037]
        set_busy(True);
        done: any = await _call(  # jac:ignore[W1037]
            hand_over_snacks,
            [
                slug,
                shown["pickup_reference"],
                ready["collection_token"] if extra and ready is not None else ""
            ]
        );  # jac:ignore[W1037,W2037]
        set_busy(False);
        if done is None or not done["ok"] {
            set_problem(done["error"]["message"] if done is not None else OFFLINE);
            if extra
                and done is not None
                and done["error"]["code"] == "pickup_changed" {
                refreshed: any = await _call(  # jac:ignore[W1037]
                    snack_pickup, [slug, shown["pickup_reference"]]
                );  # jac:ignore[W1037]
                if refreshed is not None and refreshed["ok"] {
                    set_pickup_ready(refreshed["pickup"]);
                }
            }
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
            {extra
                and <p className="text-sm text-muted-foreground">
                    {booking_label
                        + " · Pay only for the extra snacks. Keep your existing pickup code."}
                </p>}{len(places) > 1
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
                            {busy and <Spinner aria-hidden="true"/>}{"Continue to payment"
                                if online
                                else "Take payment"}
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
                            {not online
                                and <div
                                    className="flex flex-col gap-2 rounded-md border p-3"
                                >
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
                                                onClick={lambda { set_confirming(
                                                    False
                                                ); }}
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
                                </div>}
                            <form
                                className="flex flex-col gap-2 rounded-md border p-3"
                                onSubmit={send_prompt}
                            >
                                {online
                                    and <>
                                        <Label htmlFor="extra-snack-email">
                                            Email for your updated booking
                                        </Label>
                                        <Input
                                            id="extra-snack-email"
                                            type="email"
                                            autoComplete="email"
                                            value={email}
                                            onChange={typed_email}
                                            className="h-11 text-base"
                                        />
                                    </>}
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
                    <h3 className="text-lg font-semibold">
                        {"Extra snacks added" if extra else "Paid"}
                    </h3>
                    {extra
                        and <PickupCard
                            snacks={shown["snacks"]}
                            pickup={{
                                "reference": shown["pickup_reference"],
                                "qr": shown["pickup_qr"]
                            }}
                        />}
                    <p>
                        Pickup code
                        <strong
                            className="ml-2 font-mono text-xl"
                            data-testid="snack-sale-code"
                        >
                            {shown["pickup_reference"]}
                        </strong>
                    </p>
                    {extra
                        and not online
                        and pickup_ready is not None
                        and <div className="text-sm" data-testid="extra-ready">
                            <p className="font-medium">Items ready to hand over</p>
                            <ul>
                                {[
                                    <li key={f"{i}"}>
                                        {f"{s['quantity']} × {s['name']}"}
                                    </li> for (i, s) in enumerate(ready_view["snacks"])
                                ]}
                            </ul>
                        </div>}
                    <div className="flex flex-wrap gap-2">
                        {not online
                            and (
                                (
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
                                        disabled={busy
                                            or (extra and pickup_ready is None)}
                                        data-testid="snack-sale-hand-over"
                                        onClick={lambda { hand_over(); }}
                                    >
                                        Hand over the snacks
                                    </Button>
                            )}
                        <Button
                            variant="outline"
                            className="min-h-11 px-5"
                            data-testid="snack-sale-new"
                            onClick={new_sale}
                        >
                            {"Add more snacks" if extra else "New sale"}
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
