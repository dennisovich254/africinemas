"""Snack sales in the chosen period, and current stock alerts (P12.11)."""

import from .report_view { money_label }

def SnackRanking(
    rows: list[dict[str, any]],  # jac:ignore[W1037]
    title: str,
    testid: str,
    currency: str
) -> JsxElement {
    return
        <div
            className="min-w-0 rounded-xl bg-card p-4 ring-1 ring-foreground/10"
            data-testid={testid}
        >
            <table className="w-full table-fixed text-left text-sm">
                <caption className="pb-3 text-left font-medium text-foreground">
                    {title}
                </caption>
                <thead>
                    <tr className="border-b">
                        <th scope="col" className="w-1/2 py-2 font-medium">Snack</th>
                        <th scope="col" className="w-1/6 py-2 text-right font-medium">
                            Units
                        </th>
                        <th scope="col" className="py-2 text-right font-medium">
                            Sales
                        </th>
                    </tr>
                </thead>
                <tbody>
                    {[
                        <tr key={r["id"]} className="border-b border-border/60">
                            <th
                                scope="row"
                                className="break-words py-3 pr-2 font-normal"
                            >
                                {r["name"]}
                            </th>
                            <td className="py-3 text-right tabular-nums">
                                {r["quantity"]}
                            </td>
                            <td
                                className="break-words py-3 pl-2 text-right tabular-nums"
                            >
                                {money_label(r["revenue_cents"], currency)}
                            </td>
                        </tr> for r in rows
                    ]}
                </tbody>
            </table>
            {len(rows) == 0
                and <p className="py-3 text-sm text-muted-foreground">
                    No snacks sold in this period.
                </p>}
        </div>;
}

def:pub SnackReport(snacks: dict[str, any], currency: str) -> JsxElement {  # jac:ignore[W1037]
    low: list[dict[str, any]] = snacks["low_stock"];  # jac:ignore[W1037]
    return
        <section
            aria-labelledby="snacks-heading"
            className="flex flex-col gap-4"
            data-testid="snack-report"
        >
            <div className="flex flex-col gap-1">
                <h2 id="snacks-heading" className="text-lg font-semibold">Snacks</h2>
                <p
                    className="text-sm text-muted-foreground"
                    data-testid="snack-sales-summary"
                >
                    {f"{snacks['units']} units sold · {money_label(
                        snacks['sales_cents'], currency
                    )} before refunds."}
                </p>
                <p className="text-sm text-muted-foreground">
                    Top 10 by sales in this period, counted when paid. Extras are included; a combo counts as one item.
                </p>
            </div>
            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                <SnackRanking
                    rows={snacks["top_products"]}
                    title="Top products"
                    testid="top-snack-products"
                    currency={currency}
                />
                <SnackRanking
                    rows={snacks["top_variants"]}
                    title="Top variants"
                    testid="top-snack-variants"
                    currency={currency}
                />
            </div>
            <div
                className="flex flex-col gap-3 rounded-xl bg-card p-4 ring-1 ring-foreground/10"
                data-testid="snack-low-stock"
            >
                <h3 className="text-sm font-medium">Low stock now</h3>
                <p className="text-sm text-muted-foreground">
                    Available stock after reservations, at the selected venues. This is current stock, not the selected dates.
                </p>
                {len(low) == 0
                    and <p className="text-sm text-muted-foreground">
                        No low-stock alerts at these venues.
                    </p>}
                <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    {[
                        <li
                            key={r["venue_id"] + ":" + r["variant_id"]}
                            className="min-w-0 rounded-lg border p-3"
                        >
                            <p className="break-words font-medium">{r["name"]}</p>
                            <p className="break-words text-sm text-muted-foreground">
                                {r["venue"]}
                            </p>
                            <p className="mt-2 text-sm font-medium">
                                {f"{r['available']} available · "}{"Out of stock"
                                    if r["status"] == "out"
                                    else "Low stock"}
                            </p>
                            <p className="text-sm text-muted-foreground">
                                {f"{r['on_hand']} on hand · {r[
                                    'reserved'
                                ]} reserved · alert at {r['low_threshold']}"}
                            </p>
                        </li> for r in low
                    ]}
                </ul>
            </div>
        </section>;
}
