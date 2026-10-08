"""The dashboard's pieces (P7.3): KPI tiles, the takings chart, top movies, drill-down.

Charts are plain HTML, not SVG, so labels stay legible at phone width. One series each,
in `--chart-bar` (checked with the dataviz palette validator, core/theming/css.jac);
values and labels wear text colours, never the bar's. Every chart has a hover/tap/focus
readout and a table view, so nothing depends on seeing the bars.
"""

import from react { useState }
import from .report_view {
    day_label,
    point_label,
    percent,
    compact_money,
    nice_max,
    money_label
}
import from ..storefront.showtimes { day_label as show_day, time_label }

def:pub KpiTile(
    label: str, value: str, note: str = "", testid: str = ""
) -> JsxElement {
    return
        <div
            className="flex flex-col gap-1 rounded-xl bg-card p-4 ring-1 ring-foreground/10"
        >
            <p className="text-sm text-muted-foreground">{label}</p>
            <p data-testid={testid} className="text-2xl font-semibold tabular-nums">
                {value}
            </p>
            {note and <p className="text-xs text-muted-foreground">{note}</p>}
        </div>;
}

def ChartBar(
    index: int,
    height: float,
    readout: str,
    active: bool,
    side: str,
    on_show: any,  # jac:ignore[W1037]
    on_hide: any  # jac:ignore[W1037]
) -> JsxElement {
    # One bar: a hit target the full column tall (bigger than the mark), a 4px rounded
    # top, and its readout above it while hovered, tapped or focused. `side` keeps the
    # readout inside the chart at the ends ("left", "right", or "" centred).
    place = "left-1/2 -translate-x-1/2";
    if side == "left" {
        place = "left-0";
    } elif side == "right" {
        place = "right-0";
    }
    return
        <button
            type="button"
            data-testid="chart-bar"
            aria-label={readout}
            className="relative flex h-full min-w-0 flex-1 items-end focus-visible:outline-2"
            onMouseEnter={lambda { on_show(index); }}
            onMouseLeave={lambda { on_hide(); }}
            onFocus={lambda { on_show(index); }}
            onBlur={lambda { on_hide(); }}
            onClick={lambda { on_show(index); }}
        >
            <span
                aria-hidden="true"
                className="w-full rounded-t-[4px] bg-(--chart-bar)"
                style={{"height": f"{height}%"}}
            />
            {active
                and <span
                    role="tooltip"
                    data-testid="chart-readout"
                    className={f"pointer-events-none absolute bottom-full z-10 mb-2 whitespace-nowrap rounded-md bg-popover px-2 py-1 text-xs text-popover-foreground shadow-md ring-1 ring-foreground/10 {place}"}
                >
                    {readout}
                </span>}
        </button>;
}

def:pub TakingsChart(
    points: list[dict[str, any]],  # jac:ignore[W1037]
    unit: str,
    currency: str
) -> JsxElement {
    # Net takings a day (or a week), as columns on one axis, with a table view.
    [active, set_active] = useState(-1);
    top = nice_max(max([0] + [int(p["takings_net_cents"]) for p in points]));
    count = len(points);
    # At most about eight day labels under the chart, so they never collide.
    every = max(1, int((count + 7) / 8));
    def show(i: int) {
        set_active(i);
    }
    def hide {
        set_active(-1);
    }
    bars = [];
    labels = [];
    for (i, p) in enumerate(points) {
        cents = int(p["takings_net_cents"]);
        name = point_label(p["start"], unit);
        tickets = int(p["tickets_sold"]);
        side = "";
        if i < count / 4 {
            side = "left";
        } elif i >= count - count / 4 {
            side = "right";
        }
        bars.append(
            <ChartBar
                key={p["start"]}
                index={i}
                height={max(0, cents) * 100 / top}
                readout={f"{name}: {money_label(cents, currency)} taken, {tickets} tickets for its showtimes"}
                active={active == i}
                side={side}
                on_show={show}
                on_hide={hide}
            />
        );
        labels.append(
            <span key={p["start"]} className="min-w-0 flex-1 text-center">
                {day_label(p["start"]) if i % every == 0 else ""}
            </span>
        );
    }
    return
        <figure className="flex flex-col gap-3" data-testid="takings-chart">
            <figcaption className="text-sm font-medium">
                {"Net takings by week" if unit == "week" else "Net takings by day"}
            </figcaption>
            <div className="flex gap-2">
                <div
                    aria-hidden="true"
                    className="flex h-48 flex-col justify-between text-right text-xs text-muted-foreground tabular-nums"
                >
                    <span>{compact_money(top, currency)}</span>
                    <span>{compact_money(int(top / 2), currency)}</span>
                    <span>{compact_money(0, currency)}</span>
                </div>
                <div className="relative h-48 min-w-0 flex-1">
                    <div
                        aria-hidden="true"
                        className="absolute inset-0 flex flex-col justify-between"
                    >
                        <span className="border-t border-border/60"/>
                        <span className="border-t border-border/60"/>
                        <span className="border-t border-foreground/30"/>
                    </div>
                    <div className="relative flex h-full items-end gap-[2px]">
                        {bars}
                    </div>
                </div>
            </div>
            <div
                aria-hidden="true"
                className="ml-14 flex gap-[2px] text-xs text-muted-foreground"
            >
                {labels}
            </div>
            <details className="text-sm">
                <summary className="cursor-pointer py-2 text-muted-foreground">
                    Show as a table
                </summary>
                <table className="mt-2 w-full text-left text-sm">
                    <thead>
                        <tr className="border-b">
                            <th className="py-2 font-medium">
                                {"Week" if unit == "week" else "Day"}
                            </th>
                            <th className="py-2 text-right font-medium">Net takings</th>
                            <th className="py-2 text-right font-medium">Tickets</th>
                        </tr>
                    </thead>
                    <tbody>
                        {[
                            <tr key={p["start"]} className="border-b border-border/60">
                                <td className="py-2">
                                    {point_label(p["start"], unit)}
                                </td>
                                <td className="py-2 text-right tabular-nums">
                                    {money_label(int(p["takings_net_cents"]), currency)}
                                </td>
                                <td className="py-2 text-right tabular-nums">
                                    {p["tickets_sold"]}
                                </td>
                            </tr> for p in points
                        ]}
                    </tbody>
                </table>
            </details>
        </figure>;
}

def width_of(value: int, top: int) -> float {
    # A bar's width in percent of the longest, at least 1 so every bar shows.
    return max(1.0, value * 100.0 / top);
}

def:pub TopMovies(
    rows: list[dict[str, any]],  # jac:ignore[W1037]
    currency: str
) -> JsxElement {
    # Movies by ticket revenue: a labelled bar each, the value always written.
    if len(rows) == 0 {
        return
            <p className="text-sm text-muted-foreground">
                No tickets sold for showtimes in this period.
            </p>;
    }
    top = max([1] + [int(r["revenue_cents"]) for r in rows]);
    return
        <ol className="flex flex-col gap-3" data-testid="top-movies">
            {[
                <li key={r["movie_id"]} className="flex flex-col gap-1">
                    <div className="flex items-baseline justify-between gap-3 text-sm">
                        <span className="min-w-0 truncate font-medium">
                            {r["title"]}
                        </span>
                        <span className="shrink-0 tabular-nums text-muted-foreground">
                            {money_label(int(r["revenue_cents"]), currency)} · {r[
                                "tickets"
                            ]} tickets
                        </span>
                    </div>
                    <span
                        aria-hidden="true"
                        className="h-2 rounded-r-[4px] bg-(--chart-bar)"
                        style={{"width": f"{width_of(int(r['revenue_cents']), top)}%"}}
                    />
                </li> for r in rows
            ]}
        </ol>;
}

def Numbers(row: dict[str, any], currency: str) -> JsxElement {  # jac:ignore[W1037]
    # A drill-down row's figures.
    full: float = row["occupancy_pct"];
    return
        <span
            className="flex flex-wrap gap-x-4 gap-y-1 text-sm tabular-nums text-muted-foreground"
        >
            <span>{row["tickets_sold"]} tickets</span>
            <span>{percent(full)} full</span>
            <span>{money_label(int(row["ticket_revenue_cents"]), currency)}</span>
        </span>;
}

def:pub DrillDown(
    venues: list[dict[str, any]],  # jac:ignore[W1037]
    currency: str,
    timezone: str
) -> JsxElement {
    # Venue, screen, movie, showtime: each level opens the next.
    if len(venues) == 0 {
        return
            <p className="text-sm text-muted-foreground">
                No showtimes in this period.
            </p>;
    }
    return
        <ul className="flex flex-col gap-2" data-testid="drill-down">
            {[
                <li key={v["venue_id"]}>
                    <details className="rounded-lg border bg-card">
                        <summary
                            className="flex min-h-11 cursor-pointer flex-wrap items-center justify-between gap-2 px-4 py-2"
                        >
                            <span className="font-medium">{v["name"]}</span>
                            <Numbers row={v} currency={currency}/>
                        </summary>
                        <ul className="flex flex-col gap-2 border-t px-4 py-3">
                            {[
                                <li key={sc["screen_id"]}>
                                    <details>
                                        <summary
                                            className="flex min-h-11 cursor-pointer flex-wrap items-center justify-between gap-2"
                                        >
                                            <span>{sc["name"]}</span>
                                            <Numbers row={sc} currency={currency}/>
                                        </summary>
                                        <ul className="flex flex-col gap-2 pl-4">
                                            {[
                                                <li key={m["movie_id"]}>
                                                    <details>
                                                        <summary
                                                            className="flex min-h-11 cursor-pointer flex-wrap items-center justify-between gap-2"
                                                        >
                                                            <span>{m["title"]}</span>
                                                            <Numbers
                                                                row={m}
                                                                currency={currency}
                                                            />
                                                        </summary>
                                                        <ul
                                                            className="flex flex-col gap-1 pl-4"
                                                        >
                                                            {[
                                                                <li
                                                                    key={s[
                                                                        "screening_id"
                                                                    ]}
                                                                    className="flex min-h-11 flex-wrap items-center justify-between gap-2"
                                                                >
                                                                    <span>
                                                                        {show_day(
                                                                            s[
                                                                                "starts_at"
                                                                            ],
                                                                            timezone
                                                                        )}, {time_label(
                                                                            s[
                                                                                "starts_at"
                                                                            ],
                                                                            timezone
                                                                        )}
                                                                    </span>
                                                                    <Numbers
                                                                        row={s}
                                                                        currency={currency}
                                                                    />
                                                                </li>
                                                                for s in m["showtimes"]
                                                            ]}
                                                        </ul>
                                                    </details>
                                                </li> for m in sc["movies"]
                                            ]}
                                        </ul>
                                    </details>
                                </li> for sc in v["screens"]
                            ]}
                        </ul>
                    </details>
                </li> for v in venues
            ]}
        </ul>;
}
