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
    parts = [
        ("left", left_label, left, SLOTS[0]),
        ("right", right_label, right, SLOTS[1])
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
                                key={key}
                                aria-hidden="true"
                                className="h-full min-w-[4px] first:rounded-l-[4px] last:rounded-r-[4px]"
                                style={{
                                    "width": f"{cents * 100 / whole}%",
                                    "background": colour
                                }}
                            />
                                if cents > 0
                                else <span key={key} className="hidden"/>
                        ) for (key, label, cents, colour) in parts
                    ]}
                </div>}
            {whole > 0
                and <ul
                    className="flex flex-wrap justify-between gap-x-4 gap-y-1 text-sm"
                >
                    {[
                        <li
                            key={key}
                            data-testid={f"{testid}-{key}"}
                            className="flex items-center gap-1.5"
                        >
                            <span
                                aria-hidden="true"
                                className="size-2.5 shrink-0 rounded-sm"
                                style={{"background": colour}}
                            />
                            <span>{label}</span>
                            <span className="tabular-nums text-muted-foreground">
                                {f"{money_label(cents, currency)} · {share_label(
                                    cents, whole
                                )}"}
                            </span>
                        </li> for (key, label, cents, colour) in parts
                    ]}
                </ul>}
        </figure>;
}

def _slices(rows: list[dict[str, any]], whole: int) -> list[tuple[str, int, str]] {  # jac:ignore[W1037]
    # (name, cents, colour): the top four movies, then the rest as "Other".
    top = [
        r
        for r in rows
        if int(r["revenue_cents"]) > 0
    ][:4];
    made: list[tuple[str, int, str]] = [];
    for (i, r) in enumerate(top) {
        made.append((str(r["title"]), int(r["revenue_cents"]), SLOTS[i]));
    }
    rest = whole - sum([c for (n, c, k) in made]);
    if rest > 0 {
        made.append(("Other", rest, OTHER));
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
    slices = _slices(rows, whole) if whole > 0 else [];
    circumference = 2 * 3.14159265 * RADIUS;
    # Each slice's length and where it starts around the ring.
    lengths = [c * circumference / whole for (label, c, tint) in slices]
        if whole > 0
        else [];
    starts: list[float] = [];
    run = 0.0;
    for length in lengths {
        starts.append(run);
        run += length;
    }
    gap = GAP if len(slices) > 1 else 0.0;
    arcs = [
        <circle
            key={f"{i}"}
            cx="50"
            cy="50"
            r={f"{RADIUS}"}
            fill="none"
            stroke={colour}
            strokeWidth={f"{STROKE + (2 if active == i else 0)}"}
            strokeDasharray={f"{max(lengths[i] - gap, 0.1)} {circumference}"}
            strokeDashoffset={f"{0 - starts[i]}"}
            transform="rotate(-90 50 50)"
            onMouseEnter={lambda { set_active(i); }}
            onMouseLeave={lambda { set_active(-1); }}
        /> for (i, (label, c, colour)) in enumerate(slices)
    ];
    shown: tuple[str, int, str] | None = slices[active]
        if active >= 0 and active < len(slices)
        else None;
    centre_top = shown[0] if shown is not None else "Ticket revenue";
    centre_value = money_label(shown[1] if shown is not None else whole, currency);
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
                                        f"{n} {share_label(c, whole)}"
                                        for (n, c, k) in slices
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
                                key={f"{i}"}
                                className="flex min-w-0 items-center gap-2"
                            >
                                <button
                                    type="button"
                                    data-testid="movie-share-row"
                                    className={"flex min-h-11 min-w-0 flex-1 items-center gap-2 text-left focus-visible:outline-2"
                                        + (" font-medium" if active == i else "")}
                                    onMouseEnter={lambda { set_active(i); }}
                                    onMouseLeave={lambda { set_active(-1); }}
                                    onFocus={lambda { set_active(i); }}
                                    onBlur={lambda { set_active(-1); }}
                                    onClick={lambda { set_active(i); }}
                                >
                                    <span
                                        aria-hidden="true"
                                        className="size-2.5 shrink-0 rounded-sm"
                                        style={{"background": colour}}
                                    />
                                    <span className="min-w-0 flex-1 truncate">
                                        {name}
                                    </span>
                                    <span
                                        className="shrink-0 tabular-nums text-muted-foreground"
                                    >
                                        {f"{money_label(cents, currency)} · {share_label(
                                            cents, whole
                                        )}"}
                                    </span>
                                </button>
                            </li> for (i, (name, cents, colour)) in enumerate(slices)
                        ]}
                    </ul>
                </div>}
        </figure>;
}
