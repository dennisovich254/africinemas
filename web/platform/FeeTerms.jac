"""A cinema's fee terms, on its page in the platform console (P15.2, ADR-0080).

The rates in force for the cinema, and whether they're the standard or agreed with it;
its own versions with the day each applies from, who set it and the note (what was
agreed and when). A super admin (`may_change`) sets agreed rates from a day, or returns
the cinema to the standard from a day (core/legal/fee_rule.jac). Agreed rates belong in
the cinema's agreement too.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.legal.fee_rule {
    cinema_fee_terms,  # jac:ignore[W2037] authenticated endpoint
    set_cinema_fee_terms  # jac:ignore[W2037] authenticated endpoint
}
import from .FeesPage { percent_label, RateField }

def _rates(v: dict[str, any]) -> str {  # jac:ignore[W1037]
    return f"{percent_label(v['online_ticket_bp'])} tickets and {percent_label(
        v['online_snack_bp']
    )} snacks online; {percent_label(v['counter_bp'])} at the box office";
}

def:pub FeeTerms(slug: str, may_change: bool = False) -> JsxElement {
    [terms, set_terms] = useState(None);
    [ticket, set_ticket] = useState("");
    [snack, set_snack] = useState("");
    [counter, set_counter] = useState("");
    [day, set_day] = useState("");
    [note, set_note] = useState("");
    [busy, set_busy] = useState(False);
    [message, set_message] = useState("");

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await cinema_fee_terms(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("cinema_fee_terms failed", e);
        }
        if got is not None and got["ok"] {
            set_terms(got);
        }
    }

    def start {
        load();
    }
    useEffect(start, [slug]);

    async def save(standard: bool) {
        set_busy(True);
        set_message("");
        win: any = window;  # jac:ignore[W1037,W2001]
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await set_cinema_fee_terms(  # jac:ignore[W2037]
                slug,
                standard,
                0 if standard else win.Number(ticket or "x"),
                0 if standard else win.Number(snack or "x"),
                0 if standard else win.Number(counter or "x"),
                day,
                note
            );
        } except Exception as e {
            console.warn("set_cinema_fee_terms failed", e);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_message(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't save that. Try again."
            );
            return;
        }
        set_message(
            f"From {got['rule'][
                'applies_from'
            ]}, this cinema is back on the standard rates."
                if standard
                else f"From {got['rule']['applies_from']}: {_rates(
                    got['rule']
                )}. Put these rates in its agreement too."
        );
        load();
    }

    shown: dict[str, any] | None = terms;  # jac:ignore[W1037]
    if shown is None {
        return <Spinner aria-label="Loading the fee terms"/>;
    }
    current: dict[str, any] = shown["current"];  # jac:ignore[W1037]
    versions: list[dict[str, any]] = shown["versions"];  # jac:ignore[W1037]
    return
        <section
            data-testid="fee-terms"
            aria-label="Fee terms"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h2 className="text-lg font-semibold">Fees</h2>
            <p data-testid="fee-terms-current" className="text-sm">
                {(
                    "Agreed with this cinema: "
                        if current["scope"] == "cinema"
                        else "Standard rates: "
                )
                    + _rates(current)
                    + "."}
            </p>
            {len(versions) > 0
                and <ul className="flex flex-col gap-1 text-sm text-muted-foreground">
                    {[
                        <li key={f"{v['version']}"}>
                            {(
                                f"From {v['applies_from']}: back to the standard"
                                    if v["standard"]
                                    else f"From {v['applies_from']}: {_rates(v)}"
                            )
                                + (f". {v['note']}" if v["note"] else "")
                                + (f" Set by {v['set_by']}." if v["set_by"] else "")}
                        </li> for v in versions
                    ]}
                </ul>}
            {may_change
                and <div className="flex flex-col gap-3 border-t pt-3">
                    <div className="grid gap-3 sm:grid-cols-2">
                        <RateField
                            field_id="terms-ticket"
                            label="Online tickets, glasses, booking fee (%)"
                            value={ticket}
                            on_value={set_ticket}
                        />
                        <RateField
                            field_id="terms-snack"
                            label="Online snacks (%)"
                            value={snack}
                            on_value={set_snack}
                        />
                        <RateField
                            field_id="terms-counter"
                            label="Box office (%)"
                            value={counter}
                            on_value={set_counter}
                        />
                        <RateField
                            field_id="terms-from"
                            label="Applies from"
                            value={day}
                            on_value={set_day}
                            kind="date"
                        />
                    </div>
                    <RateField
                        field_id="terms-note"
                        label="What was agreed, and when"
                        value={note}
                        on_value={set_note}
                    />
                    <div className="flex flex-wrap gap-2">
                        <Button
                            disabled={busy}
                            className="min-h-11"
                            onClick={lambda { save(False); }}
                        >
                            Set agreed rates
                        </Button>
                        <Button
                            variant="outline"
                            disabled={busy}
                            className="min-h-11"
                            onClick={lambda { save(True); }}
                        >
                            Back to the standard
                        </Button>
                    </div>
                    <p
                        role="status"
                        aria-live="polite"
                        className="text-sm empty:hidden"
                    >
                        {message}
                    </p>
                </div>}
        </section>;
}
