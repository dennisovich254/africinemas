"""`/reconciliation` in the platform console (P15.6, ADR-0085): every cinema's open
exceptions (from the daily M-Pesa check, uploaded statements and cash counts), for
platform staff (platform.read). Each cinema resolves its own on its Reconciliation page.
"""

import from react { useState, useEffect }
import from ...components.ui.spinner { Spinner }
import from core.payments.reconcile_api { platform_reconciliation }  # jac:ignore[W2037] authenticated endpoint
import from ..backoffice.ReconciliationSection { ExceptionText }

def:pub ReconciliationPage -> JsxElement {
    [shown, set_shown] = useState(None);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await platform_reconciliation();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_reconciliation failed", e);
        }
        if got is not None and got["ok"] {
            set_shown(got);
        }
    }

    def start {
        load();
    }
    useEffect(start, []);

    found: dict[str, any] | None = shown;  # jac:ignore[W1037]
    if found is None {
        return <Spinner/>;
    }
    rows: list[dict[str, any]] = found["exceptions"];  # jac:ignore[W1037]
    return
        <div
            className="flex max-w-3xl flex-col gap-4"
            data-testid="platform-reconciliation"
        >
            <p className="text-sm text-muted-foreground">
                What doesn't add up at each cinema: M-Pesa asked again every day, the statements cinemas upload, and the box office's cash counts. Cinemas resolve their own.
            </p>
            {len(rows) == 0
                and <p className="rounded-lg border bg-card p-4 text-sm">
                    Nothing open.
                </p>}
            {len(rows) > 0
                and <ul className="flex flex-col gap-3">
                    {[
                        <li
                            key={r["exception_id"]}
                            className="flex flex-col gap-1 rounded-lg border bg-card p-4"
                            data-testid="platform-exception"
                        >
                            <p className="font-medium">
                                {f"{r['cinema_name']}: {r['label']}"}
                            </p>
                            <p className="text-sm break-words">{ExceptionText(r)}</p>
                        </li> for r in rows
                    ]}
                </ul>}
        </div>;
}
