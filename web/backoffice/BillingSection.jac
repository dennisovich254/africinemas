"""`/app/:slug/billing`: the cinema's monthly statements and invoices (P15.4, ADR-0083).

Staff who read the cinema's financial reports see each month's statement, newest first:
the invoice's number, when it's due and how to pay it, the amount due, and, opened,
the takings by channel, refunds, AfriCinemas' fees and VAT. Each one downloads as a PDF
with its orders. Each says whether it's due, overdue or paid; one still owed is paid in
full with Pay now, or queried as a dispute (InvoiceActions, P15.5). The console's
Billing page shows the same Statement for every cinema.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.billing.billing_api {
    billing,  # jac:ignore[W2037] authenticated endpoint
    billing_pdf  # jac:ignore[W2037] authenticated endpoint
}
import from .report_view { money_label }
import from .InvoiceActions { InvoiceActions }

glob MONTHS: list[str] = [
         "January",
         "February",
         "March",
         "April",
         "May",
         "June",
         "July",
         "August",
         "September",
         "October",
         "November",
         "December"
     ],
     ROWS: list[tuple[str, str, bool]] = [
         ("online_cents", "Online", False),
         ("counter_mpesa_cents", "Box office, M-Pesa", False),
         ("counter_cash_cents", "Box office, cash", False),
         ("gross_cents", "Gross takings", True),
         ("refunds_cents", "Refunds", False),
         ("net_cents", "Net takings", True),
         ("fees_charged_cents", "AfriCinemas' fees", False),
         ("fees_credited_cents", "Fees credited on refunds", False),
         ("fees_cents", "Fees this month", True),
         ("brought_forward_cents", "Credit brought forward", False),
         ("vat_cents", "VAT", False),
         ("due_cents", "Amount due", True),
         # M-Pesa takes whole shillings (P15.5).
         ("rounding_cents", "Rounded to whole shillings for M-Pesa", False),
         ("payable_cents", "To pay", True),
         ("carried_forward_cents", "Credit carried to next month", False)
     ];

def:pub month_label(month: str) -> str {
    return f"{MONTHS[int(month[5:7]) - 1]} {month[:4]}";
}

def:pub day_label(iso: str) -> str {
    parts = iso.split("-");
    return f"{int(parts[2])} {MONTHS[int(parts[1]) - 1][:3]} {parts[0]}";
}

def:pub status_text(shown: dict[str, any]) -> str {  # jac:ignore[W1037]
    # The invoice's state in words (never a colour alone).
    status: str = shown["status"];
    if status == "paid" {
        return "Paid";
    }
    if status == "nothing_due" {
        return "Nothing to pay";
    }
    if status == "waived" {
        return "Waived";
    }
    if status == "overdue" {
        days: int = int(shown["days_overdue"]);
        return f"Overdue by {days} day" + ("" if days == 1 else "s");
    }
    return "Due";
}

def:pub save_pdf(name: str, pdf: str) {
    # Hands the visitor the PDF, from base64.
    win: any = window;  # jac:ignore[W1037,W2001]
    raw: str = win.atob(pdf);
    bytes: any = new(win.Uint8Array, len(raw));  # jac:ignore[W1037]
    for i in range(len(raw)) {
        bytes[i] = ord(raw[i]);
    }
    blob: any = new(win.Blob, [bytes], {"type": "application/pdf"});  # jac:ignore[W1037]
    url: str = win.URL.createObjectURL(blob);
    link: any = win.document.createElement("a");  # jac:ignore[W1037,W6001]
    link.href = url;
    link.download = name;
    link.click();
    win.URL.revokeObjectURL(url);
}

def:pub Statement(
    shown: dict[str, any],  # jac:ignore[W1037]
    load_pdf: any,  # jac:ignore[W1037]
    cinema: str = "",
    actions: any = None  # jac:ignore[W1037]
) -> JsxElement {
    # One statement: the invoice up top, the figures when opened, and its PDF.
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    f: dict[str, int] = shown["figures"];
    currency: str = shown["currency"];

    async def download {
        set_busy(True);
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await load_pdf(shown["number"]);
        } except Exception as e {
            console.warn("statement PDF failed", e);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem("We couldn't make the PDF. Try again.");
            return;
        }
        save_pdf(got["filename"], got["pdf"]);
    }

    def shows(key: str) -> bool {
        # Credits and VAT only when there are any; the rest always.
        if key in ["brought_forward_cents", "carried_forward_cents", "vat_cents"] {
            return int(f[key]) != 0;
        }
        if key in ["rounding_cents", "payable_cents"] {
            return int(f.get("rounding_cents", 0)) != 0;
        }
        return True;
    }

    return
        <li
            data-testid="statement"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex min-w-0 flex-col gap-0.5">
                    <h2 className="text-base font-semibold">
                        {(cinema + ": " if cinema else "")
                            + month_label(shown["month"])}
                    </h2>
                    <p className="text-sm text-muted-foreground">
                        {f"Invoice {shown['number']} · issued {day_label(
                            shown['issued_on']
                        )} · due {day_label(shown['due_on'])}"}
                    </p>
                </div>
                <p className="text-right">
                    <span
                        className={"block text-xs font-medium"
                            + (
                                " text-destructive"
                                    if shown["status"] == "overdue"
                                    else " text-muted-foreground"
                            )}
                        data-testid="statement-status"
                    >
                        {status_text(shown)}
                    </span>
                    <span className="block text-xs text-muted-foreground">
                        Amount due
                    </span>
                    <span
                        className="text-lg font-semibold tabular-nums"
                        data-testid="statement-due"
                    >
                        {money_label(int(f["due_cents"]), currency)}
                    </span>
                </p>
            </div>
            {shown["status"] in ["due", "overdue"]
                and <p className="text-sm" data-testid="statement-pay">
                    {f"Pay {money_label(
                        int(shown['payable_cents']), currency
                    )} by M-Pesa to Paybill {shown['paybill']}, account number {shown[
                        'number'
                    ]}."}{shown["paybill_is_placeholder"]
                        and " AfriCinemas' paybill isn't live yet, so payments here are tests."}
                </p>}
            {shown["status"] == "paid"
                and <p className="text-sm" data-testid="statement-paid">
                    {f"Paid on {day_label(shown['paid_at'][:10])}"
                        + (
                            f", M-Pesa {shown['paid_receipt']}."
                                if shown["paid_receipt"]
                                else "."
                        )}
                </p>}
            <details className="text-sm">
                <summary className="min-h-11 cursor-pointer py-2 font-medium">
                    {f"The figures ({f['bookings']} booking"
                        + ("" if int(f["bookings"]) == 1 else "s")
                        + ")"}
                </summary>
                <dl className="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1">
                    {[
                        <div key={key} className="contents">
                            <dt className={"font-medium" if strong else ""}>
                                {f"VAT at {shown['vat_bp'] // 100}%"
                                    if key == "vat_cents"
                                    else label}
                            </dt>
                            <dd
                                className={"text-right tabular-nums"
                                    + (" font-medium" if strong else "")}
                            >
                                {money_label(
                                    0 - int(f[key])
                                        if key
                                            in ["refunds_cents", "fees_credited_cents"]
                                        else int(f[key]),
                                    currency
                                )}
                            </dd>
                        </div>
                        for (key, label, strong) in ROWS
                        if shows(key)
                    ]}
                </dl>
                {int(shown["vat_bp"]) == 0
                    and <p className="mt-2 text-muted-foreground">
                        No VAT: AfriCinemas isn't registered for VAT yet.
                    </p>}
            </details>
            {actions}
            <div className="flex flex-wrap items-center gap-3">
                <Button
                    variant="outline"
                    className="min-h-11"
                    disabled={busy}
                    onClick={download}
                >
                    {"Making the PDF…" if busy else "Download PDF"}
                </Button>
                <p role="alert" className="text-sm text-destructive empty:hidden">
                    {problem}
                </p>
            </div>
        </li>;
}

def:pub BillingSection(slug: str) -> JsxElement {
    [shown, set_shown] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await billing(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("billing failed", e);
        }
        if got is None or not got["ok"] {
            set_failed(True);
            return;
        }
        set_shown(got);
    }

    def start {
        load();
    }
    useEffect(start, [slug]);

    async def pdf_of(number: str) -> any {  # jac:ignore[W1037]
        return await billing_pdf(slug, number);  # jac:ignore[W2037]
    }

    found: dict[str, any] | None = shown;  # jac:ignore[W1037]
    if failed {
        return
            <p role="alert" className="text-sm">
                We couldn't load your statements. Reload the page to try again.
            </p>;
    }
    if found is None {
        return <Spinner/>;
    }
    statements: list[dict[str, any]] = found["statements"];  # jac:ignore[W1037]
    return
        <div className="flex max-w-3xl flex-col gap-4" data-testid="billing">
            <p className="text-sm text-muted-foreground">
                {f"On the 1st of each month you get a statement for the month before, with an invoice for AfriCinemas' fees. Pay it within {found[
                    'due_days'
                ]} days."}
            </p>
            {len(statements) == 0
                and <p
                    className="rounded-lg border bg-card p-4 text-sm"
                    data-testid="no-statements"
                >
                    No statements yet. Your first comes on the 1st of the month after your first sale.
                </p>}
            {len(statements) > 0
                and <ul className="flex flex-col gap-4">
                    {[
                        <Statement
                            key={s["number"]}
                            shown={s}
                            load_pdf={pdf_of}
                            actions={<InvoiceActions
                                slug={slug}
                                shown={s}
                                on_changed={load}
                            />}
                        /> for s in statements
                    ]}
                </ul>}
        </div>;
}
