"""The platform overview's figures (P13.4), on the console's home.

From platform_overview (core/platform/overview_api.jac): how many cinemas there are and
in which states, how many signed up this week, and bookings and net takings across the
platform over the last 14 days, with a column a day (or a line saying there were none).
The chart is the dashboard's
(web/backoffice/report_parts.jac: one series, a readout on hover, tap or focus, and a
table view), its count the day's bookings.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.spinner { Spinner }
import from core.platform.overview_api { platform_overview }  # jac:ignore[W2037] authenticated endpoint
import from ..shell.AppLink { AppLink }
import from ..backoffice.report_parts { KpiTile, TakingsChart }
import from ..backoffice.report_view { money_label }
import from ..storefront.showtimes { day_time_label }

def:pub OverviewFigures -> JsxElement {
    [found, set_found] = useState(None);
    [problem, set_problem] = useState("");

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_overview();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_overview failed", e);
        }
        if answer is None {
            set_problem("We couldn't load the figures. Refresh the page to try again.");
        } elif not answer["ok"] {
            set_problem(answer["error"]["message"]);
        } else {
            set_found(answer);
        }
    }

    def start {
        load();
    }
    useEffect(start, []);

    if problem {
        return
            <Alert variant="destructive" role="alert">
                <AlertDescription>{problem}</AlertDescription>
            </Alert>;
    }
    if found is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading the figures…
            </p>;
    }
    shown: dict[str, any] = found;  # jac:ignore[W1037]
    states: list[dict[str, any]] = shown["states"];  # jac:ignore[W1037]
    active: int = [
        s["count"]
        for s in states
        if s["key"] == "active"
    ][0];
    currency: str = shown["currency"];
    troubled: list[dict[str, any]] = shown["with_problems"] or [];  # jac:ignore[W1037]
    jobs: list[dict[str, str]] = shown["jobs"] or [];
    silent: list[dict[str, str]] = [
        j
        for j in jobs
        if j["state"] == "silent"
    ];
    waiting: list[dict[str, str]] = [
        j
        for j in jobs
        if j["state"] == "waiting"
    ];
    mpesa: dict[str, any] = shown["mpesa"];  # jac:ignore[W1037]
    links: list[list[str]] = mpesa["links"];
    why: list[str] = mpesa["why"];
    asked: dict[str, str] | None = mpesa["probe"];
    seen: list[str] = [];
    if "daraja" in why {
        seen.append("Daraja hasn't answered our last two checks");
    }
    if "payments" in why {
        seen.append(
            f"{mpesa['failures']} of the last {mpesa[
                'attempts'
            ]} payments failed on Safaricom's side"
        );
    }
    mpesa_why = " and ".join(seen) + ".";
    mpesa_line = "M-Pesa: not checked yet."
        if asked is None
        else (
            f"M-Pesa: answering (checked {day_time_label(
                asked['at'], shown['timezone']
            )})."
                if asked["result"] in ["ok", "refused"]
                else (
                    "M-Pesa: not checked (no M-Pesa provider set)."
                        if asked["result"] == "not_configured"
                        else f"M-Pesa: no answer at the last check ({day_time_label(
                            asked['at'], shown['timezone']
                        )})."
                )
        );
    # An empty 14 days says so, not as a chart of zeros.
    quiet = shown["bookings"] == 0 and shown["takings_net_cents"] == 0;
    return
        <div className="flex flex-col gap-4" data-testid="platform-figures">
            {mpesa["likely_down"]
                and <section
                    role="alert"
                    className="flex flex-col gap-2 rounded-xl border border-destructive/50 bg-destructive/5 p-4"
                    data-testid="overview-mpesa-down"
                >
                    <h2 className="font-semibold">
                        M-Pesa is likely down (Safaricom), not the cinemas
                    </h2>
                    <p className="text-sm">
                        {mpesa_why
                            + " Tell the cinemas to take cash meanwhile, and post on the status page."}
                    </p>
                    <ul className="flex flex-wrap gap-x-5 text-sm">
                        {[
                            <li key={l[1]}>
                                <a
                                    href={l[1]}
                                    target="_blank"
                                    rel="noreferrer"
                                    className="inline-flex min-h-11 items-center underline underline-offset-4"
                                >
                                    {l[0]}
                                </a>
                            </li> for l in links
                        ]}
                    </ul>
                </section>}
            <section
                className="grid grid-cols-2 gap-3 lg:grid-cols-4"
                aria-label="The platform today"
            >
                <KpiTile
                    label="Cinemas"
                    value={str(shown["cinemas"])}
                    note={f"{active} active"}
                    testid="overview-cinemas"
                />
                <KpiTile
                    label="Signed up this week"
                    value={str(shown["signed_up_this_week"])}
                    testid="overview-signups"
                />
                <KpiTile
                    label="Bookings"
                    value={str(shown["bookings"])}
                    note="Last 14 days"
                    testid="overview-bookings"
                />
                <KpiTile
                    label="Takings"
                    value={money_label(shown["takings_net_cents"], currency)}
                    note="Last 14 days, less refunds"
                    testid="overview-takings"
                />
            </section>
            {quiet
                and <p
                    className="rounded-xl bg-card p-4 text-sm text-muted-foreground ring-1 ring-foreground/10"
                    data-testid="overview-no-sales"
                >
                    No bookings or takings in the last 14 days.
                </p>}
            {not quiet
                and <section
                    className="rounded-xl bg-card p-4 ring-1 ring-foreground/10"
                >
                    <TakingsChart
                        points={shown["days"]}
                        unit="day"
                        currency={currency}
                        count_key="bookings"
                        count_words="bookings"
                        count_heading="Bookings"
                    />
                </section>}
            <section
                className={"flex flex-col gap-2 rounded-xl bg-card p-4 ring-1 "
                    + (
                        "ring-destructive/50"
                            if len(silent) > 0
                            else "ring-foreground/10"
                    )}
                data-testid="overview-jobs"
            >
                <h2 className="font-semibold" data-testid="overview-jobs-heading">
                    {"All background jobs are running"
                        if len(silent) == 0
                        else f"Background jobs stopped: {len(silent)}"}
                </h2>
                {len(silent) > 0
                    and <ul
                        className="flex flex-col gap-1 text-sm"
                        data-testid="overview-jobs-silent"
                    >
                        {[
                            <li key={j["name"]}>
                                <span className="font-medium">{j["label"]}</span>
                                <span className="text-muted-foreground">
                                    {f" · last ran {day_time_label(
                                        j['last_ran'], shown['timezone']
                                    )}"
                                        if j["last_ran"]
                                        else " · hasn't run"}
                                </span>
                            </li> for j in silent
                        ]}
                    </ul>}
                {not mpesa["likely_down"]
                    and <p
                        className="text-sm text-muted-foreground"
                        data-testid="overview-mpesa"
                    >
                        {mpesa_line}
                    </p>}
                {mpesa["our_keys_refused"]
                    and <p
                        className="text-sm text-destructive"
                        data-testid="overview-mpesa-keys"
                    >
                        Daraja refuses AfriCinemas' own M-Pesa keys (DARAJA_*): invoices can't be paid with M-Pesa until they're fixed.
                    </p>}
                {len(waiting) > 0
                    and <p className="text-sm text-muted-foreground">
                        {f"Not run yet since the server started: {', '.join(
                            [j['label'] for j in waiting]
                        )}."}
                    </p>}
            </section>
            <section
                className="flex flex-col gap-2 rounded-xl bg-card p-4 ring-1 ring-foreground/10"
                data-testid="overview-problems"
            >
                <h2 className="font-semibold">
                    {f"Cinemas with technical problems: {len(troubled)}"}
                </h2>
                {len(troubled) == 0
                    and <p className="text-sm text-muted-foreground">
                        None right now.
                    </p>}
                <ul className="flex flex-col gap-1">
                    {[
                        <li
                            key={c["slug"]}
                            className="flex items-center justify-between gap-3 text-sm"
                        >
                            <AppLink
                                to={f"/cinemas/{c['slug']}"}
                                className="inline-flex min-h-11 items-center font-medium underline underline-offset-4"
                            >
                                {c["name"]}
                            </AppLink>
                            <span className="text-muted-foreground">
                                {f"{c['problems']} {'thing'
                                    if c['problems'] == 1
                                    else 'things'} to look at"}
                            </span>
                        </li> for c in troubled[:5]
                    ]}
                </ul>
            </section>
            <section
                className="flex flex-col gap-2 rounded-xl bg-card p-4 ring-1 ring-foreground/10"
                data-testid="overview-states"
            >
                <h2 className="font-semibold">Cinemas by state</h2>
                <ul className="flex max-w-sm flex-col gap-1">
                    {[
                        <li
                            key={s["key"]}
                            className="flex justify-between gap-3 text-sm"
                        >
                            <span>{s["label"]}</span>
                            <span className="tabular-nums font-medium">
                                {s["count"]}
                            </span>
                        </li> for s in states
                    ]}
                </ul>
                <AppLink
                    to="/cinemas"
                    className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline underline-offset-4"
                >
                    All cinemas
                </AppLink>
            </section>
        </div>;
}
