"""The reports' part-to-whole charts (owner, 2026-10-27): split bars and a donut.

- SplitBar: one horizontal bar in two parts (tickets and snacks, M-Pesa and cash,
  online and the box office, the cinema's share and AfriCinemas' fees), each part in
  its slot colour (--chart-1, --chart-2) with a 2px gap. Under it, each part's name,
  amount and share, in text colours, so nothing depends on the colour; the bar itself
  is a picture of those numbers, with no tiny tap targets.
- ShareDonut: the top movies' share of ticket revenue, the top four in --chart-1..4
  and the rest as "Other" in a neutral grey, an SVG ring with 2px gaps and the total in
  the middle. The legend beside it is the table: each slice's name, amount and share.

The donut answers a hover, tap or focus on a legend row by naming that slice in the
middle. With nothing to show, both say so instead of drawing an empty mark.
"""

import from react { useState }
import from .report_view { money_label }

glob SLOTS: list[str] = [
         "var(--chart-1)",
         "var(--chart-2)",
         "var(--chart-3)",
         "var(--chart-4)"
     ],
     OTHER: str = "var(--chart-other)",
     # The ring: radius 40 and stroke 14 in a 100-unit box.
     RADIUS: float = 40.0,
     STROKE: float = 14.0,
     GAP: float = 0.6;

def share_label(part: int, whole: int) -> str {
    # part as a whole percentage of whole ("<1%" for a sliver); "0%" with no whole.
    if whole <= 0 or part <= 0 {
        return "0%";
    }
    pct = part * 100 / whole;
    if pct < 1 {
        return "<1%";
    }
    return f"{round(pct)}%";
}

def:pub SplitBar(  # jac:ignore[W3030] a titled bar: two named amounts, the currency and a test id
    title: str,
    left_label: str,
    left_cents: int,
    right_label: str,
    right_cents: int,
    currency: str,
    testid: str
) -> JsxElement {
    left = max(0, left_cents);
    right = max(0, right_cents);
    whole = left + right;
    parts: list[dict[str, any]] = [  # jac:ignore[W1037]
        {"key": "left", "label": left_label, "cents": left, "colour": SLOTS[0]},
        {"key": "right", "label": right_label, "cents": right, "colour": SLOTS[1]}
    ];
    return
        <figure data-testid={testid} className="flex min-w-0 flex-col gap-2">
            <figcaption className="text-sm font-medium">{title}</figcaption>
            {whole <= 0
                and <p className="text-sm text-muted-foreground">
                    Nothing in this period.
                </p>}
            {whole > 0
                and <div className="relative flex h-3 w-full gap-[2px]">
                    {[
                        (
                            <span
                                key={p["key"]}
                                aria-hidden="true"
                                className="h-full min-w-[4px] first:rounded-l-[4px] last:rounded-r-[4px]"
                                style={{
                                    "width": f"{p['cents'] * 100 / whole}%",
                                    "background": p["colour"]
                                }}
                            />
                                if p["cents"] > 0
                                else <span key={p["key"]} className="hidden"/>
                        ) for p in parts
                    ]}
                </div>}
            {whole > 0
                and <ul
                    className="flex flex-wrap justify-between gap-x-4 gap-y-1 text-sm"
                >
                    {[
                        <li
                            key={p["key"]}
                            data-testid={f"{testid}-{p['key']}"}
                            className="flex items-center gap-1.5"
                        >
                            <span
                                aria-hidden="true"
                                className="size-2.5 shrink-0 rounded-sm"
                                style={{"background": p["colour"]}}
                            />
                            <span>{p["label"]}</span>
                            <span className="tabular-nums text-muted-foreground">
                                {money_label(p["cents"], currency)
                                    + " · "
                                    + share_label(p["cents"], whole)}
                            </span>
                        </li> for p in parts
                    ]}
                </ul>}
        </figure>;
}

def _slices(
    rows: list[dict[str, any]],  # jac:ignore[W1037]
    whole: int,
    circumference: float
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Each slice as {"i", "name", "cents", "colour", "length", "start"}: the top four
    # movies, then the rest as "Other", with where each sits around the ring. Dicts,
    # not tuples: a nested tuple in a client comprehension loses its names (JI-061).
    top = [
        r
        for r in rows
        if int(r["revenue_cents"]) > 0
    ][:4];
    made: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for r in top {
        made.append(
            {
                "name": str(r["title"]),
                "cents": int(r["revenue_cents"]),
                "colour": SLOTS[len(made)]
            }
        );
    }
    rest = whole - sum([m["cents"] for m in made]);
    if rest > 0 {
        made.append({"name": "Other", "cents": rest, "colour": OTHER});
    }
    run = 0.0;
    n = 0;
    for m in made {
        m["i"] = n;
        n += 1;
        m["length"] = m["cents"] * circumference / whole;
        m["start"] = run;
        run += m["length"];
    }
    return made;
}

def:pub ShareDonut(
    rows: list[dict[str, any]],  # jac:ignore[W1037]
    whole_cents: int,
    currency: str
) -> JsxElement {
    # `rows`: the top movies by revenue ({title, revenue_cents}); `whole_cents`: all the
    # ticket revenue in the period, so the rest is "Other".
    [active, set_active] = useState(-1);
    whole = max(0, whole_cents);
    circumference = 2 * 3.14159265 * RADIUS;
    slices = _slices(rows, whole, circumference) if whole > 0 else [];
    gap = GAP if len(slices) > 1 else 0.0;
    arcs = [
        <circle
            key={f"{m['i']}"}
            cx="50"
            cy="50"
            r={f"{RADIUS}"}
            fill="none"
            stroke={m["colour"]}
            strokeWidth={f"{STROKE + (2 if active == m['i'] else 0)}"}
            strokeDasharray={f"{max(m['length'] - gap, 0.1)} {circumference}"}
            strokeDashoffset={f"{0 - m['start']}"}
            transform="rotate(-90 50 50)"
            onMouseEnter={lambda { set_active(m["i"]); }}
            onMouseLeave={lambda { set_active(-1); }}
        /> for m in slices
    ];
    shown: dict[str, any] | None = slices[active]  # jac:ignore[W1037]
        if active >= 0 and active < len(slices)
        else None;
    centre_top = shown["name"] if shown is not None else "Ticket revenue";
    centre_value = money_label(
        shown["cents"] if shown is not None else whole, currency
    );
    return
        <figure data-testid="movie-share" className="flex min-w-0 flex-col gap-3">
            <figcaption className="text-sm font-medium">
                Ticket revenue by movie
            </figcaption>
            {whole <= 0
                and <p className="text-sm text-muted-foreground">
                    No tickets sold in this period.
                </p>}
            {whole > 0
                and <div className="flex flex-wrap items-center gap-6">
                    <div className="relative size-40 shrink-0">
                        <svg
                            viewBox="0 0 100 100"
                            role="img"
                            aria-label={"Ticket revenue by movie: "
                                + "; ".join(
                                    [
                                        f"{m['name']} {share_label(m['cents'], whole)}"
                                        for m in slices
                                    ]
                                )}
                            className="size-full"
                        >
                            {arcs}
                        </svg>
                        <div
                            aria-hidden="true"
                            className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center px-6 text-center"
                        >
                            <span
                                className="line-clamp-2 text-xs text-muted-foreground"
                            >
                                {centre_top}
                            </span>
                            <span className="text-sm font-semibold tabular-nums">
                                {centre_value}
                            </span>
                        </div>
                    </div>
                    <ul className="flex min-w-0 flex-1 flex-col gap-1 text-sm">
                        {[
                            <li
                                key={f"{m['i']}"}
                                className="flex min-w-0 items-center gap-2"
                            >
                                <button
                                    type="button"
                                    data-testid="movie-share-row"
                                    className={"flex min-h-11 min-w-0 flex-1 items-center gap-2 text-left focus-visible:outline-2"
                                        + (" font-medium" if active == m["i"] else "")}
                                    onMouseEnter={lambda { set_active(m["i"]); }}
                                    onMouseLeave={lambda { set_active(-1); }}
                                    onFocus={lambda { set_active(m["i"]); }}
                                    onBlur={lambda { set_active(-1); }}
                                    onClick={lambda { set_active(m["i"]); }}
                                >
                                    <span
                                        aria-hidden="true"
                                        className="size-2.5 shrink-0 rounded-sm"
                                        style={{"background": m["colour"]}}
                                    />
                                    <span className="min-w-0 flex-1 truncate">
                                        {m["name"]}
                                    </span>
                                    <span
                                        className="shrink-0 tabular-nums text-muted-foreground"
                                    >
                                        {money_label(m["cents"], currency)
                                            + " · "
                                            + share_label(m["cents"], whole)}
                                    </span>
                                </button>
                            </li> for m in slices
                        ]}
                    </ul>
                </div>}
        </figure>;
}

def:pub OccupancyMeter(sold: int, seats: int, showtimes: int) -> JsxElement {
    # How full the period's showtimes were: one ratio, so a meter (a track with the
    # same slot's fill), the percentage large and the counts in words beside it.
    filled = min(max(sold, 0), max(seats, 0));
    pct = (filled * 100 / seats) if seats > 0 else 0;
    return
        <figure
            data-testid="occupancy-meter"
            className="flex flex-col gap-2 rounded-xl bg-card p-4 ring-1 ring-foreground/10"
        >
            <figcaption className="flex flex-wrap items-baseline justify-between gap-2">
                <span className="text-sm font-medium">How full the showtimes were</span>
                <span className="text-2xl font-semibold tabular-nums">
                    {f"{round(pct)}%" if seats > 0 else "No seats on sale"}
                </span>
            </figcaption>
            <div
                role="meter"
                aria-valuemin={0}
                aria-valuemax={100}
                aria-valuenow={round(pct)}
                aria-label="Occupancy"
                className="relative h-3 w-full overflow-hidden rounded-[4px]"
            >
                <span
                    aria-hidden="true"
                    className="absolute inset-0 bg-(--chart-1) opacity-20"
                />
                <span
                    aria-hidden="true"
                    className="absolute inset-y-0 left-0 rounded-[4px] bg-(--chart-1)"
                    style={{"width": f"{pct}%"}}
                />
            </div>
            <p className="text-sm text-muted-foreground">
                {f"{filled} of {seats} seats sold across {showtimes} showtimes"}
            </p>
        </figure>;
}
