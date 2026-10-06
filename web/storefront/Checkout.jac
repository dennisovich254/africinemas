"""Checkout on a showtime's page (P4.6): choose seats, hold them, choose tickets, order.

1. Choose: the seat map (SeatMap); a bar fixed to the bottom of the screen shows the
   chosen seats and holds them (hold_seats). A seat someone has just taken is dropped
   from the choice, and the visitor is told which.
2. Tickets: the seats are held for a few minutes, counting down. Before the time runs
   out the visitor is told and can keep the seats longer (extend_hold, up to the
   cinema's limit; WCAG 2.2.1); if it does run out, the seats go back and so does the
   visitor, with a message. Each seat gets a ticket type; the server prices them
   (quote_hold) and the bar shows the total. "Change seats" gives the hold back.
3. Pay: places the order (place_order) with an idempotency key made for this order and
   reused if the request is sent again, then pays it with M-Pesa (PayPanel, P5.6): a PIN
   prompt on the phone, the status live, and the tickets once paid (Tickets).

A reload comes back to the same step: the browser keeps the visitor's holder id for
the visit, and my_order / my_hold say where they were. Changes worth hearing (held,
time nearly up, seats released, order placed) are announced politely.
"""

import from react { useState, useEffect, useRef }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Clock01Icon }
import from ...components.ui.button { Button }
import from core.catalog.storefront_api { public_seat_availability }
import from core.booking.hold_api { hold_seats, my_hold, release_hold, extend_hold }
import from core.booking.order_api {
    place_order,
    my_order,
    quote_hold,
    public_ticket_types
}
import from .SeatMap { SeatMap }
import from .PayPanel { PayPanel, Tickets }
import from core.payments.settlement { my_payment }
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

def Ordered(order: dict[str, any], tz: str) -> JsxElement {  # jac:ignore[W1037]
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
                ]}
            </ul>
            <p className="flex items-center justify-between text-lg font-semibold">
                <span>Total</span>
                <span data-testid="order-total" className="tabular-nums">
                    {money(order["total_cents"], order["currency"])}
                </span>
            </p>
            <p className="text-sm text-muted-foreground">
                {f"Your seats are kept for you until {time_label(
                    order['pay_by'], tz
                )}. Pay before then to get your tickets."}
            </p>
        </section>;
}

def:pub Checkout(slug: str, screening_id: str, tz: str) -> JsxElement {
    holder = visitor_id();
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
    [key, set_key] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [news, set_news] = useState("");
    [now_ms, set_now_ms] = useState(Date.now());  # jac:ignore[W2001]
    [warned, set_warned] = useState(False);
    asked_count = useRef(0);
    picked: list[str] = chosen;
    lines: list[dict[str, str]] = items;
    tickets: list[dict[str, str]] = types;
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
        shown = await call(public_seat_availability, [slug, screening_id]);
        if shown is not None and shown["ok"] {
            set_seat_map(shown);
        }
    }

    def begin_tickets(held: dict[str, any], codes: list[dict[str, str]]) {  # jac:ignore[W1037]
        set_hold(held);
        set_chosen(held["seats"]);
        set_items(_items(held["seats"], codes[0]["code"] if codes else ""));
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
            }
        }
        await load_map();
    }

    def kick_off {
        start();
    }
    useEffect(kick_off, [slug, screening_id]);

    def tick -> any {  # jac:ignore[W1037]
        if hold is None or order is not None {
            return lambda {};
        }
        timer = setInterval(lambda { set_now_ms(Date.now()); }, 1000);  # jac:ignore[W2001]
        return lambda { clearInterval(timer); };  # jac:ignore[W2001]
    }
    useEffect(tick, [hold, order]);

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
        held = await call(hold_seats, [slug, screening_id, holder, chosen]);
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
        set_problem("");
        load_map();
    }

    async def pay {
        set_busy(True);
        placed = await call(place_order, [slug, screening_id, holder, key, items]);
        if _code(placed) == "order_in_progress" {
            # The same order is still being made: ask again with the same key.
            await new(Promise, lambda (done: any) { setTimeout(done, 1000); });  # jac:ignore[W1037,W2001]
            placed = await call(place_order, [slug, screening_id, holder, key, items]);
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
        set_problem(_message(placed));
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
                {status_line}
                <Tickets payment={paid}/>
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
                <Ordered order={placed} tz={tz}/>
                <PayPanel
                    slug={slug}
                    screening_id={screening_id}
                    holder={holder}
                    total_cents={placed["total_cents"]}
                    currency={placed["currency"]}
                    initial={pay_state}
                    on_paid={on_paid}
                />
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
                        {money(priced_now["total_cents"], priced_now["currency"])
                            if priced_now is not None
                            else "…"}
                    </span>
                </div>
                <Button
                    data-testid="pay"
                    disabled={busy or quote is None}
                    onClick={pay}
                    className="min-h-11 shrink-0 px-5"
                >
                    {"Placing order…" if busy else "Proceed to pay"}
                </Button>
            </BottomBar>
        </div>;
}
