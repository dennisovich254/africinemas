"""The back office's Overview (P7.4): the first page every member of staff sees.

One request (staff_home) brings what the member's roles allow, for the cinema's today:
today's figures (who reads reports), today's showtimes with Sell or Scan where they may
(everyone who reads showtimes), quick actions (from their permissions), the setup
checklist until it's done (who sets the cinema up) and recent activity (who reads the
audit log). Desktop: the day on the left, actions and setup on the right; a phone
stacks them, most useful first. Off shift, the page says what starting one shows.
"""

import from react { useState, useEffect }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Ticket01Icon,
    QrCodeIcon,
    Calendar03Icon,
    UserAdd01Icon,
    ChartHistogramIcon,
    CheckmarkCircle02Icon,
    CircleIcon,
    ArrowUpRight01Icon
}
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.reporting.staff_home { staff_home }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from ..shell.AppLink { AppLink }
import from ..storefront.showtimes { time_label }
import from .report_view { day_label, percent, money_label, action_label, result_label }
import from .report_parts { KpiTile }
import from .nav { section_path }

glob CARD: str = "flex flex-col gap-4 rounded-xl bg-card p-4 ring-1 ring-foreground/10 sm:p-5";

def greeting(tz: str) -> str {
    # "Good morning" / "Good afternoon" / "Good evening", at the cinema's hour.
    stamp: str = new(Date).toLocaleString(  # jac:ignore[W2001]
        "en-GB", {"hour": "2-digit", "hour12": False, "timeZone": tz}
    );
    hour = int(stamp);
    if hour < 12 {
        return "Good morning";
    }
    return "Good afternoon" if hour < 17 else "Good evening";
}

def QuickAction(
    to: str,
    label: str,
    hint: str,
    icon: any,  # jac:ignore[W1037]
    testid: str
) -> JsxElement {
    return
        <li>
            <AppLink
                to={to}
                testid={testid}
                className="flex min-h-14 items-center gap-3 rounded-lg p-3 ring-1 ring-foreground/10 transition-colors hover:bg-muted focus-visible:outline-2"
            >
                <span
                    className="flex size-10 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary"
                >
                    <HugeiconsIcon icon={icon} strokeWidth={2} aria-hidden="true"/>
                </span>
                <span className="flex min-w-0 flex-col">
                    <span className="font-medium">{label}</span>
                    <span className="text-xs text-muted-foreground">{hint}</span>
                </span>
            </AppLink>
        </li>;
}

def QuickActions(slug: str, permissions: list[str]) -> JsxElement {
    # The jobs this member's roles allow, at most four, as large targets.
    actions = [];
    if "bookings.create" in permissions {
        actions.append(
            <QuickAction
                key="sell"
                to={section_path(slug, "box-office")}
                label="Sell tickets"
                hint="Box office, cash or M-Pesa"
                icon={Ticket01Icon}
                testid="quick-sell"
            />
        );
    }
    if "tickets.scan" in permissions {
        actions.append(
            <QuickAction
                key="scan"
                to={section_path(slug, "scanner")}
                label="Scan tickets"
                hint="Check people in at the door"
                icon={QrCodeIcon}
                testid="quick-scan"
            />
        );
    }
    if "showtimes.create" in permissions {
        actions.append(
            <QuickAction
                key="showtime"
                to={section_path(slug, "screenings")}
                label="Add a showtime"
                hint="Schedule and publish"
                icon={Calendar03Icon}
                testid="quick-showtime"
            />
        );
    }
    if "financial_reports.read" in permissions {
        actions.append(
            <QuickAction
                key="reports"
                to={section_path(slug, "reports")}
                label="Reports"
                hint="Takings, occupancy, top movies"
                icon={ChartHistogramIcon}
                testid="quick-reports"
            />
        );
    }
    if "employees.invite" in permissions {
        actions.append(
            <QuickAction
                key="invite"
                to={section_path(slug, "staff")}
                label="Invite staff"
                hint="Add someone to your team"
                icon={UserAdd01Icon}
                testid="quick-invite"
            />
        );
    }
    if len(actions) == 0 {
        return <span/>;
    }
    return
        <section aria-labelledby="quick-heading" className={CARD}>
            <h2 id="quick-heading" className="text-base font-semibold">
                Quick actions
            </h2>
            <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-1">
                {actions[:4]}
            </ul>
        </section>;
}

def ShowtimeRow(
    show: dict[str, any],  # jac:ignore[W1037]
    slug: str,
    tz: str
) -> JsxElement {
    sold = int(show["seats_sold"]);
    seats = int(show["seats_on_sale"]);
    filled = (sold * 100 / seats) if seats > 0 else 0;
    return
        <li
            data-testid="home-showtime"
            className="flex flex-col gap-3 border-b border-border/60 py-3 last:border-0 sm:flex-row sm:items-center sm:gap-4"
        >
            <span className="w-14 shrink-0 text-lg font-semibold tabular-nums">
                {time_label(show["starts_at"], tz)}
            </span>
            <span className="flex min-w-0 flex-1 flex-col gap-1.5">
                <span className="truncate font-medium">{show["movie_title"]}</span>
                <span className="text-xs text-muted-foreground">
                    {show["venue"]} · {show["screen"]}
                </span>
                <span
                    className="flex items-center gap-2 text-xs text-muted-foreground tabular-nums"
                >
                    <span
                        aria-hidden="true"
                        className="h-1.5 w-full max-w-40 overflow-hidden rounded-full bg-muted"
                    >
                        <span
                            className="block h-full rounded-full bg-(--chart-bar)"
                            style={{"width": f"{filled}%"}}
                        />
                    </span>
                    <span data-testid="home-showtime-seats">
                        {sold} of {seats} sold
                    </span>
                </span>
            </span>
            <span className="flex gap-2">
                {show["can_sell"]
                    and <Button asChild size="sm" className="min-h-11">
                        <AppLink
                            to={section_path(slug, "box-office")}
                            testid="home-sell"
                        >
                            Sell
                        </AppLink>
                    </Button>}{show["can_scan"]
                    and <Button
                        asChild
                        size="sm"
                        variant="outline"
                        className="min-h-11"
                    >
                        <AppLink to={section_path(slug, "scanner")} testid="home-scan">
                            Scan
                        </AppLink>
                    </Button>}
            </span>
        </li>;
}

def SetupChecklist(
    setup: dict[str, any],  # jac:ignore[W1037]
    slug: str
) -> JsxElement {
    # Until every step is done: what's done, and a link to do the next ones.
    done = int(setup["done"]);
    total = int(setup["total"]);
    if done >= total {
        return <span/>;
    }
    return
        <section
            aria-labelledby="setup-heading"
            data-testid="setup-checklist"
            className={CARD}
        >
            <div className="flex items-baseline justify-between gap-3">
                <h2 id="setup-heading" className="text-base font-semibold">
                    Get your cinema ready
                </h2>
                <span
                    data-testid="setup-progress"
                    className="text-sm text-muted-foreground tabular-nums"
                >
                    {done} of {total} done
                </span>
            </div>
            <span
                aria-hidden="true"
                className="h-1.5 overflow-hidden rounded-full bg-muted"
            >
                <span
                    className="block h-full rounded-full bg-primary"
                    style={{"width": f"{done * 100 / total}%"}}
                />
            </span>
            <ol className="flex flex-col">
                {[
                    <li key={step["key"]}>
                        <AppLink
                            to={section_path(slug, step["section"])}
                            testid={f"setup-{step['key']}"}
                            className="flex min-h-11 items-center gap-3 rounded-md px-2 py-2 hover:bg-muted"
                        >
                            <HugeiconsIcon
                                icon={CheckmarkCircle02Icon
                                    if step["done"]
                                    else CircleIcon}
                                strokeWidth={2}
                                className={"shrink-0 text-primary"
                                    if step["done"]
                                    else "shrink-0 text-muted-foreground"}
                                aria-hidden="true"
                            />
                            <span
                                className={"text-muted-foreground line-through"
                                    if step["done"]
                                    else "font-medium"}
                            >
                                {step["label"]}
                            </span>
                            <span className="sr-only">
                                {"(done)" if step["done"] else "(to do)"}
                            </span>
                        </AppLink>
                    </li> for step in setup["steps"]
                ]}
            </ol>
        </section>;
}

def RecentActivity(activity: list[dict[str, str]], slug: str, tz: str) -> JsxElement {
    return
        <section
            aria-labelledby="activity-heading"
            data-testid="recent-activity"
            className={CARD}
        >
            <div className="flex items-baseline justify-between gap-3">
                <h2 id="activity-heading" className="text-base font-semibold">
                    Recent activity
                </h2>
                <AppLink
                    to={section_path(slug, "audit")}
                    className="text-sm font-medium underline underline-offset-4"
                >
                    Audit log
                </AppLink>
            </div>
            {len(activity) == 0
                and <p className="text-sm text-muted-foreground">Nothing yet.</p>}
            <ul className="flex flex-col gap-3">
                {[
                    <li key={e["event_id"]} className="flex flex-col text-sm">
                        <span className="font-medium">
                            {action_label(e["action"])}{e["result"] != "ok"
                                and <span className="font-normal text-muted-foreground">
                                    {f" · {result_label(e['result'])}"}
                                </span>}
                        </span>
                        <span className="text-xs text-muted-foreground">
                            {time_label(e["at"], tz)} · {e["actor"] or "Staff member"}
                        </span>
                    </li> for e in activity
                ]}
            </ul>
        </section>;
}

def:pub StaffHome(
    slug: str, shift_open: bool, permissions: list[str], roles: list[str]
) -> JsxElement {
    # roles: how the member's roles read ("Owner", "Usher (Westgate)").
    [home, set_home] = useState(None);
    [failed, set_failed] = useState("");

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await staff_home(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("staff_home failed", e);
            set_failed(
                "We couldn't load today's overview. Refresh the page to try again."
            );
            return;
        }
        if not got["ok"] {
            set_failed(got["error"]["message"]);
            return;
        }
        set_failed("");
        set_home(got);
    }

    def start_loading {
        if shift_open {
            load();
        }
    }
    useEffect(start_loading, [slug, shift_open]);

    hello = "Welcome back";
    if home is not None {
        loaded: dict[str, any] = home;  # jac:ignore[W1037]
        place: dict[str, str] = loaded["cinema"];
        hello = greeting(place["timezone"]) + " · " + day_label(place["today"]);
    }
    header = <div className="flex flex-col gap-1">
        <p data-testid="home-greeting" className="text-sm text-muted-foreground">
            {hello}
        </p>
        <p className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
            {shift_open
                and <span
                    data-testid="shift-status"
                    className="inline-flex items-center gap-2"
                >
                    <Badge>On shift</Badge>
                    <span className="text-muted-foreground">
                        Ends when you sign out
                    </span>
                </span>}
            <span className="text-muted-foreground">
                Signed in as {", ".join(roles)}
            </span>
            <a
                href={f"/c/{slug}"}
                target="_blank"
                rel="noopener"
                className="inline-flex min-h-11 items-center gap-1 font-medium underline underline-offset-4"
            >
                View your storefront
                <HugeiconsIcon
                    icon={ArrowUpRight01Icon}
                    strokeWidth={2}
                    className="size-4"
                    aria-hidden="true"
                />
                <span className="sr-only">(opens in a new tab)</span>
            </a>
        </p>
    </div>;

    if not shift_open {
        return
            <div className="mx-auto flex w-full max-w-6xl flex-col gap-6">
                {header}
                <p
                    data-testid="home-off-shift"
                    className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground"
                >
                    Start your shift to see today's showtimes, sales and your setup steps.
                </p>
            </div>;
    }
    if home is None {
        return
            <div className="mx-auto flex w-full max-w-6xl flex-col gap-6">
                {header}{failed
                    and <Alert variant="destructive">
                        <AlertDescription>{failed}</AlertDescription>
                    </Alert>}{not failed
                    and <p
                        role="status"
                        className="flex items-center gap-2 text-muted-foreground"
                    >
                        <Spinner aria-hidden="true"/>
                        Loading today…
                    </p>}
            </div>;
    }
    got: dict[str, any] = home;  # jac:ignore[W1037]
    tz: str = got["cinema"]["timezone"];
    shows: list[dict[str, any]] = got["showtimes"];  # jac:ignore[W1037]
    figures: dict[str, any] | None = got["figures"];  # jac:ignore[W1037]
    return
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-6">
            {header}
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
                <div className="flex flex-col gap-6 lg:col-span-2">
                    {figures is not None
                        and <section
                            aria-labelledby="today-heading"
                            className="flex flex-col gap-3"
                        >
                            <div className="flex items-baseline justify-between gap-3">
                                <h2
                                    id="today-heading"
                                    className="text-base font-semibold"
                                >
                                    Today
                                </h2>
                                <AppLink
                                    to={section_path(slug, "reports")}
                                    testid="open-reports"
                                    className="text-sm font-medium underline underline-offset-4"
                                >
                                    Reports
                                </AppLink>
                            </div>
                            <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
                                <KpiTile
                                    label="Money taken"
                                    value={money_label(
                                        figures["takings_net_cents"],
                                        figures["currency"]
                                    )}
                                    note="Net, today"
                                    testid="today-net"
                                />
                                <KpiTile
                                    label="Tickets"
                                    value={f"{figures['tickets_sold']}"}
                                    note="For today's showtimes"
                                    testid="today-tickets"
                                />
                                <KpiTile
                                    label="Occupancy"
                                    value={percent(figures["occupancy_pct"])}
                                    note="Today's showtimes"
                                    testid="today-occupancy"
                                />
                                <KpiTile
                                    label="Showtimes"
                                    value={f"{figures['showtimes']}"}
                                    note="Today"
                                    testid="today-showtimes"
                                />
                            </div>
                        </section>}
                    <section aria-labelledby="shows-heading" className={CARD}>
                        <h2 id="shows-heading" className="text-base font-semibold">
                            Today's showtimes
                        </h2>
                        {len(shows) == 0
                            and <p
                                data-testid="home-no-showtimes"
                                className="text-sm text-muted-foreground"
                            >
                                No showtimes today.
                            </p>}
                        {len(shows) > 0
                            and <ul className="flex flex-col">
                                {[
                                    <ShowtimeRow
                                        key={s["screening_id"]}
                                        show={s}
                                        slug={slug}
                                        tz={tz}
                                    /> for s in shows
                                ]}
                            </ul>}
                    </section>
                </div>
                <div className="flex flex-col gap-6">
                    <QuickActions slug={slug} permissions={permissions}/>
                    {got["setup"] is not None
                        and <SetupChecklist setup={got["setup"]} slug={slug}/>}
                    {got["activity"] is not None
                        and <RecentActivity
                            activity={got["activity"]}
                            slug={slug}
                            tz={tz}
                        />}
                </div>
            </div>
        </div>;
}
