"""Counting the cash at the box office (P15.6, P15.6b, ADR-0085).

The member of staff counts the cash taken since their last count (not the float) and
enters it. Counting is how a shift ends:
- **Check it first**: the amount is shown large and in words ("sixteen thousand
  shillings") with Change and Save count, so a slip is caught before it's saved. More
  than the cinema's limit (cash_status's max_cents) is refused.
- **Blind**: what they'd recorded is only shown once they've counted.
- **Ends the shift**: on_shift_ended tells the page, which offers a new one. A count of
  cash left from an earlier shift (count_first) doesn't end the new shift.
- **One correction**: within 10 minutes, "Count again" replaces the count (both
  figures are kept for the manager).
A difference goes to the cinema's Reconciliation page.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from core.payments.reconcile_api {
    count_cash,  # jac:ignore[W2037] authenticated endpoint
    recount_cash,  # jac:ignore[W2037] authenticated endpoint
    cash_status  # jac:ignore[W2037] authenticated endpoint
}
import from .PricesSection { cents_of }
import from .report_view { money_label }
import from .cash_words { shillings_in_words }
import from .form_parts { on_input }

def _kes(cents: any) -> str {  # jac:ignore[W1037]
    return money_label(int(cents), "KES");
}

def:pub CashResult(c: dict[str, any]) -> str {  # jac:ignore[W1037]
    # "You counted KES 1,600; you recorded KES 1,660 in cash. You're KES 60 short: ..."
    off = int(c["counted_cents"]) - int(c["expected_cents"]);
    said = f"You counted {_kes(c['counted_cents'])}; you recorded {_kes(
        c['expected_cents']
    )} in cash. ";
    if off == 0 {
        return said + "It matches.";
    }
    return said
        + (f"You're {_kes(0 - off)} short" if off < 0 else f"You're {_kes(off)} over")
        + ": your manager will see it.";
}

def Confirm(  # jac:ignore[W3030] the dialog: how much, what saving does, the two answers
    cents: int,
    ends: bool,
    busy: bool,
    on_change: any,  # jac:ignore[W1037]
    on_save: any  # jac:ignore[W1037]
) -> JsxElement {
    return
        <div
            className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-4 sm:items-center"
        >
            <div
                role="dialog"
                aria-modal="true"
                aria-labelledby="cash-confirm-title"
                aria-describedby="cash-confirm-words"
                data-testid="cash-confirm"
                className="flex w-full max-w-sm flex-col gap-3 rounded-lg border bg-card p-4 shadow-lg"
            >
                <h2 id="cash-confirm-title" className="text-lg font-semibold">
                    Is this the cash you counted?
                </h2>
                <p
                    className="text-3xl font-semibold tabular-nums"
                    data-testid="cash-confirm-amount"
                >
                    {_kes(cents)}
                </p>
                <p
                    id="cash-confirm-words"
                    className="text-sm text-muted-foreground first-letter:uppercase"
                    data-testid="cash-confirm-words"
                >
                    {shillings_in_words(cents)}
                </p>
                {ends
                    and <p className="text-sm text-muted-foreground">
                        Saving it ends your shift.
                    </p>}
                <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                    <Button
                        variant="outline"
                        className="min-h-11"
                        disabled={busy}
                        onClick={on_change}
                    >
                        Change
                    </Button>
                    <Button className="min-h-11" disabled={busy} onClick={on_save}>
                        {"Saving…" if busy else "Save count"}
                    </Button>
                </div>
            </div>
        </div>;
}

def:pub CashUp(slug: str, on_shift_ended: any = None) -> JsxElement {  # jac:ignore[W1037]
    [counted, set_counted] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [result, set_result] = useState(None);
    [status, set_status] = useState(None);
    [checking, set_checking] = useState(-1);
    [again, set_again] = useState(False);
    [ended, set_ended] = useState(False);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await cash_status(slug);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("cash_status failed", err);
        }
        if got is not None and got["ok"] {
            set_status(got);
        }
    }

    def start {
        load();
    }
    useEffect(start, [slug]);

    seen: dict[str, any] = status or {"max_cents": 0, "count_first": False};  # jac:ignore[W1037]

    def check(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_problem("");
        cents: any = cents_of(counted, False);  # jac:ignore[W1037]
        if cents is None or cents < 0 {
            set_problem("Enter the cash you counted, in shillings.");
            return;
        }
        most = int(seen["max_cents"]);
        if most > 0 and cents > most {
            set_problem(
                f"That's more than {_kes(
                    most
                )}, the most one count can be. Check the amount, or ask your manager to raise the limit."
            );
            return;
        }
        set_checking(cents);
    }

    async def save {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            if again {
                got = await recount_cash(slug, checking);  # jac:ignore[W2037]
            } else {
                got = await count_cash(slug, checking);  # jac:ignore[W2037]
            }
        } except Exception as err {
            console.warn("count_cash failed", err);
        }
        set_busy(False);
        set_checking(-1);
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
        if not again and got["shift_ended"] {
            set_ended(True);
            if on_shift_ended {
                on_shift_ended();
            }
        }
        set_again(False);
        load();
    }

    shown: dict[str, any] | None = result;  # jac:ignore[W1037]
    may_recount: bool = shown is not None
        and not again
        and bool(shown["recount_until"])
        and new(Date, shown["recount_until"]).getTime() > Date.now();  # jac:ignore[W2001]
    asking: bool = shown is None or again;
    return
        <section
            className="flex max-w-xl flex-col gap-4 rounded-lg border bg-card p-4"
            data-testid="cash-up"
        >
            <h2 className="text-lg font-semibold">
                {"Count your cash again"
                    if again
                    else "End your shift: count your cash"}
            </h2>
            {seen["count_first"]
                and <p
                    role="status"
                    className="rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-sm"
                    data-testid="count-first"
                >
                    You didn't count the cash from your last shift. Count it now: you can't sell for cash until you do.
                </p>}
            {asking
                and <p className="text-sm text-muted-foreground">
                    {"Enter what you counted this time. It replaces your first count; your manager sees both."
                        if again
                        else "At the end of your shift, count the cash you've taken since your last count, not the float, and enter it. We compare it with the cash sales you recorded."}
                </p>}
            {asking
                and <form className="flex flex-col gap-3" onSubmit={check}>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="cash-counted">Cash counted (KES)</Label>
                        <Input
                            id="cash-counted"
                            inputMode="decimal"
                            value={counted}
                            onChange={on_input(set_counted)}
                            className="min-h-11"
                        />
                    </div>
                    <div className="flex flex-wrap gap-2">
                        <Button type="submit" className="min-h-11" disabled={busy}>
                            Check the amount
                        </Button>
                        {again
                            and <Button
                                type="button"
                                variant="outline"
                                className="min-h-11"
                                onClick={lambda { set_again(False); }}
                            >
                                Keep my first count
                            </Button>}
                    </div>
                    <p role="alert" className="text-sm text-destructive empty:hidden">
                        {problem}
                    </p>
                </form>}
            {shown is not None
                and not again
                and <div className="flex flex-col gap-2">
                    <p role="status" className="text-sm" data-testid="cash-up-result">
                        {CashResult(shown)}
                    </p>
                    {int(shown["first_counted_cents"]) >= 0
                        and <p className="text-sm text-muted-foreground">
                            {f"Corrected from {_kes(shown['first_counted_cents'])}."}
                        </p>}
                    {ended
                        and <p className="text-sm" data-testid="shift-ended">
                            Your shift has ended. Start a new one to sell again.
                        </p>}
                    {may_recount
                        and <div>
                            <Button
                                variant="outline"
                                className="min-h-11"
                                data-testid="count-again"
                                onClick={lambda {
                                    set_problem("");
                                    set_again(True);
                                }}
                            >
                                Made a mistake? Count again
                            </Button>
                            <p className="mt-1 text-xs text-muted-foreground">
                                You can correct a count once, within 10 minutes.
                            </p>
                        </div>}
                    <p role="alert" className="text-sm text-destructive empty:hidden">
                        {problem}
                    </p>
                </div>}
            {checking >= 0
                and <Confirm
                    cents={checking}
                    ends={not again and not seen["count_first"]}
                    busy={busy}
                    on_change={lambda { set_checking(-1); }}
                    on_save={save}
                />}
        </section>;
}
