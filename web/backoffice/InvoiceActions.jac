"""Paying an invoice and querying it, on the cinema's Billing page (P15.5, ADR-0084).

Pay now: the amount is the invoice's, shown in a read-only field (owner, 2026-10-28:
paid in full, never typed); the staff member gives the M-Pesa number the prompt goes
to. The page then asks every few seconds until M-Pesa answers: paid, or why not.

Something wrong with this invoice?: says what, which opens a Help request (category
invoice_dispute) and pauses reminders and any suspension until AfriCinemas decides.
The decision, and its note, show here once made.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from core.billing.billing_api {
    pay_invoice,  # jac:ignore[W2037] authenticated endpoint
    invoice_payment,  # jac:ignore[W2037] authenticated endpoint
    dispute_invoice  # jac:ignore[W2037] authenticated endpoint
}
import from .report_view { money_label }
import from .nav { section_path }
import from ..shell.AppLink { AppLink }

glob POLL_MS: int = 3000,
     OWED: list[str] = ["due", "overdue"];

def _said(state: str, why: str) -> str {
    # What a payment's state means for the person paying.
    if state == "stk_requested" {
        return "Check your phone: enter your M-Pesa PIN to pay.";
    }
    if state == "paid" {
        return "Paid. Thank you.";
    }
    if state == "unmatched" {
        return "We received your payment, but it didn't match this invoice. AfriCinemas will sort it out and tell you.";
    }
    if state == "cancelled" {
        return "The payment was cancelled on the phone. Try again when you're ready.";
    }
    if state == "expired" {
        return "M-Pesa didn't answer in time. Try again.";
    }
    return "The payment didn't go through"
        + (f": {why}" if why else ".")
        + " Try again.";
}

def PayInvoice(slug: str, shown: dict[str, any], on_changed: any) -> JsxElement {  # jac:ignore[W1037]
    [phone, set_phone] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [reference, set_reference] = useState("");
    [state, set_state] = useState("");
    [why, set_why] = useState("");
    number: str = shown["number"];
    field: str = f"pay-phone-{number}";

    async def check {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await invoice_payment(slug, reference);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("invoice_payment failed", e);
            return;
        }
        if got is None or not got["ok"] {
            return;
        }
        set_state(got["payment"]["state"]);
        set_why(got["payment"]["result_text"] or "");
        if got["payment"]["state"] != "stk_requested" {
            on_changed();
        }
    }

    def poll -> any {  # jac:ignore[W1037]
        # Ask again every few seconds while the prompt is on the phone.
        if not reference or state != "stk_requested" {
            return lambda {};
        }
        timer: any = setTimeout(check, POLL_MS);  # jac:ignore[W1037,W2001]
        return lambda { clearTimeout(timer); };  # jac:ignore[W2001]
    }
    useEffect(poll, [reference, state]);

    async def pay(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_busy(True);
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await pay_invoice(slug, number, phone);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("pay_invoice failed", err);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't send the prompt. Try again."
            );
            return;
        }
        set_reference(got["payment"]["reference"]);
        set_state(got["payment"]["state"]);
        set_why(got["payment"]["result_text"] or "");
    }

    waiting: bool = state == "stk_requested";
    if shown["status"] not in OWED {
        # Paid just now on this page: the form goes, its answer stays. Kept mounted
        # (InvoiceActions) so the answer survives the page reloading the invoice.
        return
            <p
                role="status"
                aria-live="polite"
                className="text-sm empty:hidden"
                data-testid="pay-status"
            >
                {_said(state, why) if state == "paid" else ""}
            </p>;
    }
    return
        <form
            className="flex flex-col gap-3 rounded-md border p-3"
            data-testid="pay-invoice"
            onSubmit={pay}
        >
            <div className="grid gap-3 sm:grid-cols-2">
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor={f"pay-amount-{number}"}>Amount</Label>
                    <Input
                        id={f"pay-amount-{number}"}
                        value={money_label(
                            int(shown["payable_cents"]), shown["currency"]
                        )}
                        readOnly={True}
                        aria-readonly="true"
                        className="min-h-11 bg-muted"
                    />
                    <p className="text-xs text-muted-foreground">
                        The invoice is paid in full.
                    </p>
                </div>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor={field}>M-Pesa number</Label>
                    <Input
                        id={field}
                        type="tel"
                        inputMode="tel"
                        autoComplete="tel"
                        placeholder="0712 345 678"
                        value={phone}
                        onChange={lambda (ev: any) { set_phone(ev.target.value); }}  # jac:ignore[W1037]
                        className="min-h-11"
                        required={True}
                    />
                </div>
            </div>
            <div>
                <Button type="submit" className="min-h-11" disabled={busy or waiting}>
                    {"Sending…"
                        if busy
                        else ("Waiting for M-Pesa…" if waiting else "Pay now")}
                </Button>
            </div>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
            <p
                role="status"
                aria-live="polite"
                className="text-sm empty:hidden"
                data-testid="pay-status"
            >
                {_said(state, why) if state else ""}
            </p>
        </form>;
}

def Dispute(slug: str, shown: dict[str, any], on_changed: any) -> JsxElement {  # jac:ignore[W1037]
    [text, set_text] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    number: str = shown["number"];
    kept: dict[str, any] | None = shown["dispute"];  # jac:ignore[W1037]

    async def send(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_busy(True);
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await dispute_invoice(slug, number, text);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("dispute_invoice failed", err);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't send that. Try again."
            );
            return;
        }
        on_changed();
    }

    if kept is not None {
        decided: str = kept["outcome"];
        return
            <div className="rounded-md border p-3 text-sm" data-testid="dispute">
                <p className="font-medium">
                    {"You queried this invoice. AfriCinemas is looking at it: no reminders, and no suspension for it, until then."
                        if kept["open"]
                        else (
                            "AfriCinemas looked at your query: the invoice stands as issued."
                                if decided == "stands"
                                else "AfriCinemas looked at your query: there's nothing to pay on this invoice."
                        )}
                </p>
                <p className="mt-1 text-muted-foreground">
                    {f"You said: {kept['text']}"}
                </p>
                {kept["note"]
                    and <p className="mt-1">{f"AfriCinemas: {kept['note']}"}</p>}
                <AppLink
                    to={section_path(slug, "help") + "/" + kept["request_id"]}
                    className="mt-2 inline-flex min-h-11 items-center underline"
                >
                    See the conversation in Help
                </AppLink>
            </div>;
    }
    if shown["status"] not in OWED {
        return <span className="hidden"/>;
    }
    return
        <details className="rounded-md border p-3 text-sm" data-testid="dispute">
            <summary className="min-h-11 cursor-pointer py-2 font-medium">
                Something wrong with this invoice?
            </summary>
            <form className="flex flex-col gap-3" onSubmit={send}>
                <Label htmlFor={f"dispute-{number}"}>What's wrong with it</Label>
                <textarea
                    id={f"dispute-{number}"}
                    value={text}
                    onChange={lambda (ev: any) { set_text(ev.target.value); }}  # jac:ignore[W1037]
                    rows={3}
                    maxLength={1000}
                    className="w-full rounded-md border border-input bg-background p-2"
                />
                <p className="text-xs text-muted-foreground">
                    We answer in Help. Until then there are no reminders for it, and your cinema isn't suspended over it.
                </p>
                <div>
                    <Button
                        type="submit"
                        variant="outline"
                        className="min-h-11"
                        disabled={busy}
                    >
                        {"Sending…" if busy else "Send to AfriCinemas"}
                    </Button>
                </div>
                <p role="alert" className="text-sm text-destructive empty:hidden">
                    {problem}
                </p>
            </form>
        </details>;
}

def:pub InvoiceActions(
    slug: str,
    shown: dict[str, any],  # jac:ignore[W1037]
    on_changed: any  # jac:ignore[W1037]
) -> JsxElement {
    return
        <div className="flex flex-col gap-3">
            {shown["status"] in ["due", "overdue", "paid"]
                and <PayInvoice slug={slug} shown={shown} on_changed={on_changed}/>}
            <Dispute slug={slug} shown={shown} on_changed={on_changed}/>
        </div>;
}
