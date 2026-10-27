"""Box office: selling to walk-in customers at the counter (P6.5; ADR-0025).

The agent picks a showtime on sale at their venues (counter_showtimes), then books on
the storefront's own seat map and ticket types (Checkout in counter mode, under a
counter holder id, one per sale) and takes the money (CounterPay):

- Cash: "Cash received", then "Confirm" (two steps, so a slip doesn't sell): the order
  is confirmed and the tickets issued at once (sell_for_cash).
- M-Pesa: the customer's number gets the PIN prompt (sell_with_mpesa); the page follows
  the payment (my_payment) until it's paid or refused.

An email address for the tickets is optional. Once paid (CounterDone), the tickets and
any snack pickup show with their QR codes; snacks can be handed over there immediately,
or all codes can be printed. New sale starts over with a new holder id.
**Snacks only** (P12.10) sells snacks to a walk-in without a ticket (SnackOnlySale).
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.booking.counter_api {
    counter_showtimes,  # jac:ignore[W2037] authenticated endpoints
    sell_for_cash,  # jac:ignore[W2037]
    sell_with_mpesa  # jac:ignore[W2037]
}
import from core.payments.settlement { my_payment }
import from core.snacks.pickup_api { hand_over_snacks }  # jac:ignore[W2037]
import from ..storefront.Checkout { Checkout }
import from ..storefront.PayPanel { TicketCard, PickupCard }
import from ..storefront.checkout_rules {
    money,
    email_problem,
    phone_problem,
    random_id
}
import from .CounterPicker { CounterPicker }
import from .SnackOnlySale { SnackOnlySale }
import from ..storefront.MoreSnacks { CounterMoreSnacks }

glob POLL_MS: int = 3000;

def _counter_holder -> str {
    return random_id("counter");
}

async def _call(fn: any, args: list[any]) -> any {  # jac:ignore[W1037]
    try {
        return await fn(*args);
    } except Exception as e {
        console.warn("box office call failed", e);
        return None;
    }
}

def CounterPay(
    tenant: str,
    screening_id: str,
    holder: str,
    order: dict[str, any],  # jac:ignore[W1037]
    on_paid: any,  # jac:ignore[W1037]
    on_expired: any  # jac:ignore[W1037]
) -> JsxElement {
    amount: str = money(order["total_cents"], order["currency"]);
    [confirming, set_confirming] = useState(False);
    [phone, set_phone] = useState("");
    [email, set_email] = useState("");
    [busy, set_busy] = useState(False);
    [waiting, set_waiting] = useState(False);
    [problem, set_problem] = useState("");
    is_confirming: bool = confirming;
    is_busy: bool = busy;
    is_waiting: bool = waiting;
    trouble: str = problem;

    def refused(answer: dict[str, any]) {  # jac:ignore[W1037]
        if answer["error"]["code"] == "order_expired" {
            on_expired();
            return;
        }
        set_problem(answer["error"]["message"]);
    }

    def email_ok -> bool {
        wrong = email_problem(email) if len(email.strip()) > 0 else "";
        set_problem(wrong);
        return len(wrong) == 0;
    }

    async def take_cash {
        if not email_ok() {
            return;
        }
        set_busy(True);
        sold: any = await _call(sell_for_cash, [tenant, screening_id, holder, email]);  # jac:ignore[W1037,W2037]
        set_busy(False);
        set_confirming(False);
        if sold is None {
            set_problem(
                "The sale didn't go through: the server didn't answer as expected. Nothing was sold; try again."
            );
        } elif sold["ok"] {
            on_paid(sold["payment"]);
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
        if not email_ok() {
            return;
        }
        set_busy(True);
        started: any = await _call(  # jac:ignore[W1037]
            sell_with_mpesa,  # jac:ignore[W2037]
            [tenant, screening_id, holder, phone, email]
        );
        set_busy(False);
        if started is None {
            set_problem(
                "The prompt wasn't sent: the server didn't answer as expected. Try again."
            );
        } elif started["ok"] {
            set_problem("");
            set_waiting(True);
        } else {
            refused(started);
        }
    }

    async def check {
        got: any = await _call(my_payment, [tenant, screening_id, holder]);  # jac:ignore[W1037]
        if got is None or not got["ok"] {
            return;
        }
        paid: dict[str, any] = got["payment"];  # jac:ignore[W1037]
        if paid["state"] == "success" {
            set_waiting(False);
            on_paid(paid);
        } elif paid["state"] == "failed" or paid["state"] == "cancelled" {
            set_waiting(False);
            set_problem(paid["message"]);
        }
    }

    def poll -> any {  # jac:ignore[W1037]
        if not is_waiting {
            return lambda {};
        }
        timer = setInterval(lambda { check(); }, POLL_MS);  # jac:ignore[W2001]
        return lambda { clearInterval(timer); };  # jac:ignore[W2001]
    }
    useEffect(poll, [is_waiting]);

    def typed_phone(e: any) {  # jac:ignore[W1037]
        set_phone(e.target.value);
    }

    def typed_email(e: any) {  # jac:ignore[W1037]
        set_email(e.target.value);
    }

    return
        <section
            data-testid="counter-pay"
            aria-labelledby="counter-pay-heading"
            className="flex flex-col gap-4 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-wrap items-baseline justify-between gap-2">
                <h3 id="counter-pay-heading" className="text-lg font-semibold">
                    Take payment
                </h3>
                <p data-testid="counter-total" className="text-2xl font-semibold">
                    {amount}
                </p>
            </div>
            <div className="flex flex-col gap-1.5">
                <Label htmlFor="counter-email">Customer's email (optional)</Label>
                <Input
                    id="counter-email"
                    type="email"
                    inputMode="email"
                    autoComplete="off"
                    placeholder="name@example.com"
                    value={email}
                    onChange={typed_email}
                    className="h-11 max-w-xs text-base"
                />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
                <div className="flex flex-col gap-2 rounded-md border p-3">
                    <p className="font-medium">Cash</p>
                    {(
                        <div className="flex flex-wrap gap-2">
                            <Button
                                data-testid="confirm-cash"
                                disabled={is_busy}
                                onClick={lambda { take_cash(); }}
                                className="min-h-11"
                            >
                                {is_busy and <Spinner aria-hidden="true"/>}{f"Confirm {amount} received"}
                            </Button>
                            <Button
                                variant="ghost"
                                disabled={is_busy}
                                onClick={lambda { set_confirming(False); }}
                                className="min-h-11"
                            >
                                Cancel
                            </Button>
                        </div>
                    )
                        if is_confirming
                        else <Button
                            data-testid="cash-received"
                            disabled={is_busy or is_waiting}
                            onClick={lambda { set_confirming(True); }}
                            className="min-h-11 w-fit"
                        >
                            Cash received
                        </Button>}
                </div>
                <form
                    onSubmit={send_prompt}
                    noValidate={True}
                    className="flex flex-col gap-2 rounded-md border p-3"
                >
                    <Label htmlFor="counter-phone">M-Pesa: customer's number</Label>
                    <Input
                        id="counter-phone"
                        type="tel"
                        inputMode="tel"
                        autoComplete="off"
                        placeholder="0712 345 678"
                        value={phone}
                        onChange={typed_phone}
                        className="h-11 text-base"
                    />
                    <Button
                        type="submit"
                        data-testid="counter-mpesa"
                        disabled={is_busy or is_waiting}
                        className="min-h-11 w-fit"
                    >
                        Send M-Pesa prompt
                    </Button>
                </form>
            </div>
            <div role="status" aria-live="polite">
                {is_waiting
                    and <p
                        data-testid="counter-waiting"
                        className="flex items-center gap-2 text-sm"
                    >
                        <Spinner aria-hidden="true"/>
                        Waiting for the customer to enter their M-Pesa PIN…
                    </p>}
            </div>
            {len(trouble) > 0
                and <p
                    role="alert"
                    data-testid="counter-problem"
                    className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm"
                >
                    {trouble}
                </p>}
        </section>;
}

def _print {
    win: any = window;  # jac:ignore[W1037,W2001]
    win.print();
}

def CounterDone(tenant: str, payment: dict[str, any], on_new_sale: any) -> JsxElement {  # jac:ignore[W1037]
    tickets: list[dict[str, str]] = payment["tickets"];
    snacks: list[dict[str, any]] = payment["snacks"] or [];  # jac:ignore[W1037]
    pickup: any = payment["pickup"];  # jac:ignore[W1037]
    [busy, set_busy] = useState(False);
    [handed, set_handed] = useState(False);
    [problem, set_problem] = useState("");
    is_busy: bool = busy;
    is_handed: bool = handed;
    trouble: str = problem;

    def print_tickets {
        _print();
    }

    async def hand_over {
        set_busy(True);
        set_problem("");
        done: any = await _call(hand_over_snacks, [tenant, pickup["qr"]]);  # jac:ignore[W1037,W2037]
        set_busy(False);
        if done is None or not done["ok"] {
            set_problem(
                done["error"]["message"]
                    if done is not None
                    else "The server didn't answer. Nothing changed; try again."
            );
            return;
        }
        set_handed(True);
    }
    return
        <section
            data-testid="counter-done"
            aria-labelledby="counter-done-heading"
            className="flex flex-col gap-4 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-col gap-1">
                <h3 id="counter-done-heading" className="text-lg font-semibold">
                    Sold
                </h3>
                <p className="text-sm text-muted-foreground">
                    {f"Paid {money(
                        payment['amount_cents'], payment['currency']
                    )}. Give the customer their tickets"
                        + (
                            " and snacks. Print the pickup code if they will collect the snacks later."
                                if len(snacks) > 0
                                else ": print them, or let them photograph the QR codes."
                        )}
                </p>
            </div>
            <ul className="grid gap-3 sm:grid-cols-2">
                {[<TicketCard key={t["reference"]} ticket={t}/> for t in tickets]}
            </ul>
            {len(snacks) > 0
                and <PickupCard
                    snacks={snacks}
                    pickup={pickup}
                    note="Hand these snacks over now, or print this code for later collection."
                />}
            {len(snacks) > 0
                and not is_handed
                and pickup is not None
                and <Button
                    data-testid="counter-hand-over-snacks"
                    disabled={is_busy}
                    onClick={lambda { hand_over(); }}
                    className="min-h-11 w-fit print:hidden"
                >
                    {is_busy and <Spinner aria-hidden="true"/>}Hand over snacks now
                </Button>}
            {is_handed
                and <p
                    role="status"
                    data-testid="counter-snacks-handed"
                    className="text-sm font-medium text-green-700 dark:text-green-400"
                >
                    Snacks handed over.
                </p>}
            {len(trouble) > 0
                and <p
                    role="alert"
                    className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm"
                >
                    {trouble}
                </p>}
            <div className="flex flex-wrap gap-2 print:hidden">
                <Button
                    variant="outline"
                    data-testid="print-tickets"
                    onClick={print_tickets}
                    className="min-h-11"
                >
                    {"Print tickets and pickup code"
                        if len(snacks) > 0
                        else "Print tickets"}
                </Button>
                <Button
                    data-testid="new-sale"
                    onClick={lambda { on_new_sale(); }}
                    className="min-h-11"
                >
                    New sale
                </Button>
            </div>
        </section>;
}

def SaleKind(kind: str, on_kind: any) -> JsxElement {  # jac:ignore[W1037]
    # Tickets (with snacks if the customer wants) or snacks only (P12.10).
    return
        <div
            role="group"
            aria-label="What's being sold"
            className="flex flex-wrap gap-2 border-b"
        >
            {[
                <button
                    key={k}
                    type="button"
                    aria-pressed={"true" if kind == k else "false"}
                    data-testid={f"sale-kind-{k}"}
                    onClick={lambda { on_kind(k); }}
                    className={"-mb-px inline-flex min-h-11 items-center border-b-2 px-3 text-sm font-medium "
                        + (
                            "border-primary text-foreground"
                                if kind == k
                                else "border-transparent text-muted-foreground hover:text-foreground"
                        )}
                >
                    {label}
                </button>
                for (k, label) in [
                    ("tickets", "Tickets"),
                    ("snacks", "Snacks only"),
                    ("extra", "Existing booking")
                ]
            ]}
        </div>;
}

def:pub BoxOfficeSection(slug: str, shift_open: bool = True) -> JsxElement {
    # shift_open: reload once the member starts their shift (the server refuses without).
    [kind, set_kind] = useState("tickets");
    [page, set_page] = useState(None);
    [chosen, set_chosen] = useState("");
    [holder, set_holder] = useState(_counter_holder());
    found: dict[str, any] | None = page;  # jac:ignore[W1037]
    screening_id: str = chosen;
    sale: str = holder;

    async def load {
        got: any = await _call(counter_showtimes, [slug]);  # jac:ignore[W1037,W2037]
        set_page(
            got
                or {
                    "ok": False,
                    "error": {"message": "We couldn't load the showtimes."}
                }
        );
    }

    def start_loading -> any {  # jac:ignore[W1037]
        load();
        return lambda {};
    }
    useEffect(start_loading, [slug, shift_open]);

    def new_sale {
        set_holder(_counter_holder());
    }

    def choose(sid: str) {
        set_chosen(sid);
        new_sale();
    }

    if kind == "extra" {
        return
            <div className="flex flex-col gap-6">
                <SaleKind kind={kind} on_kind={set_kind}/>
                <CounterMoreSnacks slug={slug}/>
            </div>;
    }
    if kind == "snacks" {
        return
            <div className="flex flex-col gap-6">
                <SaleKind kind={kind} on_kind={set_kind}/>
                <SnackOnlySale slug={slug} shift_open={shift_open}/>
            </div>;
    }
    tabs = <SaleKind kind={kind} on_kind={set_kind}/>;
    if found is None {
        return <Spinner aria-label="Loading"/>;
    }
    if not found["ok"] {
        return
            <p
                role="alert"
                data-testid="box-office-problem"
                className="text-destructive"
            >
                {found["error"]["message"]}
            </p>;
    }
    showtimes: list[dict[str, any]] = found["showtimes"];  # jac:ignore[W1037]
    tz: str = found["timezone"];
    cinema_slug: str = found["slug"];
    if len(showtimes) == 0 {
        return
            <div className="flex flex-col gap-6">
                {tabs}
                <p data-testid="nothing-on-sale" className="text-muted-foreground">
                    No tickets are on sale at your venues right now; showtimes appear here once they're published. You can still sell snacks.
                </p>
            </div>;
    }
    pay_panel = lambda (placed: any, on_paid: any, on_expired: any) -> any { return  # jac:ignore[W1037]
        <CounterPay
            tenant={cinema_slug}
            screening_id={screening_id}
            holder={sale}
            order={placed}
            on_paid={on_paid}
            on_expired={on_expired}
        />; };
    done_panel = lambda (paid: any) -> any { return  # jac:ignore[W1037]
        <CounterDone tenant={cinema_slug} payment={paid} on_new_sale={new_sale}/>; };
    return
        <div data-testid="box-office" className="flex flex-col gap-6">
            {tabs}
            <CounterPicker
                showtimes={showtimes}
                slug={cinema_slug}
                tz={tz}
                chosen={screening_id}
                on_choose={choose}
            />
            {len(screening_id) > 0
                and <Checkout
                    key={sale}
                    slug={cinema_slug}
                    screening_id={screening_id}
                    tz={tz}
                    counter_holder={sale}
                    pay_panel={pay_panel}
                    done_panel={done_panel}
                />}
        </div>;
}
