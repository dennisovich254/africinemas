"""Counting the cash at the box office (P15.6, P15.6b, ADR-0085, ADR-0086).

The member of staff counts the cash taken since their last count (not the float) and
enters it, whenever they need to (a handover, a cash drop) and always before signing
out: Sign out sends them here (`sign_out_after`) when they have cash to count.
- **Check it first**: the amount is shown large and in words ("sixteen thousand
  shillings") with Change and Save count, so a slip is caught before it's saved. More
  than the cinema's limit (cash_status's max_cents) is refused.
- **Blind**: what they'd recorded is only shown once they've counted.
- **One correction**: within 10 minutes, "Count again" replaces the count (both
  figures are kept for the manager).
- **Cash someone left**: a member who didn't sign out left cash uncounted at this
  venue. The next here counts it on their behalf (LeftCash): offered while that member
  is still signed in, required (before a cash sale) once their shift is over.
A difference goes to the cinema's Reconciliation page.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useNavigate }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from core.payments.reconcile_api {
    count_cash,  # jac:ignore[W2037] authenticated endpoint
    count_left_cash,  # jac:ignore[W2037] authenticated endpoint
    recount_cash,  # jac:ignore[W2037] authenticated endpoint
    cash_status  # jac:ignore[W2037] authenticated endpoint
}
import from ..auth.session { sign_out }
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

def LeftResult(c: dict[str, any]) -> str {  # jac:ignore[W1037]
    # The same, for cash counted on someone else's behalf.
    off = int(c["counted_cents"]) - int(c["expected_cents"]);
    said = f"You counted {_kes(c['counted_cents'])}; {c['member']} recorded {_kes(
        c['expected_cents']
    )} in cash. ";
    if off == 0 {
        return said + "It matches.";
    }
    return said
        + (f"It's {_kes(0 - off)} short" if off < 0 else f"It's {_kes(off)} over")
        + ": your manager will see it.";
}

def Confirm(  # jac:ignore[W3030] the dialog: how much, what saving does, the two answers
    cents: int,
    note: str,
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
                {note and <p className="text-sm text-muted-foreground">{note}</p>}
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

def CountForm(  # jac:ignore[W3030] the field: its id, the limit, the note, what saving does
    field: str,
    most: int,
    note: str,
    save: any,  # jac:ignore[W1037] async (cents) -> the endpoint's answer
    on_saved: any  # jac:ignore[W1037]
) -> JsxElement {
    # An amount, checked in the dialog, then saved: on_saved(answer) when it worked.
    [counted, set_counted] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [checking, set_checking] = useState(-1);

    def check(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_problem("");
        cents: any = cents_of(counted, False);  # jac:ignore[W1037]
        if cents is None or cents < 0 {
            set_problem("Enter the cash you counted, in shillings.");
            return;
        }
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

    async def confirmed {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await save(checking);
        } except Exception as err {
            console.warn("saving the count failed", err);
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
        set_counted("");
        on_saved(got);
    }

    return
        <form className="flex flex-col gap-3" onSubmit={check}>
            <div className="flex flex-col gap-1.5">
                <Label htmlFor={field}>Cash counted (KES)</Label>
                <Input
                    id={field}
                    inputMode="decimal"
                    value={counted}
                    onChange={on_input(set_counted)}
                    className="min-h-11"
                />
            </div>
            <div>
                <Button type="submit" className="min-h-11" disabled={busy}>
                    Check the amount
                </Button>
            </div>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
            {checking >= 0
                and <Confirm
                    cents={checking}
                    note={note}
                    busy={busy}
                    on_change={lambda { set_checking(-1); }}
                    on_save={confirmed}
                />}
        </form>;
}

def LeftCash(  # jac:ignore[W3030] whose cash, where, the limit, what then
    slug: str,
    left: dict[str, any],  # jac:ignore[W1037]
    most: int,
    on_done: any  # jac:ignore[W1037]
) -> JsxElement {
    # Counting the cash someone left at this venue without counting it.
    [result, set_result] = useState(None);
    async def save(cents: int) -> any {  # jac:ignore[W1037]
        return await count_left_cash(slug, left["member_id"], cents);  # jac:ignore[W2037]
    }
    def saved(got: any) {  # jac:ignore[W1037]
        set_result(got["cash_up"]);
    }
    shown: dict[str, any] | None = result;  # jac:ignore[W1037]
    return
        <section
            className="flex max-w-xl flex-col gap-3 rounded-lg border border-amber-500/40 bg-amber-500/10 p-4"
            data-testid="left-cash"
        >
            <h2 className="text-lg font-semibold">
                {f"{left['member']} didn't count their cash"}
            </h2>
            {shown is None
                and <p className="text-sm">
                    {"They're still signed in. If they've left, count the cash they left here: it's recorded as theirs, counted by you, and their shift ends."
                        if left["on_shift"]
                        else "They left without counting it. Count the cash they left here before you sell for cash: it's recorded as theirs, counted by you."}
                </p>}
            {shown is None
                and <CountForm
                    field={f"left-{left['member_id']}"}
                    most={most}
                    note={f"You're counting {left['member']}'s cash."}
                    save={save}
                    on_saved={saved}
                />}
            {shown is not None
                and <div className="flex flex-col gap-2">
                    <p role="status" className="text-sm" data-testid="left-cash-result">
                        {LeftResult(shown)}
                    </p>
                    <div>
                        <Button
                            variant="outline"
                            className="min-h-11"
                            onClick={on_done}
                        >
                            Done
                        </Button>
                    </div>
                </div>}
        </section>;
}

def:pub CashUp(slug: str, sign_out_after: bool = False) -> JsxElement {
    nav = useNavigate();
    [result, set_result] = useState(None);
    [status, set_status] = useState(None);
    [again, set_again] = useState(False);
    [leaving, set_leaving] = useState(False);

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

    async def save(cents: int) -> any {  # jac:ignore[W1037]
        if again {
            return await recount_cash(slug, cents);  # jac:ignore[W2037]
        }
        return await count_cash(slug, cents);  # jac:ignore[W2037]
    }

    def saved(got: any) {  # jac:ignore[W1037]
        set_result(got["cash_up"]);
        set_again(False);
        load();
    }

    async def leave {
        set_leaving(True);
        await sign_out([slug]);
        nav("/login", {"replace": True});
    }

    blank: dict[str, any] = {"max_cents": 0, "count_first": False, "left_behind": []};  # jac:ignore[W1037]
    seen: dict[str, any] = status or blank;  # jac:ignore[W1037]
    most: int = int(seen["max_cents"]);
    lefts: list[dict[str, any]] = seen["left_behind"];  # jac:ignore[W1037]
    shown: dict[str, any] | None = result;  # jac:ignore[W1037]
    may_recount: bool = shown is not None
        and not again
        and bool(shown["recount_until"])
        and new(Date, shown["recount_until"]).getTime() > Date.now();  # jac:ignore[W2001]
    asking: bool = shown is None or again;
    heading = "Count your cash again"
        if again
        else ("Count your cash to sign out" if sign_out_after else "Count your cash");
    return
        <div className="flex flex-col gap-4">
            {[
                <LeftCash
                    key={l["member_id"]}
                    slug={slug}
                    left={l}
                    most={most}
                    on_done={load}
                /> for l in lefts
            ]}
            <section
                className="flex max-w-xl flex-col gap-4 rounded-lg border bg-card p-4"
                data-testid="cash-up"
            >
                <h2 className="text-lg font-semibold">{heading}</h2>
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
                            else "Count the cash you've taken since your last count, not the float, and enter it. We compare it with the cash sales you recorded. You count before you sign out, and whenever you hand over."}
                    </p>}
                {asking
                    and <CountForm
                        field="cash-counted"
                        most={most}
                        note={"Once it's saved, you can sign out."
                            if sign_out_after and not again
                            else ""}
                        save={save}
                        on_saved={saved}
                    />}
                {again
                    and <div>
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11"
                            onClick={lambda { set_again(False); }}
                        >
                            Keep my first count
                        </Button>
                    </div>}
                {shown is not None
                    and not again
                    and <div className="flex flex-col gap-2">
                        <p
                            role="status"
                            className="text-sm"
                            data-testid="cash-up-result"
                        >
                            {CashResult(shown)}
                        </p>
                        {int(shown["first_counted_cents"]) >= 0
                            and <p className="text-sm text-muted-foreground">
                                {f"Corrected from {_kes(
                                    shown['first_counted_cents']
                                )}."}
                            </p>}
                        {may_recount
                            and <div>
                                <Button
                                    variant="outline"
                                    className="min-h-11"
                                    data-testid="count-again"
                                    onClick={lambda { set_again(True); }}
                                >
                                    Made a mistake? Count again
                                </Button>
                                <p className="mt-1 text-xs text-muted-foreground">
                                    You can correct a count once, within 10 minutes.
                                </p>
                            </div>}
                        {sign_out_after
                            and <div>
                                <Button
                                    className="min-h-11"
                                    data-testid="cash-sign-out"
                                    disabled={leaving}
                                    onClick={leave}
                                >
                                    {"Signing out…" if leaving else "Sign out now"}
                                </Button>
                            </div>}
                    </div>}
            </section>
        </div>;
}
