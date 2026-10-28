"""Counting the cash at the box office (P15.6, ADR-0085).

The member of staff counts the cash taken since their last cash-up (not the float)
and enters it; what they'd recorded is only shown once they've counted, so the count
is honest. A difference goes to the cinema's Reconciliation page as an exception.
"""

import from react { useState }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from core.payments.reconcile_api { count_cash }  # jac:ignore[W2037] authenticated endpoint
import from .PricesSection { cents_of }
import from .report_view { money_label }

def:pub CashUp(slug: str) -> JsxElement {
    [counted, set_counted] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [result, set_result] = useState(None);

    async def count(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_problem("");
        cents: any = cents_of(counted, False);  # jac:ignore[W1037]
        if cents is None or cents < 0 {
            set_problem("Enter the cash you counted, in shillings.");
            return;
        }
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await count_cash(slug, cents);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("count_cash failed", err);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't save that. Try again."
            );
            return;
        }
        set_result(got["cash_up"]);
        set_counted("");
    }

    shown: dict[str, any] | None = result;  # jac:ignore[W1037]
    off: int = int(shown["difference_cents"]) if shown is not None else 0;
    return
        <section
            className="flex max-w-xl flex-col gap-4 rounded-lg border bg-card p-4"
            data-testid="cash-up"
        >
            <h2 className="text-lg font-semibold">Count your cash</h2>
            <p className="text-sm text-muted-foreground">
                Count the cash you've taken since your last count, not the float, and enter it. We compare it with the cash sales you recorded.
            </p>
            <form className="flex flex-col gap-3" onSubmit={count}>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="cash-counted">Cash counted (KES)</Label>
                    <Input
                        id="cash-counted"
                        inputMode="decimal"
                        value={counted}
                        onChange={lambda (ev: any) { set_counted(ev.target.value); }}  # jac:ignore[W1037]
                        className="min-h-11"
                    />
                </div>
                <div>
                    <Button type="submit" className="min-h-11" disabled={busy}>
                        {"Saving…" if busy else "Save the count"}
                    </Button>
                </div>
                <p role="alert" className="text-sm text-destructive empty:hidden">
                    {problem}
                </p>
            </form>
            {shown is not None
                and <p role="status" className="text-sm" data-testid="cash-up-result">
                    {f"You counted {money_label(
                        int(shown['counted_cents']), 'KES'
                    )}; you recorded {money_label(
                        int(shown['expected_cents']), 'KES'
                    )} in cash. "
                        + (
                            "It matches."
                                if off == 0
                                else (
                                    f"You're {money_label(0 - off, 'KES')} short"
                                        if off < 0
                                        else f"You're {money_label(off, 'KES')} over"
                                )
                                    + ": your manager will see it."
                        )}
                </p>}
        </section>;
}
