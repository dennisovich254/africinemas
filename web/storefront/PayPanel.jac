"""Paying an order with M-Pesa on the showtime page (P5.6).

The visitor enters their M-Pesa number (a tel keypad; checked inline as the server
checks it), and pays: start_payment sends the PIN prompt to their phone. The panel then
says to check the phone and asks my_payment every few seconds what happened, announcing
changes politely. Paid: the parent shows the tickets (Tickets). Failed or cancelled: the
message, and the form again to try once more (a new attempt, with a new idempotency
key). The visitor's PIN never touches the app (architecture §39).
"""

import from react { useState, useEffect }
# The checker reads the dot as a module separator (docs/jac-issues/JI-039).
import from "qrcode.react" { QRCodeSVG }  # jac:ignore[W1101]
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.payments.payment_api { start_payment }
import from core.payments.settlement { my_payment }
import from .showtimes { listed }
import from .checkout_rules { money, phone_problem, email_problem, order_key }
import from .TicketDelivery { TicketDelivery }

glob WAITING: list[str] = ["created", "stk_requested", "timeout", "unknown"],
     RETRYABLE: list[str] = ["failed", "cancelled"],
     POLL_MS: int = 3000;

def:pub TicketCard(ticket: dict[str, str]) -> JsxElement {
    # One ticket: its seat, the QR code the door scans (P6.1) and the reference under
    # it, for reading out or typing in when a scan fails. The code is always dark on a
    # white tile with a margin, in either theme, so scanners read it. A ticket issued
    # before 6.1 has no QR and shows its reference only.
    qr: str = ticket["qr"] or "";
    return
        <li
            data-testid="ticket"
            className="flex flex-col items-center gap-3 rounded-lg border p-4"
        >
            <p className="self-start font-medium">
                {f"Seat {ticket['seat_label']} · {ticket['ticket_name']}"}
            </p>
            {len(qr) > 0
                and <div className="rounded-md bg-white p-2">
                    <QRCodeSVG  # jac:ignore[W1051]
                        value={qr}
                        size={192}
                        level="M"
                        marginSize={2}
                        bgColor="#FFFFFF"
                        fgColor="#000000"
                        role="img"
                        aria-label={f"QR code for seat {ticket['seat_label']}, ticket {ticket[
                            'reference'
                        ]}"}
                        data-testid="ticket-qr"
                        data-payload={qr}
                    />
                </div>}
            <p
                className="font-mono text-base tracking-wider"
                data-testid="ticket-reference"
            >
                {ticket["reference"]}
            </p>
        </li>;
}

def:pub Tickets(payment: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    # A paid order's tickets: one card per seat, with its QR code and reference.
    tickets: list[dict[str, str]] = payment["tickets"];
    link: str = payment["link"] or "";
    return
        <section
            data-testid="booked"
            aria-labelledby="booked-heading"
            className="flex flex-col gap-4 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-col gap-1">
                <h3 id="booked-heading" className="text-lg font-semibold">
                    You're booked
                </h3>
                <p className="text-sm text-muted-foreground">
                    {f"Paid {money(
                        payment['amount_cents'], payment['currency']
                    )} with M-Pesa. Show each ticket's QR code at the door."}
                </p>
            </div>
            <ul className="grid gap-3 sm:grid-cols-2">
                {[<TicketCard key={t["reference"]} ticket={t}/> for t in tickets]}
            </ul>
            {len(link) > 0
                and <TicketDelivery
                    link={link}
                    email={payment["email"]}
                    show_open={True}
                />}
        </section>;
}

def:pub PayPanel(
    slug: str,
    screening_id: str,
    holder: str,
    amount: str,
    initial: any,  # jac:ignore[W1037]
    on_paid: any,  # jac:ignore[W1037]
    on_expired: any  # jac:ignore[W1037]
) -> JsxElement {
    [payment, set_payment] = useState(initial);
    [phone, set_phone] = useState("");
    [phone_error, set_phone_error] = useState("");
    [email, set_email] = useState("");
    [email_error, set_email_error] = useState("");
    email_wrong: str = email_error;
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    current: dict[str, any] | None = payment;  # jac:ignore[W1037]
    state: str = current["state"] if current is not None else "";
    waiting: bool = listed(state, WAITING);

    async def call(fn: any, args: list[any]) -> any {  # jac:ignore[W1037]
        try {
            return await fn(*args);
        } except Exception as e {
            console.warn("payment call failed", e);
            return None;
        }
    }

    def seen(found: dict[str, any]) {  # jac:ignore[W1037]
        set_payment(found);
        if found["state"] == "success" {
            on_paid(found);
        }
    }

    async def check {
        got = await call(my_payment, [slug, screening_id, holder]);
        if got is not None and got["ok"] {
            seen(got["payment"]);
        }
    }

    def poll -> any {  # jac:ignore[W1037]
        if not waiting {
            return lambda {};
        }
        timer = setInterval(lambda { check(); }, POLL_MS);  # jac:ignore[W2001]
        return lambda { clearInterval(timer); };  # jac:ignore[W2001]
    }
    useEffect(poll, [state]);

    def checked(text: str) {
        set_phone_error(phone_problem(text) if len(text.strip()) > 0 else "");
    }

    async def pay(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        wrong = phone_problem(phone);
        set_phone_error(wrong);
        address_wrong = email_problem(email);
        set_email_error(address_wrong);
        if len(wrong) > 0 or len(address_wrong) > 0 {
            return;
        }
        set_busy(True);
        set_problem("");
        started = await call(
            start_payment, [slug, screening_id, holder, phone, email, order_key()]
        );
        set_busy(False);
        if started is None {
            set_problem(
                "We couldn't reach the cinema. Check your connection and try again."
            );
            return;
        }
        if started["ok"] {
            seen(started["payment"]);
            return;
        }
        refused: dict[str, any] = started["error"];  # jac:ignore[W1037]
        if refused["code"] == "invalid_email" {
            set_email_error(refused["message"]);
            return;
        }
        if refused["code"] == "order_expired" {
            # The order's time to pay is up: the page offers the seats again.
            on_expired();
            return;
        }
        # listed(): a typed membership test, not JavaScript's `in` (JI-035).
        if refused["code"] == "payment_in_progress"
            and listed("payment", Object.keys(refused)) {  # jac:ignore[W2001]
            seen(refused["payment"]);
            return;
        }
        set_problem(started["error"]["message"]);
    }

    status = current is not None
        and <div
            role="status"
            aria-live="polite"
            data-testid="payment-status"
            data-state={state}
            className={"flex items-start gap-3 rounded-md border px-3 py-3 text-sm "
                + ("bg-muted" if waiting else "bg-card")}
        >
            {waiting
                and <Spinner aria-hidden="true" className="mt-0.5 size-4 shrink-0"/>}
            <div className="flex flex-col gap-1">
                <p className="font-medium">
                    {f"Check your phone ({current['phone']})" if waiting else ""}
                </p>
                <p data-testid="payment-message">{current["message"]}</p>
            </div>
        </div>;

    show_form = current is None or listed(state, RETRYABLE);
    form = show_form
        and <form onSubmit={pay} noValidate={True} className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
                <Label htmlFor="mpesa-phone">M-Pesa number</Label>
                <Input
                    id="mpesa-phone"
                    name="phone"
                    type="tel"
                    inputMode="tel"
                    autoComplete="tel"
                    placeholder="0712 345 678"
                    value={phone}
                    aria-invalid={"true" if len(phone_error) > 0 else "false"}
                    aria-describedby={"mpesa-phone-error"
                        if len(phone_error) > 0
                        else "mpesa-phone-help"}
                    onChange={lambda (e: any) { set_phone(e.target.value); }}  # jac:ignore[W1037]
                    onBlur={lambda (e: any) { checked(e.target.value); }}  # jac:ignore[W1037]
                    className="h-11 max-w-xs text-base"
                />
                {(
                    <p
                        id="mpesa-phone-error"
                        data-testid="phone-error"
                        className="text-sm text-destructive"
                    >
                        {phone_error}
                    </p>
                )
                    if len(phone_error) > 0
                    else <p
                        id="mpesa-phone-help"
                        className="text-sm text-muted-foreground"
                    >
                        You'll get a prompt on this phone to enter your M-Pesa PIN.
                    </p>}
            </div>
            <div className="flex flex-col gap-1.5">
                <Label htmlFor="tickets-email">Email for your tickets</Label>
                <Input
                    id="tickets-email"
                    name="email"
                    type="email"
                    inputMode="email"
                    autoComplete="email"
                    placeholder="name@example.com"
                    value={email}
                    aria-invalid={"true" if len(email_wrong) > 0 else "false"}
                    aria-describedby={"tickets-email-error"
                        if len(email_wrong) > 0
                        else "tickets-email-help"}
                    onChange={lambda (e: any) { set_email(e.target.value); }}  # jac:ignore[W1037]
                    onBlur={lambda (e: any) { set_email_error(  # jac:ignore[W1037]
                        email_problem(e.target.value)
                            if len(e.target.value.strip()) > 0
                            else ""
                    ); }}
                    className="h-11 max-w-xs text-base"
                />
                {(
                    <p
                        id="tickets-email-error"
                        data-testid="email-error"
                        className="text-sm text-destructive"
                    >
                        {email_wrong}
                    </p>
                )
                    if len(email_wrong) > 0
                    else <p
                        id="tickets-email-help"
                        className="text-sm text-muted-foreground"
                    >
                        We'll email your tickets here, with a link to open them again.
                    </p>}
            </div>
            <Button
                type="submit"
                data-testid="pay-mpesa"
                disabled={busy}
                className="min-h-11 w-full sm:w-fit sm:px-6"
            >
                {busy and <Spinner aria-hidden="true"/>}{(
                    "Sending the request…"
                        if busy
                        else (
                            "Try again"
                                if listed(state, RETRYABLE)
                                else f"Pay {amount} with M-Pesa"
                        )
                )}
            </Button>
        </form>;

    return
        <section
            data-testid="pay-panel"
            aria-labelledby="pay-heading"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h3 id="pay-heading" className="text-lg font-semibold">Pay with M-Pesa</h3>
            {status}
            {len(problem) > 0
                and <p
                    role="alert"
                    data-testid="pay-problem"
                    className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm"
                >
                    {problem}
                </p>}
            {form}
        </section>;
}
