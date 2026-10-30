"""Checkout on a showtime's page (P4.6): choose seats, hold them, choose tickets, order.

1. Choose: the seat map (SeatMap); a bar fixed to the bottom of the screen shows the
   chosen seats and holds them (hold_seats). A seat someone has just taken is dropped
   from the choice, and the visitor is told which.
2. Tickets: the seats are held for a few minutes, counting down. Before the time runs
   out the visitor is told and can keep the seats longer (extend_hold, up to the
   cinema's limit; WCAG 2.2.1); if it does run out, the seats go back and so does the
   visitor, with a message. Each seat gets a ticket type; the server prices them
   (quote_hold) and the bar shows the total. "Change seats" gives the hold back.
3. Snacks (P12.8): when the venue sells snacks (public_snacks), the tickets' button
   leads to the "Add snacks" step (SnackStep): the menu, a sheet per product, and the
   cart priced by the server (price_snacks), with Skip as plain as Continue. Without
   snacks it goes straight to paying.
4. Pay: places the order (place_order) with an idempotency key made for this order and
   reused if the request is sent again, with the snack cart, then pays it with M-Pesa.
   "← Change seats or snacks" goes back (change_order): the unpaid order is cancelled,
   the seats held again and the cart kept, unless an M-Pesa request is out. Then it pays
   (PayPanel, P5.6): a PIN
   prompt on the phone, the status live, and the tickets once paid (Tickets).

In the chat (P8.5) the booking card passes `suggested` seats: they start chosen, not
held. A reload comes back to the same step: the browser keeps the visitor's holder id for
the visit, and my_order / my_hold say where they were. Changes worth hearing (held,
time nearly up, seats released, order placed) are announced politely.
"""

import from react { useState, useEffect, useRef }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Clock01Icon }
import from ...components.ui.button { Button }
import from core.catalog.storefront_api { public_seat_availability }
import from core.booking.hold_api { hold_seats, my_hold, release_hold, extend_hold }
import from core.booking.counter_api {
    counter_seat_availability,  # jac:ignore[W2037] authenticated endpoint
    counter_hold_seats  # jac:ignore[W2037] authenticated endpoint
}
import from core.booking.change_order { change_order }
import from core.booking.order_api {
    place_order,
    my_order,
    quote_hold,
    public_ticket_types
}
import from core.snacks.menu_api { public_snacks, price_snacks }
import from .SeatMap { SeatMap }
import from .SnackStep { SnackStep, cart_lines, has_snacks }
import from .PayPanel { PayPanel, Tickets }
import from core.payments.settlement { my_payment }
import from core.payments.resolver { end_my_order }
import from .showtimes { listed, time_label }
import from .checkout_rules { money, countdown, seconds_until, visitor_id, order_key }

glob MAX_SEATS: int = 10,
     WARN_SECONDS: int = 120;

def _code(answer: any) -> str {  # jac:ignore[W1037]
    if answer is None {
        return "network";
    }
    return "" if answer["ok"] else answer["error"]["code"];
}

def _message(answer: any) -> str {  # jac:ignore[W1037]
    if answer is None {
        return "We couldn't reach the cinema. Check your connection and try again.";
    }
    return answer["error"]["message"];
}

def _items(seats: list[str], code: str) -> list[dict[str, str]] {
    found: list[dict[str, str]] = [];
    for label in seats {
        found.append({"seat_label": label, "ticket_type": code});
    }
    return found;
}

def _with_ticket(
    items: list[dict[str, str]], label: str, code: str
) -> list[dict[str, str]] {
    found: list[dict[str, str]] = [];
    for item in items {
        found.append(
            {
                "seat_label": item["seat_label"],
                "ticket_type": code
                    if item["seat_label"] == label
                    else item["ticket_type"]
            }
        );
    }
    return found;
}

def _with_glasses(chosen: list[str], label: str, checked: bool) -> list[str] {
    without = [
        x
        for x in chosen
        if x != label
    ];
    return sorted(without + [label]) if checked else without;
}

def _line_for(quote: any, label: str) -> any {  # jac:ignore[W1037]
    if quote is None {
        return None;
    }
    for line in quote["lines"] {
        if line["seat_label"] == label {
            return line;
        }
    }
    return None;
}

def BottomBar(children: any) -> JsxElement {  # jac:ignore[W1037]
    return
        <div
            data-testid="checkout-bar"
            className="sticky bottom-0 z-20 -mx-4 border-t bg-background/95 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur sm:bottom-4 sm:mx-0 sm:rounded-lg sm:border sm:pb-3"
        >
            <div className="flex items-center justify-between gap-3">{children}</div>
        </div>;
}

def Ordered(order: dict[str, any], tz: str, at_counter: bool = False) -> JsxElement {  # jac:ignore[W1037]
    # at_counter: the box office (P6.5) holds the seats for the walk-in customer, so the
    # note speaks to the agent, not to "you".
    until = time_label(order["pay_by"], tz);
    return
        <section
            data-testid="order-placed"
            aria-labelledby="order-heading"
            className="flex flex-col gap-4 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-col gap-1">
                <h3 id="order-heading" className="text-lg font-semibold">
                    Your order is waiting for payment
                </h3>
                <p className="text-sm text-muted-foreground">
                    Reference
                    <span
                        data-testid="order-reference"
                        className="ml-1 font-mono font-medium text-foreground"
                    >
                        {order["reference"]}
                    </span>
                </p>
            </div>
            <ul className="flex flex-col divide-y">
                {[
                    <li
                        key={line["seat_label"]}
                        className="flex items-center justify-between gap-3 py-2"
                    >
                        <span>
                            {f"Seat {line['seat_label']} · {line['ticket_name']}"}
                        </span>
                        <span className="tabular-nums">
                            {money(line["total_cents"], order["currency"])}
                        </span>
                    </li> for line in order["lines"]
                ]}{[
                    <li
                        key={f"snack-{n}"}
                        data-testid="order-snack"
                        className="flex items-center justify-between gap-3 py-2"
                    >
                        <span>{f"{line['quantity']} × {line['name']}"}</span>
                        <span className="tabular-nums">
                            {money(line["line_cents"], order["currency"])}
                        </span>
                    </li> for (n, line) in enumerate(order["snacks"] or [])
                ]}
            </ul>
            <p className="flex items-center justify-between text-lg font-semibold">
                <span>Total</span>
                <span data-testid="order-total" className="tabular-nums">
                    {money(order["total_cents"], order["currency"])}
                </span>
            </p>
            <p className="text-sm text-muted-foreground">
                {f"The seats are held until {until}. Take payment before then to issue the tickets."
                    if at_counter
                    else f"Your seats are kept for you until {until}. Pay before then to get your tickets."}
            </p>
        </section>;
}

def:pub Checkout(
    slug: str,
    screening_id: str,
    tz: str,
    counter_holder: str = "",
    pay_panel: any = None,  # jac:ignore[W1037]
    done_panel: any = None,  # jac:ignore[W1037]
    suggested: list[str] | None = None
) -> JsxElement {
    # At the box office (P6.5) the agent books under counter_holder, one per sale, and
    # pay_panel(order, on_paid, on_expired) and done_panel(payment) replace the M-Pesa
    # panel and the customer's tickets panel (which would save the tickets to the
    # signed-in agent's own account).
    holder = counter_holder or visitor_id();
    [seat_map, set_seat_map] = useState(None);
    [types, set_types] = useState([]);
    [currency, set_currency] = useState("");
    [chosen, set_chosen] = useState([]);
    [hold, set_hold] = useState(None);
    [items, set_items] = useState([]);
    [quote, set_quote] = useState(None);
    [order, set_order] = useState(None);
    [paid, set_paid] = useState(None);
    [pay_state, set_pay_state] = useState(None);
    [expired, set_expired] = useState(False);
    [key, set_key] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [news, set_news] = useState("");
    [now_ms, set_now_ms] = useState(Date.now());  # jac:ignore[W2001]
    [warned, set_warned] = useState(False);
    # Snacks (P12.8): the venue's menu, whether the snack step is showing, the cart and
    # its price from the server.
    [menu, set_menu] = useState(None);
    [snack_step, set_snack_step] = useState(False);
    [cart, set_cart] = useState([]);
    [snack_price, set_snack_price] = useState(None);
    # One explicit, unchecked choice per ticket when this 3D venue has glasses in stock.
    [glasses, set_glasses] = useState(None);
    [glasses_seats, set_glasses_seats] = useState([]);
    asked_count = useRef(0);
    snacks_asked = useRef(0);
    picked: list[str] = chosen;
    lines: list[dict[str, str]] = items;
    tickets: list[dict[str, str]] = types;
    selected_glasses: list[str] = glasses_seats;
    glasses_now: dict[str, any] | None = glasses;  # jac:ignore[W1037]
    glasses_cents: int = int(glasses_now["price_cents"])
        if glasses_now is not None
        else 0;
    current: dict[str, any] | None = hold;  # jac:ignore[W1037]
    priced_now: dict[str, any] | None = quote;  # jac:ignore[W1037]

    async def call(fn: any, args: list[any]) -> any {  # jac:ignore[W1037]
        try {
            return await fn(*args);
        } except Exception as e {
            console.warn("checkout call failed", e);
            return None;
        }
    }

    async def load_map {
        # At the box office, its own map: counter seats bookable (2026-10-30).
        shown = await call(counter_seat_availability, [slug, screening_id])
            if counter_holder
            else await call(public_seat_availability, [slug, screening_id]);
        if shown is not None and shown["ok"] {
            set_seat_map(shown);
        }
    }

    async def load_menu {
        found = await call(public_snacks, [slug, screening_id]);
        set_menu(found["categories"] if found is not None and found["ok"] else []);
        set_glasses(
            found.get("glasses") if found is not None and found["ok"] else None
        );
    }

    def begin_tickets(held: dict[str, any], codes: list[dict[str, str]]) {  # jac:ignore[W1037]
        load_menu();
        set_snack_step(False);
        set_hold(held);
        set_chosen(held["seats"]);
        set_items(
            _items(held["seats"], codes[0]["code"] if len(codes or []) > 0 else "")
        );
        set_key(order_key());
        set_warned(False);
    }

    async def start {
        # Ticket types and any hold or order first, the seat map last: the map shows
        # as soon as it arrives, and before the types it would look closed to sales.
        # A paid order shows its tickets; a payment under way picks up where it was.
        paying = await call(my_payment, [slug, screening_id, holder]);
        if paying is not None and paying["ok"] {
            if paying["payment"]["state"] == "success" {
                set_paid(paying["payment"]);
                return;
            }
            set_pay_state(paying["payment"]);
        }
        listed_types = await call(public_ticket_types, [slug]);
        codes: list[dict[str, str]] = [];
        if listed_types is not None and listed_types["ok"] {
            codes = listed_types["ticket_types"];
            set_types(codes);
            set_currency(listed_types["currency"]);
        }
        mine = await call(my_order, [slug, screening_id, holder]);
        if mine is not None and mine["ok"] {
            set_order(mine["order"]);
        } else {
            held = await call(my_hold, [slug, screening_id, holder]);
            if held is not None and held["ok"] {
                begin_tickets(held["hold"], codes);
            } elif suggested {
                # Seats the chat suggested (P8.5; free when suggested): chosen, not
                # held, until the visitor continues. One taken meanwhile is dropped
                # when they hold, with a message, as on any choice.
                set_chosen([x for x in suggested][:MAX_SEATS]);
            }
        }
        await load_map();
    }

    def kick_off {
        start();
    }
    useEffect(kick_off, [slug, screening_id]);

    def tick -> any {  # jac:ignore[W1037]
        # The clock runs while seats are held or an order waits for payment.
        if (hold is None and order is None) or paid is not None {
            return lambda {};
        }
        timer = setInterval(lambda { set_now_ms(Date.now()); }, 1000);  # jac:ignore[W2001]
        return lambda { clearInterval(timer); };  # jac:ignore[W2001]
    }
    useEffect(tick, [hold, order, paid]);

    placed_now: dict[str, any] | None = order;  # jac:ignore[W1037]
    pay_left: int = seconds_until(placed_now["pay_by"], now_ms)
        if placed_now is not None
        else 1;

    async def time_up {
        # The order's time to pay is up: end it now so its seats can be chosen again,
        # unless its payment went through at the last moment.
        set_expired(True);
        ended = await call(end_my_order, [slug, screening_id, holder]);
        if ended is not None and ended["ok"] and ended["state"] == "confirmed" {
            paying = await call(my_payment, [slug, screening_id, holder]);
            if paying is not None and paying["ok"] {
                set_paid(paying["payment"]);
                set_expired(False);
                set_news("Paid. Your tickets are ready.");
                return;
            }
        }
        set_news("The time to pay ran out, so your seats were released.");
    }

    def watch_pay {
        if placed_now is not None and paid is None and not expired and pay_left <= 0 {
            time_up();
        }
    }
    useEffect(watch_pay, [pay_left]);

    async def go_back {
        # From paying back to the order (owner, 2026-10-27): the unpaid order is
        # cancelled on the server and the seats are held again, so the visitor can change
        # the snacks, the tickets or the seats. Refused while an M-Pesa request is out.
        set_busy(True);
        set_problem("");
        back = await call(change_order, [slug, screening_id, holder]);
        set_busy(False);
        if back is None {
            set_problem("We couldn't reach the cinema. Try again.");
            return;
        }
        if not back["ok"] {
            set_problem(back["error"]["message"]);
            return;
        }
        set_order(None);
        set_pay_state(None);
        set_hold(back["hold"]);
        set_key(order_key());
        set_snack_step(has_snacks(menu));
        set_news("Your order is open again. Change it, then continue.");
    }

    def choose_again {
        # Back to the seat map, with nothing chosen.
        set_order(None);
        set_hold(None);
        set_pay_state(None);
        set_quote(None);
        set_chosen([]);
        set_glasses_seats([]);
        set_expired(False);
        set_problem("");
        load_map();
    }

    left: int = seconds_until(current["expires_at"], now_ms)
        if current is not None
        else 0;

    def watch_time {
        if hold is None or order is not None {
            return;
        }
        if left <= 0 {
            set_hold(None);
            set_quote(None);
            set_problem(
                "Your seats were released because the time ran out. Choose them again."
            );
            set_news("Your seats were released because the time ran out.");
            load_map();
            return;
        }
        if left <= WARN_SECONDS and not warned {
            set_warned(True);
            set_news(
                f"{countdown(left)} left to finish. You can keep your seats longer."
            );
        }
    }
    useEffect(watch_time, [left]);

    async def price(wanted: list[dict[str, str]]) {
        if not wanted or not wanted[0]["ticket_type"] {
            return;
        }
        # Only the latest request's answer counts: an earlier one can arrive after it
        # (changing a ticket type while the last price is on its way).
        asked = asked_count.current + 1;
        asked_count.current = asked;
        priced = await call(quote_hold, [slug, screening_id, holder, wanted]);
        if asked != asked_count.current {
            return;
        }
        if priced is not None and priced["ok"] {
            set_quote(priced["quote"]);
            set_problem("");
        } else {
            set_quote(None);
            set_problem(_message(priced));
        }
    }

    def reprice {
        if hold is not None and order is None {
            price(items);
        }
    }
    useEffect(reprice, [items, hold]);

    async def price_cart(wanted: list[dict[str, any]]) {  # jac:ignore[W1037]
        # The cart's price from the server; only the latest request's answer counts.
        if len(wanted) == 0 {
            set_snack_price({"lines": [], "total_cents": 0});
            return;
        }
        asked = snacks_asked.current + 1;
        snacks_asked.current = asked;
        priced = await call(price_snacks, [slug, screening_id, cart_lines(wanted)]);
        if asked != snacks_asked.current {
            return;
        }
        if priced is not None and priced["ok"] {
            set_snack_price(priced);
            set_problem("");
        } else {
            set_snack_price(None);
            set_problem(_message(priced));
        }
    }

    def reprice_snacks {
        if snack_step {
            price_cart(cart);
        }
    }
    useEffect(reprice_snacks, [cart, snack_step]);

    def toggle(label: str) {
        # From React's latest list, not this render's: two quick taps (or Enter then
        # Space) can come before a re-render, and the second would undo the first.
        def update(prev: list[str]) -> list[str] {
            if listed(label, prev) {
                return [
                    s
                    for s in prev
                    if s != label
                ];
            }
            if len(prev) >= MAX_SEATS {
                return prev;
            }
            return prev + [label];
        }
        if not listed(label, picked) and len(picked) >= MAX_SEATS {
            set_problem(f"You can choose up to {MAX_SEATS} seats at a time.");
            return;
        }
        set_problem("");
        set_chosen(update);
    }

    async def hold_chosen {
        set_busy(True);
        held = await call(counter_hold_seats, [slug, screening_id, holder, chosen])
            if counter_holder
            else await call(hold_seats, [slug, screening_id, holder, chosen]);
        set_busy(False);
        if held is not None and held["ok"] {
            set_problem("");
            begin_tickets(held["hold"], tickets);
            set_news(
                f"Seats {', '.join(
                    held['hold']['seats']
                )} are held for you. Choose your tickets."
            );
            return;
        }
        if _code(held) == "seats_taken" {
            gone: list[str] = held["error"]["seats"];
            set_chosen(
                [
                    s
                    for s in picked
                    if not listed(s, gone)
                ]
            );
            set_problem(
                f"Someone has just taken {', '.join(gone)}. Choose other seats."
            );
            load_map();
            return;
        }
        set_problem(_message(held));
    }

    async def keep_longer {
        set_busy(True);
        kept = await call(extend_hold, [slug, screening_id, holder]);
        set_busy(False);
        if kept is not None and kept["ok"] {
            set_hold(kept["hold"]);
            set_warned(False);
            set_news("Your seats are held for longer.");
            return;
        }
        set_problem(_message(kept));
    }

    async def change_seats {
        set_busy(True);
        await call(release_hold, [slug, screening_id, holder]);
        set_busy(False);
        set_hold(None);
        set_quote(None);
        set_glasses_seats([]);
        set_problem("");
        load_map();
    }

    async def pay(snacks: list[dict[str, any]]) {  # jac:ignore[W1037]
        set_busy(True);
        sent = cart_lines(snacks);
        placed = await call(
            place_order,
            [slug, screening_id, holder, key, items, sent, selected_glasses]
        );
        if _code(placed) == "order_in_progress" {
            # The same order is still being made: ask again with the same key.
            await new(Promise, lambda (done: any) { setTimeout(done, 1000); });  # jac:ignore[W1037,W2001]
            placed = await call(
                place_order,
                [slug, screening_id, holder, key, items, sent, selected_glasses]
            );
        }
        set_busy(False);
        if placed is not None and placed["ok"] {
            set_order(placed["order"]);
            set_problem("");
            set_news(f"Order placed. Reference {placed['order']['reference']}.");
            return;
        }
        if _code(placed) == "no_hold" {
            set_hold(None);
            set_quote(None);
            load_map();
        }
        if _code(placed) == "snacks_unavailable" {
            # Something sold out: the snack step shows the cart, repriced, to change.
            set_snack_step(True);
            price_cart(cart);
        }
        set_problem(_message(placed));
    }

    def to_snacks_or_pay {
        if has_snacks(menu) {
            set_snack_step(True);
            set_problem("");
            set_news("Add snacks, or skip this.");
        } else {
            pay([]);
        }
    }

    status_line = <p aria-live="polite" className="sr-only" data-testid="checkout-news">
        {news}
    </p>;
    problem_box = problem
        and <p
            role="alert"
            data-testid="checkout-problem"
            className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm"
        >
            {problem}
        </p>;

    if paid is not None {
        return
            <div data-testid="checkout" className="flex flex-col gap-4">
                {status_line}{(
                    done_panel(paid)
                        if done_panel is not None
                        else <Tickets payment={paid}/>
                )}
            </div>;
    }
    if order is not None and expired {
        return
            <div data-testid="checkout" className="flex flex-col gap-4">
                {status_line}
                <section
                    data-testid="time-up"
                    aria-labelledby="time-up-heading"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                >
                    <h3 id="time-up-heading" className="text-lg font-semibold">
                        The time to pay ran out
                    </h3>
                    <p className="text-sm text-muted-foreground">
                        Your seats were released so others could book them. If they are still free, you can choose them again.
                    </p>
                    <Button
                        data-testid="choose-again"
                        onClick={choose_again}
                        className="min-h-11 w-fit px-5"
                    >
                        Choose seats again
                    </Button>
                </section>
            </div>;
    }
    if order is not None {
        placed: dict[str, any] = order;  # jac:ignore[W1037]

        def on_paid(payment: dict[str, any]) {  # jac:ignore[W1037]
            set_paid(payment);
            set_news("Paid. Your tickets are ready.");
        }

        return
            <div data-testid="checkout" className="flex flex-col gap-4">
                {status_line}
                <Button
                    variant="ghost"
                    data-testid="change-order"
                    disabled={busy}
                    onClick={go_back}
                    className="min-h-11 w-fit px-3"
                >
                    ← Change seats or snacks
                </Button>
                {problem_box}
                <Ordered order={placed} tz={tz} at_counter={bool(counter_holder)}/>
                {(
                    pay_panel(placed, on_paid, time_up)
                        if pay_panel is not None
                        else <PayPanel
                            slug={slug}
                            screening_id={screening_id}
                            holder={holder}
                            amount={money(placed["total_cents"], placed["currency"])}
                            initial={pay_state}
                            on_paid={on_paid}
                            on_expired={time_up}
                        />
                )}
            </div>;
    }
    if seat_map is None {
        return
            <div data-testid="checkout" className="flex flex-col gap-4">
                {status_line}
                <p className="text-muted-foreground">Loading the seats…</p>
            </div>;
    }
    if hold is None {
        selling = len(tickets) > 0;
        return
            <div data-testid="checkout" className="flex flex-col gap-4">
                {status_line}
                {not selling
                    and <p
                        role="status"
                        data-testid="booking-closed"
                        className="rounded-md border bg-muted px-3 py-2 text-sm"
                    >
                        Online booking isn't open for this cinema yet. You can see the seats, but not choose them here.
                    </p>}
                <SeatMap
                    seat_map={seat_map}
                    chosen={chosen}
                    on_toggle={toggle}
                    locked={not selling}
                />
                {problem_box}
                {selling
                    and <BottomBar>
                        <p data-testid="chosen-seats" className="min-w-0 text-sm">
                            {(
                                f"{len(picked)} seat{'' if len(picked) == 1 else 's'}: {', '.join(
                                    chosen
                                )}"
                                    if len(picked) > 0
                                    else "Tap the seats you'd like."
                            )}
                        </p>
                        <Button
                            data-testid="hold-seats"
                            disabled={busy or len(picked) == 0}
                            onClick={hold_chosen}
                            className="min-h-11 shrink-0 px-5"
                        >
                            {"Holding…" if busy else "Continue"}
                        </Button>
                    </BottomBar>}
            </div>;
    }
    if snack_step and has_snacks(menu) {
        tickets_cents: int = priced_now["total_cents"] if priced_now is not None else 0;
        snacks_priced: dict[str, any] | None = snack_price;  # jac:ignore[W1037]
        in_cart: list[dict[str, any]] = cart;  # jac:ignore[W1037]
        return
            <div data-testid="checkout" className="flex flex-col gap-4">
                {status_line}
                <div className="flex flex-wrap items-center justify-between gap-3">
                    <Button
                        variant="ghost"
                        data-testid="back-to-tickets"
                        disabled={busy}
                        onClick={lambda { set_snack_step(False); }}
                        className="min-h-11 w-fit px-3"
                    >
                        ← Tickets
                    </Button>
                    <p
                        data-testid="hold-timer"
                        className={"flex items-center gap-1.5 text-sm font-medium tabular-nums "
                            + (
                                "text-[var(--ac-warning)]"
                                    if left <= WARN_SECONDS
                                    else "text-muted-foreground"
                            )}
                    >
                        <HugeiconsIcon
                            icon={Clock01Icon}
                            strokeWidth={2}
                            className="size-4"
                            aria-hidden="true"
                        />
                        {f"Seats held for {countdown(left)}"}
                    </p>
                </div>
                <SnackStep
                    slug={slug}
                    menu={menu}
                    cart={cart}
                    on_cart={set_cart}
                    priced={snack_price}
                    busy={busy}
                />
                {problem_box}
                <BottomBar>
                    <div className="flex min-w-0 flex-col">
                        <span className="text-xs text-muted-foreground">
                            {"Tickets and snacks" if len(in_cart) > 0 else "Tickets"}
                        </span>
                        <span
                            data-testid="checkout-total"
                            className="text-lg font-semibold tabular-nums"
                        >
                            {money(
                                tickets_cents
                                    + snacks_priced["total_cents"]
                                    + len(selected_glasses) * glasses_cents,
                                currency
                            )
                                if snacks_priced is not None
                                else "…"}
                        </span>
                    </div>
                    <div className="flex shrink-0 gap-2">
                        <Button
                            variant="outline"
                            data-testid="skip-snacks"
                            disabled={busy}
                            onClick={lambda { pay([]); }}
                            className="min-h-11 px-4"
                        >
                            Skip
                        </Button>
                        <Button
                            data-testid="snacks-continue"
                            disabled={busy
                                or len(in_cart) == 0
                                or snacks_priced is None}
                            onClick={lambda { pay(in_cart); }}
                            className="min-h-11 px-4"
                        >
                            {"Placing order…" if busy else "Continue"}
                        </Button>
                    </div>
                </BottomBar>
            </div>;
    }
    return
        <div data-testid="checkout" className="flex flex-col gap-4">
            {status_line}
            <section
                aria-labelledby="tickets-heading"
                className="flex flex-col gap-4 rounded-lg border bg-card p-4"
            >
                <div className="flex flex-wrap items-center justify-between gap-3">
                    <h3 id="tickets-heading" className="text-lg font-semibold">
                        Choose your tickets
                    </h3>
                    <p
                        data-testid="hold-timer"
                        className={"flex items-center gap-1.5 text-sm font-medium tabular-nums "
                            + (
                                "text-[var(--ac-warning)]"
                                    if left <= WARN_SECONDS
                                    else "text-muted-foreground"
                            )}
                    >
                        <HugeiconsIcon
                            icon={Clock01Icon}
                            strokeWidth={2}
                            className="size-4"
                            aria-hidden="true"
                        />
                        {f"Seats held for {countdown(left)}"}
                    </p>
                </div>
                {left <= WARN_SECONDS
                    and <div
                        className="flex flex-wrap items-center justify-between gap-3 rounded-md bg-muted px-3 py-2"
                    >
                        <p className="text-sm">Need more time?</p>
                        <Button
                            variant="outline"
                            data-testid="keep-seats"
                            disabled={busy}
                            onClick={keep_longer}
                            className="min-h-11 px-4"
                        >
                            Keep my seats
                        </Button>
                    </div>}
                <ul className="flex flex-col divide-y">
                    {[
                        <li
                            key={item["seat_label"]}
                            data-testid="ticket-line"
                            className="flex flex-wrap items-center justify-between gap-3 py-3"
                        >
                            <label
                                htmlFor={f"ticket-{item['seat_label']}"}
                                className="font-medium"
                            >
                                {f"Seat {item['seat_label']}"}
                            </label>
                            <div className="flex items-center gap-3">
                                <select
                                    id={f"ticket-{item['seat_label']}"}
                                    data-testid="ticket-type"
                                    value={item["ticket_type"]}
                                    onChange={lambda (e: any) { set_items(  # jac:ignore[W1037]
                                        _with_ticket(
                                            lines, item["seat_label"], e.target.value
                                        )
                                    ); }}
                                    className="min-h-11 rounded-md border border-input bg-background px-2 text-sm"
                                >
                                    {[
                                        <option key={t["code"]} value={t["code"]}>
                                            {t["name"]}
                                        </option> for t in tickets
                                    ]}
                                </select>
                                <span className="min-w-20 text-right tabular-nums">
                                    {money(
                                        _line_for(quote, item["seat_label"])[
                                            "total_cents"
                                        ],
                                        currency
                                    )
                                        if _line_for(quote, item["seat_label"])
                                            is not None
                                        else "…"}
                                </span>
                            </div>
                        </li> for item in lines
                    ]}
                </ul>
                {glasses_now is not None
                    and <fieldset
                        data-testid="glasses-choice"
                        className="flex flex-col gap-2 rounded-lg border bg-muted/30 p-3"
                    >
                        <legend className="px-1 text-sm font-semibold">
                            3D glasses
                        </legend>
                        <p className="text-sm text-muted-foreground">
                            I'll bring my own is the default. Buy only for the people who need a pair.
                        </p>
                        <div className="grid gap-2 sm:grid-cols-2">
                            {[
                                <label
                                    key={item["seat_label"]}
                                    className="flex min-h-11 cursor-pointer items-center gap-3 rounded-md border bg-background px-3 py-2 text-sm focus-within:ring-2 focus-within:ring-ring"
                                >
                                    <input
                                        type="checkbox"
                                        checked={listed(
                                            item["seat_label"], selected_glasses
                                        )}
                                        onChange={lambda (e: any) { set_glasses_seats(  # jac:ignore[W1037]
                                            _with_glasses(
                                                selected_glasses,
                                                item["seat_label"],
                                                e.target.checked
                                            )
                                        ); }}
                                        className="size-5 accent-primary"
                                    />
                                    <span
                                        className="flex min-w-0 flex-1 justify-between gap-2"
                                    >
                                        <span>{f"Seat {item['seat_label']}"}</span>
                                        <span className="tabular-nums">
                                            {money(glasses_cents, currency)}
                                        </span>
                                    </span>
                                </label> for item in lines
                            ]}
                        </div>
                    </fieldset>}
                <p className="text-xs text-muted-foreground">
                    Prices include the booking fee.
                </p>
                <Button
                    variant="ghost"
                    data-testid="change-seats"
                    disabled={busy}
                    onClick={change_seats}
                    className="min-h-11 w-fit px-3"
                >
                    Change seats
                </Button>
            </section>
            {problem_box}
            <BottomBar>
                <div className="flex min-w-0 flex-col">
                    <span className="text-xs text-muted-foreground">
                        {f"Seats {', '.join(chosen)}"}
                    </span>
                    <span
                        data-testid="checkout-total"
                        className="text-lg font-semibold tabular-nums"
                    >
                        {money(
                            priced_now["total_cents"]
                                + len(selected_glasses) * glasses_cents,
                            priced_now["currency"]
                        )
                            if priced_now is not None
                            else "…"}
                    </span>
                </div>
                <Button
                    data-testid="pay"
                    disabled={busy or quote is None or menu is None}
                    onClick={to_snacks_or_pay}
                    className="min-h-11 shrink-0 px-5"
                >
                    {"Placing order…"
                        if busy
                        else ("Continue" if has_snacks(menu) else "Proceed to pay")}
                </Button>
            </BottomBar>
        </div>;
}
