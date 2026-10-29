"""`/app/:slug/reconciliation`: what doesn't add up (P15.6, ADR-0085).

For staff who read the cinema's financial reports, in three tabs:
- **M-Pesa**: what the daily M-Pesa check found, still open;
- **Cash**: the box office's cash counts that didn't match, still open, and the recent
  counts;
- **Resolved**: everything marked resolved, with its note.
Each open one is marked resolved with a note. Times are the cinema's (its time zone),
whatever the device is set to. `use_open_exceptions` is the sidebar's count.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.payments.reconcile_api {
    reconciliation,  # jac:ignore[W2037] authenticated endpoint
    reconciliation_open,  # jac:ignore[W2037] authenticated endpoint
    resolve_exception  # jac:ignore[W2037] authenticated endpoint
}
import from ..storefront.showtimes { day_time_label }
import from ..support.live { use_every, LIST_MS }
import from .report_view { money_label }
import from ..shell.Tabs { Tabs }

glob CARD: str = "flex flex-col gap-2 rounded-lg border bg-card p-4",
     # Tells the sidebar's count to look again (after one is resolved).
     CHANGED: str = "africinemas:reconciliation-changed",
     TABS: list[tuple[str, str]] = [
         ("mpesa", "M-Pesa"),
         ("cash", "Cash"),
         ("resolved", "Resolved")
     ];

def _kes(cents: any) -> str {  # jac:ignore[W1037]
    return money_label(int(cents), "KES");
}

def:pub ExceptionText(e: dict[str, any]) -> str {  # jac:ignore[W1037]
    # What it's about, in words: the sale and M-Pesa's answer, or the cash recorded and
    # counted.
    parts: list[str] = [];
    if e["reference"] {
        parts.append(f"Order {e['reference']}");
    }
    if e["receipt"] {
        parts.append(f"M-Pesa receipt {e['receipt']}");
    }
    expected = int(e["expected_cents"]);
    found = int(e["found_cents"]);
    if e["kind"] == "cash_not_counted" {
        parts.append(f"Cash sales recorded: {_kes(expected)}");
        parts.append("Not counted when the shift ended");
    } elif e["source"] == "cash_up" {
        parts.append(f"Cash sales recorded: {_kes(expected)}");
        parts.append(f"Cash counted: {_kes(found)}");
        gap = found - expected;
        parts.append(f"{_kes(-gap)} short" if gap < 0 else f"{_kes(gap)} over");
    } elif expected or found {
        parts.append(f"Sold for {_kes(expected)}" if expected else "Nothing sold");
        parts.append(
            f"M-Pesa received {_kes(found)}" if found else "M-Pesa received nothing"
        );
    }
    if e["detail"] {
        parts.append(e["detail"]);
    }
    return " · ".join(parts);
}

def:pub use_open_exceptions(slug: str, enabled: bool) -> int {
    # How many are open, for the sidebar's Reconciliation link.
    [count, set_count] = useState(0);
    async def load {
        if not enabled {
            set_count(0);
            return;
        }
        try {
            answer: any = await reconciliation_open(slug);  # jac:ignore[W1037,W2037]
            if answer["ok"] {
                set_count(int(answer["open"]));
            }
        } except Exception as e {
            console.warn("reconciliation_open failed", e);
        }
    }
    def first -> any {  # jac:ignore[W1037]
        load();
        window.addEventListener(CHANGED, load);
        return lambda { window.removeEventListener(CHANGED, load); };
    }
    useEffect(first, [slug, enabled]);
    use_every(LIST_MS, load, [slug, enabled]);
    return count;
}

def Exception(slug: str, e: dict[str, any], tz: str, on_changed: any) -> JsxElement {  # jac:ignore[W1037]
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
        window.dispatchEvent(new(Event, CHANGED));  # jac:ignore[W2001]
        on_changed();
    }

    return
        <li className={CARD} data-testid="exception">
            <p className="font-medium">
                {e["label"]}
                <span className="ml-2 text-xs font-normal text-muted-foreground">
                    {("Open" if open else "Resolved")
                        + " · "
                        + day_time_label(e["found_at"], tz)}
                </span>
            </p>
            <p className="text-sm break-words">{ExceptionText(e)}</p>
            {not open
                and <p className="text-sm text-muted-foreground">
                    {f"Resolved by {e['resolved_by']}, {day_time_label(
                        e['resolved_at'], tz
                    )}: {e['resolved_note']}"}
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

def Exceptions(  # jac:ignore[W3030] the list: whose, which, in what time zone, what then
    slug: str,
    rows: list[dict[str, any]],  # jac:ignore[W1037]
    tz: str,
    empty: str,
    on_changed: any  # jac:ignore[W1037]
) -> JsxElement {
    if len(rows) == 0 {
        return
            <p
                className={CARD + " text-sm text-muted-foreground"}
                data-testid="nothing-here"
            >
                {empty}
            </p>;
    }
    return
        <ul className="flex flex-col gap-3">
            {[
                <Exception
                    key={r["exception_id"]}
                    slug={slug}
                    e={r}
                    tz={tz}
                    on_changed={on_changed}
                /> for r in rows
            ]}
        </ul>;
}

def CashUps(ups: list[dict[str, any]], tz: str) -> JsxElement {  # jac:ignore[W1037]
    return
        <section className={CARD} data-testid="cash-ups">
            <h2 className="text-lg font-semibold">Recent cash counts</h2>
            {len(ups) == 0
                and <p className="text-sm text-muted-foreground">
                    No counts yet: the box office counts its cash on its Box office page.
                </p>}
            {len(ups) > 0
                and <ul className="flex flex-col gap-1 text-sm">
                    {[
                        <li key={u["at"] + u["member"]}>
                            {f"{day_time_label(u['at'], tz)} · {u['member']}: counted {_kes(
                                u['counted_cents']
                            )}, recorded {_kes(u['expected_cents'])}"
                                + (
                                    ""
                                        if int(u["difference_cents"]) == 0
                                        else f" ({_kes(u['difference_cents'])})"
                                )
                                + (
                                    f"; first counted {_kes(u['first_counted_cents'])}"
                                        if int(u["first_counted_cents"]) >= 0
                                        else ""
                                )}
                        </li> for u in ups
                    ]}
                </ul>}
        </section>;
}

def:pub ReconciliationSection(slug: str) -> JsxElement {
    [shown, set_shown] = useState(None);
    [failed, set_failed] = useState(False);
    [tab, set_tab] = useState("mpesa");

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
    tz: str = found["timezone"];
    lists: dict[str, list[dict[str, any]]] = {"mpesa": [], "cash": [], "resolved": []};  # jac:ignore[W1037]
    for r in rows {
        if r["status"] != "open" {
            lists["resolved"].append(r);
        } elif r["source"] == "cash_up" {
            lists["cash"].append(r);
        } else {
            lists["mpesa"].append(r);
        }
    }
    shown_tab: list[dict[str, any]] = lists[tab];  # jac:ignore[W1037]
    return
        <div className="flex max-w-3xl flex-col gap-4" data-testid="reconciliation">
            <p className="text-sm text-muted-foreground">
                Every day we ask M-Pesa again about your payments, and the box office counts its cash. Anything that doesn't add up is listed here until someone marks it resolved.
            </p>
            <h2 className="text-lg font-semibold" data-testid="open-exceptions">
                {f"{found['open']} to look at"
                    if int(found["open"]) > 0
                    else "Nothing to look at"}
            </h2>
            <Tabs
                label="Which to show"
                tabs={[
                    {"key": k, "label": label, "count": str(len(lists[k]))}
                    for (k, label) in TABS
                ]}
                current={tab}
                on_pick={set_tab}
                testid="recon-tab"
            />
            <Exceptions
                slug={slug}
                rows={shown_tab}
                tz={tz}
                empty={"Nothing resolved yet."
                    if tab == "resolved"
                    else "Nothing to look at here."}
                on_changed={load}
            />
            {tab == "cash" and <CashUps ups={ups} tz={tz}/>}
        </div>;
}
