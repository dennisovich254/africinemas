"""What platform staff act on in the console's Billing page (P15.5, ADR-0084).

- Payments to match: paid but not matched to an invoice (already paid, waived, another
  amount, a receipt used before). A super admin matches one to an invoice of the same
  cinema still owed, for its full amount, or records how it was refunded.
- Disputes: a cinema's query about an invoice. A super admin decides it stands or is
  waived, with a note the cinema sees; reminders and suspension wait until then.
- Suspending: an invoice more than the grace period overdue and not disputed lets staff
  with platform.suspend suspend the cinema, with a reason its team sees; Reinstate
  undoes it. Never automatic.
"""

import from react { useState }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from core.billing.billing_api {
    platform_resolve_payment,  # jac:ignore[W2037] authenticated endpoint
    platform_decide_dispute,  # jac:ignore[W2037] authenticated endpoint
    platform_suspend_cinema,  # jac:ignore[W2037] authenticated endpoint
    platform_reinstate_cinema  # jac:ignore[W2037] authenticated endpoint
}
import from ..backoffice.report_view { money_label }

glob REASONS: dict[str, str] = {
         "already_settled": "The invoice was already paid or waived",
         "amount_differs": "Not the invoice's amount",
         "receipt_used": "A receipt used before",
         "no_invoice": "No such invoice"
     },
     CARD: str = "flex flex-col gap-3 rounded-lg border bg-card p-4";

def _problem_of(got: any) -> str {  # jac:ignore[W1037]
    if got is None {
        return "That didn't work. Try again.";
    }
    return "" if got["ok"] else got["error"]["message"];
}

def ToMatch(row: dict[str, any], may_act: bool, on_changed: any) -> JsxElement {  # jac:ignore[W1037]
    [number, set_number] = useState("");
    [note, set_note] = useState("");
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);
    reference: str = row["reference"];

    async def act(action: str) {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await platform_resolve_payment(  # jac:ignore[W2037]
                row["slug"], reference, action, number, note
            );
        } except Exception as e {
            console.warn("platform_resolve_payment failed", e);
        }
        set_busy(False);
        said = _problem_of(got);
        set_problem(said);
        if not said {
            on_changed();
        }
    }

    return
        <li className={CARD} data-testid="to-match">
            <p className="font-medium">
                {f"{row['cinema_name']}: {money_label(
                    int(row['paid_cents']), 'KES'
                )} for {row['number']}"}
            </p>
            <p className="text-sm text-muted-foreground">
                {f"M-Pesa {row['receipt']} · {REASONS.get(
                    row['unmatched_reason'], row['unmatched_reason']
                )}"}
            </p>
            {may_act
                and <div className="grid gap-3 sm:grid-cols-2">
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor={f"match-{reference}"}>Invoice number</Label>
                        <Input
                            id={f"match-{reference}"}
                            value={number}
                            onChange={lambda (e: any) { set_number(e.target.value); }}  # jac:ignore[W1037]
                            className="min-h-11"
                        />
                        <Button
                            className="min-h-11"
                            disabled={busy}
                            onClick={lambda { act("match"); }}
                        >
                            Match to it
                        </Button>
                    </div>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor={f"refund-{reference}"}>
                            How it was refunded
                        </Label>
                        <Input
                            id={f"refund-{reference}"}
                            value={note}
                            onChange={lambda (e: any) { set_note(e.target.value); }}  # jac:ignore[W1037]
                            className="min-h-11"
                        />
                        <Button
                            variant="outline"
                            className="min-h-11"
                            disabled={busy}
                            onClick={lambda { act("refund"); }}
                        >
                            Record the refund
                        </Button>
                    </div>
                </div>}
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </li>;
}

def Disputed(row: dict[str, any], may_act: bool, on_changed: any) -> JsxElement {  # jac:ignore[W1037]
    [note, set_note] = useState("");
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);
    number: str = row["number"];

    async def decide(outcome: str) {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await platform_decide_dispute(number, outcome, note);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_decide_dispute failed", e);
        }
        set_busy(False);
        said = _problem_of(got);
        set_problem(said);
        if not said {
            on_changed();
        }
    }

    return
        <li className={CARD} data-testid="disputed">
            <p className="font-medium">
                {f"{row['cinema_name']}: invoice {number}, {money_label(
                    int(row['payable_cents']), 'KES'
                )}"}
            </p>
            <p className="text-sm">{f"They said: {row['dispute']['text']}"}</p>
            {may_act
                and <div className="flex flex-col gap-2">
                    <Label htmlFor={f"decide-{number}"}>
                        Your answer (they see it)
                    </Label>
                    <Input
                        id={f"decide-{number}"}
                        value={note}
                        onChange={lambda (e: any) { set_note(e.target.value); }}  # jac:ignore[W1037]
                        className="min-h-11"
                    />
                    <div className="flex flex-wrap gap-2">
                        <Button
                            className="min-h-11"
                            disabled={busy}
                            onClick={lambda { decide("stands"); }}
                        >
                            It stands
                        </Button>
                        <Button
                            variant="outline"
                            className="min-h-11"
                            disabled={busy}
                            onClick={lambda { decide("waived"); }}
                        >
                            Waive it
                        </Button>
                    </div>
                </div>}
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </li>;
}

def Overdue(row: dict[str, any], may_suspend: bool, on_changed: any) -> JsxElement {  # jac:ignore[W1037]
    [reason, set_reason] = useState("");
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);
    slug: str = row["slug"];
    suspended: bool = row["cinema_state"] == "suspended";

    async def change {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            if suspended {
                got = await platform_reinstate_cinema(slug);  # jac:ignore[W2037]
            } else {
                got = await platform_suspend_cinema(slug, reason);  # jac:ignore[W2037]
            }
        } except Exception as e {
            console.warn("suspension change failed", e);
        }
        set_busy(False);
        said = _problem_of(got);
        set_problem(said);
        if not said {
            on_changed();
        }
    }

    return
        <li className={CARD} data-testid="overdue">
            <p className="font-medium">
                {f"{row['cinema_name']}: invoice {row['number']}, {row[
                    'days_overdue'
                ]} days overdue"
                    + (" · suspended" if suspended else "")}
            </p>
            {may_suspend
                and not suspended
                and <div className="flex flex-col gap-2">
                    <Label htmlFor={f"suspend-{slug}-{row['number']}"}>
                        Why (the cinema's team sees it)
                    </Label>
                    <Input
                        id={f"suspend-{slug}-{row['number']}"}
                        value={reason}
                        onChange={lambda (e: any) { set_reason(e.target.value); }}  # jac:ignore[W1037]
                        className="min-h-11"
                    />
                </div>}
            {may_suspend
                and <div>
                    <Button
                        variant={"outline" if suspended else "destructive"}
                        className="min-h-11"
                        disabled={busy}
                        onClick={change}
                    >
                        {"Reinstate the cinema" if suspended else "Suspend the cinema"}
                    </Button>
                </div>}
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </li>;
}

def:pub BillingDesk(
    found: dict[str, any],  # jac:ignore[W1037]
    may_act: bool,
    may_suspend: bool,
    on_changed: any  # jac:ignore[W1037]
) -> JsxElement {
    rows: list[dict[str, any]] = found["statements"];  # jac:ignore[W1037]
    unmatched: list[dict[str, any]] = found["unmatched"];  # jac:ignore[W1037]
    disputes = [
        r
        for r in rows
        if r["dispute"] is not None and r["dispute"]["open"]
    ];
    # Past the grace period, or suspended with an invoice still owed.
    late = [
        r
        for r in rows
        if r["suspendable"]
            or (r["cinema_state"] == "suspended" and r["status"] == "overdue")
    ];
    return
        <div className="flex flex-col gap-6" data-testid="billing-desk">
            {len(unmatched) > 0
                and <section className="flex flex-col gap-3">
                    <h2 className="text-lg font-semibold">Payments to match</h2>
                    <ul className="flex flex-col gap-3">
                        {[
                            <ToMatch
                                key={r["reference"]}
                                row={r}
                                may_act={may_act}
                                on_changed={on_changed}
                            /> for r in unmatched
                        ]}
                    </ul>
                </section>}{len(disputes) > 0
                and <section className="flex flex-col gap-3">
                    <h2 className="text-lg font-semibold">Disputed invoices</h2>
                    <ul className="flex flex-col gap-3">
                        {[
                            <Disputed
                                key={r["number"]}
                                row={r}
                                may_act={may_act}
                                on_changed={on_changed}
                            /> for r in disputes
                        ]}
                    </ul>
                </section>}{len(late) > 0
                and <section className="flex flex-col gap-3">
                    <h2 className="text-lg font-semibold">
                        {f"More than {found['grace_days']} days overdue"}
                    </h2>
                    <ul className="flex flex-col gap-3">
                        {[
                            <Overdue
                                key={r["number"]}
                                row={r}
                                may_suspend={may_suspend}
                                on_changed={on_changed}
                            /> for r in late
                        ]}
                    </ul>
                </section>}
        </div>;
}
