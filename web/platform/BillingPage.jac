"""`/billing` in the platform console (P15.4, ADR-0083): every cinema's statements and
invoices, newest first, for platform staff (platform.read), each with its PDF.

A super admin (platform.settings) can issue what's due now, in case the monthly job
missed it; a month already issued is never issued again. In tabs (owner, 2026-10-29):
the Statements, and what needs acting on (BillingDesk, P15.5), each counted: Payments
to match, Disputes, and Overdue (cinemas past the grace period, to suspend or
reinstate).
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.billing.billing_api {
    platform_billing,  # jac:ignore[W2037] authenticated endpoint
    platform_billing_pdf,  # jac:ignore[W2037] authenticated endpoint
    platform_issue_statements  # jac:ignore[W2037] authenticated endpoint
}
import from ..backoffice.BillingSection { Statement }
import from .BillingDesk { BillingDesk, desk_lists }
import from ..shell.Tabs { Tabs }

def:pub BillingPage(may_issue: bool = False, may_suspend: bool = False) -> JsxElement {
    [shown, set_shown] = useState(None);
    [busy, set_busy] = useState(False);
    [note, set_note] = useState("");
    [tab, set_tab] = useState("statements");

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await platform_billing();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_billing failed", e);
        }
        if got is not None and got["ok"] {
            set_shown(got);
        }
    }

    def start {
        load();
    }
    useEffect(start, []);

    async def pdf_of(number: str) -> any {  # jac:ignore[W1037]
        return await platform_billing_pdf(number);  # jac:ignore[W2037]
    }

    async def issue {
        set_busy(True);
        set_note("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await platform_issue_statements();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_issue_statements failed", e);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_note("We couldn't issue them. Try again.");
            return;
        }
        made: list[str] = got["issued"];
        set_note(
            f"Issued {len(made)}: {', '.join(made)}."
                if len(made) > 0
                else "Nothing to issue: every statement due is out."
        );
        await load();
    }

    found: dict[str, any] | None = shown;  # jac:ignore[W1037]
    if found is None {
        return <Spinner/>;
    }
    statements: list[dict[str, any]] = found["statements"];  # jac:ignore[W1037]
    lists = desk_lists(found);
    def counted(key: str) -> str {
        return str(len(lists[key])) if len(lists[key]) > 0 else "";
    }
    return
        <div className="flex max-w-3xl flex-col gap-4" data-testid="platform-billing">
            <p className="text-sm text-muted-foreground">
                {f"Statements and invoices go out on the 1st of each month, for the month before. Cinemas pay to Paybill {found[
                    'paybill'
                ]}"
                    + (
                        " (a placeholder: set AFRICINEMAS_BILLING_PAYBILL once it's live)."
                            if found["paybill_is_placeholder"]
                            else "."
                    )}
            </p>
            {may_issue
                and <div className="flex flex-wrap items-center gap-3">
                    <Button className="min-h-11" disabled={busy} onClick={issue}>
                        {"Issuing…" if busy else "Issue what's due now"}
                    </Button>
                    <p
                        role="status"
                        aria-live="polite"
                        className="text-sm empty:hidden"
                    >
                        {note}
                    </p>
                </div>}
            <Tabs
                label="Billing"
                tabs={[
                    {"key": "statements", "label": "Statements", "count": ""},
                    {
                        "key": "match",
                        "label": "Payments to match",
                        "count": counted("match")
                    },
                    {
                        "key": "disputes",
                        "label": "Disputes",
                        "count": counted("disputes")
                    },
                    {"key": "overdue", "label": "Overdue", "count": counted("overdue")}
                ]}
                current={tab}
                on_pick={set_tab}
                testid="billing-tab"
            />
            {tab != "statements"
                and <BillingDesk
                    found={found}
                    part={tab}
                    may_act={may_issue}
                    may_suspend={may_suspend}
                    on_changed={load}
                />}
            {tab == "statements"
                and len(statements) == 0
                and <p className="rounded-lg border bg-card p-4 text-sm">
                    No statements yet.
                </p>}
            {tab == "statements"
                and len(statements) > 0
                and <ul className="flex flex-col gap-4">
                    {[
                        <Statement
                            key={s["number"]}
                            shown={s}
                            load_pdf={pdf_of}
                            cinema={s["cinema_name"]}
                        /> for s in statements
                    ]}
                </ul>}
        </div>;
}
