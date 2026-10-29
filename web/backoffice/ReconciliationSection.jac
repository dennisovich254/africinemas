"""`/app/:slug/reconciliation`: what doesn't add up (P15.6, ADR-0085).

For staff who read the cinema's financial reports: the exceptions the daily M-Pesa
check, an uploaded M-Pesa statement and the box office's cash-ups found, open ones
first, each marked resolved with a note; uploading the statement (the CSV from
Safaricom's M-Pesa portal) to match it; and the recent cash-ups.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.payments.reconcile_api {
    reconciliation,  # jac:ignore[W2037] authenticated endpoint
    resolve_exception,  # jac:ignore[W2037] authenticated endpoint
    upload_mpesa_statement  # jac:ignore[W2037] authenticated endpoint
}
import from .report_view { money_label }

glob CARD: str = "flex flex-col gap-2 rounded-lg border bg-card p-4";

def _when(iso: str) -> str {
    return iso[:16].replace("T", " ") if iso else "";
}

def:pub ExceptionText(e: dict[str, any]) -> str {  # jac:ignore[W1037]
    # What it's about, in words.
    parts: list[str] = [];
    if e["reference"] {
        parts.append(f"Order {e['reference']}");
    }
    if e["receipt"] {
        parts.append(f"M-Pesa {e['receipt']}");
    }
    if int(e["expected_cents"]) or int(e["found_cents"]) {
        parts.append(
            f"ours {money_label(int(e['expected_cents']), 'KES')}, theirs {money_label(
                int(e['found_cents']), 'KES'
            )}"
        );
    }
    if e["detail"] {
        parts.append(e["detail"]);
    }
    return " · ".join(parts);
}

def Exception(slug: str, e: dict[str, any], on_changed: any) -> JsxElement {  # jac:ignore[W1037]
    [note, set_note] = useState("");
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);
    open: bool = e["status"] == "open";

    async def done {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await resolve_exception(slug, e["exception_id"], note);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("resolve_exception failed", err);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "That didn't work. Try again."
            );
            return;
        }
        on_changed();
    }

    return
        <li className={CARD} data-testid="exception">
            <p className="font-medium">
                {e["label"]}
                <span className="ml-2 text-xs font-normal text-muted-foreground">
                    {("Open" if open else "Resolved") + " · " + _when(e["found_at"])}
                </span>
            </p>
            <p className="text-sm break-words">{ExceptionText(e)}</p>
            {not open
                and <p className="text-sm text-muted-foreground">
                    {f"Resolved by {e['resolved_by']}: {e['resolved_note']}"}
                </p>}
            {open
                and <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
                    <div className="flex flex-1 flex-col gap-1.5">
                        <Label htmlFor={f"resolve-{e['exception_id']}"}>
                            How it was sorted out
                        </Label>
                        <Input
                            id={f"resolve-{e['exception_id']}"}
                            value={note}
                            onChange={lambda (ev: any) { set_note(ev.target.value); }}  # jac:ignore[W1037]
                            className="min-h-11"
                        />
                    </div>
                    <Button
                        className="min-h-11"
                        variant="outline"
                        disabled={busy}
                        onClick={done}
                    >
                        Mark resolved
                    </Button>
                </div>}
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </li>;
}

def StatementUpload(slug: str, on_changed: any) -> JsxElement {  # jac:ignore[W1037]
    [busy, set_busy] = useState(False);
    [said, set_said] = useState("");
    [problem, set_problem] = useState("");

    async def chosen(ev: any) {  # jac:ignore[W1037]
        files: any = ev.target.files;  # jac:ignore[W1037]
        if not files or len(files) == 0 {
            return;
        }
        set_busy(True);
        set_said("");
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            text: str = await files[0].text();
            got = await upload_mpesa_statement(slug, text);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("upload_mpesa_statement failed", err);
        }
        set_busy(False);
        ev.target.value = "";
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't read that file."
            );
            return;
        }
        set_said(
            f"{got['rows']} payments in, {got['matched']} matched; {got[
                'exceptions'
            ]} new exception"
                + ("" if int(got["exceptions"]) == 1 else "s")
                + "."
        );
        on_changed();
    }

    return
        <section className={CARD} data-testid="statement-upload">
            <h2 className="text-lg font-semibold">Check an M-Pesa statement</h2>
            <p className="text-sm text-muted-foreground">
                Download your paybill's statement as CSV from Safaricom's M-Pesa portal and choose it here. We match every payment in it with your orders, by receipt, and list what doesn't match.
            </p>
            <Label htmlFor="statement-file">Statement (CSV)</Label>
            <input
                id="statement-file"
                type="file"
                accept=".csv,text/csv"
                disabled={busy}
                onChange={chosen}
                className="min-h-11 text-sm"
            />
            <p
                role="status"
                aria-live="polite"
                className="text-sm empty:hidden"
                data-testid="statement-result"
            >
                {"Checking…" if busy else said}
            </p>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </section>;
}

def:pub ReconciliationSection(slug: str) -> JsxElement {
    [shown, set_shown] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await reconciliation(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("reconciliation failed", e);
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

    found: dict[str, any] | None = shown;  # jac:ignore[W1037]
    if failed {
        return
            <p role="alert" className="text-sm">
                We couldn't load this. Reload the page to try again.
            </p>;
    }
    if found is None {
        return <Spinner/>;
    }
    rows: list[dict[str, any]] = found["exceptions"];  # jac:ignore[W1037]
    ups: list[dict[str, any]] = found["cash_ups"];  # jac:ignore[W1037]
    # Open ones first.
    ordered: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for r in rows {
        if r["status"] == "open" {
            ordered.append(r);
        }
    }
    for r in rows {
        if r["status"] != "open" {
            ordered.append(r);
        }
    }
    return
        <div className="flex max-w-3xl flex-col gap-6" data-testid="reconciliation">
            <p className="text-sm text-muted-foreground">
                Every day we ask M-Pesa again about your payments, and list here anything that doesn't add up, with what your statements and cash counts turn up.
            </p>
            <section className="flex flex-col gap-3">
                <h2 className="text-lg font-semibold" data-testid="open-exceptions">
                    {f"{found['open']} to look at"
                        if int(found["open"]) > 0
                        else "Nothing to look at"}
                </h2>
                {len(ordered) > 0
                    and <ul className="flex flex-col gap-3">
                        {[
                            <Exception
                                key={r["exception_id"]}
                                slug={slug}
                                e={r}
                                on_changed={load}
                            /> for r in ordered
                        ]}
                    </ul>}
            </section>
            <StatementUpload slug={slug} on_changed={load}/>
            <section className={CARD} data-testid="cash-ups">
                <h2 className="text-lg font-semibold">Cash counts</h2>
                {len(ups) == 0
                    and <p className="text-sm text-muted-foreground">
                        No counts yet: the box office counts its cash on its Box office page.
                    </p>}
                {len(ups) > 0
                    and <ul className="flex flex-col gap-1 text-sm">
                        {[
                            <li key={u["at"] + u["member"]}>
                                {f"{_when(u['at'])} · {u['member']}: counted {money_label(
                                    int(u['counted_cents']), 'KES'
                                )}, recorded {money_label(
                                    int(u['expected_cents']), 'KES'
                                )}"
                                    + (
                                        ""
                                            if int(u["difference_cents"]) == 0
                                            else f" ({money_label(
                                                int(u['difference_cents']), 'KES'
                                            )})"
                                    )}
                            </li> for u in ups
                        ]}
                    </ul>}
            </section>
        </div>;
}
