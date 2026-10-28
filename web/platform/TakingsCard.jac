"""AfriCinemas' takings on the console's overview (P15.6, ADR-0085): fees earned,
invoiced, paid and overdue, per month (newest first) and per cinema, for platform staff.
A table, so every figure is read as text.
"""

import from react { useState, useEffect }
import from core.payments.reconcile_api { platform_takings }  # jac:ignore[W2037] authenticated endpoint
import from ..backoffice.report_view { money_label }

glob COLUMNS: list[tuple[str, str]] = [
         ("earned_cents", "Fees earned"),
         ("invoiced_cents", "Invoiced"),
         ("paid_cents", "Paid"),
         ("overdue_cents", "Overdue")
     ],
     CELL: str = "px-2 py-1.5 text-right tabular-nums";

def Table(
    label: str,
    first: str,
    rows: list[dict[str, any]],  # jac:ignore[W1037]
    key_of: str
) -> JsxElement {
    return
        <div className="overflow-x-auto">
            <table className="w-full min-w-[28rem] text-sm" aria-label={label}>
                <thead>
                    <tr className="border-b text-muted-foreground">
                        <th scope="col" className="px-2 py-1.5 text-left font-medium">
                            {first}
                        </th>
                        {[
                            <th key={k} scope="col" className={CELL + " font-medium"}>
                                {name}
                            </th> for (k, name) in COLUMNS
                        ]}
                    </tr>
                </thead>
                <tbody>
                    {[
                        <tr key={str(r[key_of])} className="border-b last:border-0">
                            <th
                                scope="row"
                                className="px-2 py-1.5 text-left font-normal"
                            >
                                {str(r[key_of])}
                            </th>
                            {[
                                <td key={k} className={CELL}>
                                    {money_label(int(r[k]), "KES")}
                                </td> for (k, _) in COLUMNS
                            ]}
                        </tr> for r in rows
                    ]}
                </tbody>
            </table>
        </div>;
}

def:pub TakingsCard -> JsxElement {
    [shown, set_shown] = useState(None);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await platform_takings();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_takings failed", e);
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
        return <span className="hidden"/>;
    }
    months: list[dict[str, any]] = found["months"];  # jac:ignore[W1037]
    return
        <section
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
            data-testid="platform-takings"
        >
            <h2 className="text-lg font-semibold">AfriCinemas' takings</h2>
            {len(months) == 0
                and <p className="text-sm text-muted-foreground">No fees yet.</p>}
            {len(months) > 0
                and <Table
                    label="By month"
                    first="Month"
                    rows={months}
                    key_of="month"
                />}
            {len(months) > 0
                and <Table
                    label="By cinema"
                    first="Cinema"
                    rows={found["cinemas"]}
                    key_of="name"
                />}
        </section>;
}
