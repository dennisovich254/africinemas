"""The back office's Overview (P7.4): the first page every member of staff sees.

One request (staff_home) brings what the member's roles allow, for the cinema's today.
The page leads with the movies, as a cinema should:

- a hero for the next showtime: its backdrop (or poster) behind a dark scrim, the title
  in the display face, time, screen and seats sold, and Sell or Scan where allowed;
- today's figures (who reads reports) as compact tiles;
- today's showtimes as poster cards (a row that scrolls on its own on a phone, a grid on
  desktop), each with Sell or Scan;
- a side column of separate tiles: quick actions (from the member's permissions), the
  setup checklist until it's done (who sets the cinema up), recent activity (who reads
  the audit log).

Artwork is decorative (the title is always written) and comes from showtime_art, for
staff, so it shows before the cinema is public too. The hero's background is the
movie's backdrop, or its poster blurred when it has none. Off shift, the page says what
starting one shows. A phone stacks everything, the hero first.
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
import from ...components.ui.spinner { Spinner }
import from core.reporting.staff_home { staff_home }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from .ShowtimeArt { ShowtimeArt }
import from ..shell.AppLink { AppLink }
import from ..storefront.showtimes { time_label }
import from .report_view { day_label, percent, money_label, action_label, result_label }
import from .nav { section_path }

glob TILE: str = "flex flex-col gap-3 rounded-3xl bg-card p-4 ring-1 ring-foreground/10",
     PILL: str = "inline-flex min-h-11 items-center justify-center gap-2 rounded-full px-5 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2";

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

def _next_index(shows: list[dict[str, any]]) -> int {  # jac:ignore[W1037]
    # The next showtime to start; when all have started, the last one.
    at: float = new(Date).getTime();  # jac:ignore[W2001]
    for (i, s) in enumerate(shows) {
        starts: float = new(Date, s["starts_at"]).getTime();  # jac:ignore[W2001]
        if starts >= at {
            return i;
        }
    }
    return len(shows) - 1;
}

def SeatsBar(sold: int, seats: int, light: bool, testid: str = "") -> JsxElement {
    # "34 of 60 sold" with a thin bar; `light` on artwork (white on a dark scrim).
    filled = (sold * 100 / seats) if seats > 0 else 0;
    track = "bg-white/25" if light else "bg-muted";
    fill = "bg-white" if light else "bg-(--chart-bar)";
    return
        <span className="flex items-center gap-2 text-xs tabular-nums">
            <span
                aria-hidden="true"
                className={f"h-1.5 w-full max-w-32 overflow-hidden rounded-full {track}"}
            >
                <span
                    className={f"block h-full rounded-full {fill}"}
                    style={{"width": f"{filled}%"}}
                />
            </span>
            <span data-testid={testid or None} className="whitespace-nowrap">
                {sold} of {seats} sold
            </span>
        </span>;
}

def Hero(
    show: dict[str, any],  # jac:ignore[W1037]
    slug: str,
    tz: str,
    upcoming: bool
) -> JsxElement {
    # The next showtime, big: artwork, title, when and where, seats, Sell or Scan.
    screening_id: str = show["screening_id"];
    has_backdrop: bool = show["has_backdrop"];
    has_poster: bool = show["has_poster"];
    when = time_label(show["starts_at"], tz);
    return
        <section
            aria-labelledby="hero-title"
            data-testid="home-hero"
            className="relative isolate flex min-h-72 items-end overflow-hidden rounded-3xl bg-black"
        >
            {has_backdrop
                and <ShowtimeArt
                    slug={slug}
                    screening_id={screening_id}
                    kind="backdrop"
                    available={True}
                    className="absolute inset-0 -z-20 opacity-70"
                />}
            {not has_backdrop
                and has_poster
                and <ShowtimeArt
                    slug={slug}
                    screening_id={screening_id}
                    kind="poster"
                    available={True}
                    className="absolute inset-0 -z-20 scale-125 opacity-50 blur-2xl"
                />}
            <div
                aria-hidden="true"
                className="absolute inset-0 -z-10 bg-gradient-to-t from-black/90 via-black/60 to-black/20 sm:bg-gradient-to-r sm:from-black/90 sm:via-black/55 sm:to-black/10"
            />
            <div className="flex max-w-xl flex-col gap-3 p-5 text-white sm:p-8">
                <span
                    className="w-fit rounded-full bg-white/15 px-3 py-1 text-xs font-medium ring-1 ring-white/25"
                >
                    {f"Up next · {when}"
                        if upcoming
                        else f"Showing now · started {when}"}
                </span>
                <h2
                    id="hero-title"
                    className="font-display text-4xl uppercase leading-none sm:text-5xl"
                >
                    {show["movie_title"]}
                </h2>
                <p className="text-sm text-white/85">
                    {when} · {show["screen"]} · {show["venue"]}
                </p>
                <SeatsBar
                    sold={int(show["seats_sold"])}
                    seats={int(show["seats_on_sale"])}
                    light={True}
                />
                <div className="mt-1 flex flex-wrap gap-2">
                    {show["can_sell"]
                        and <AppLink
                            to={section_path(slug, "box-office")}
                            testid="hero-sell"
                            className={f"{PILL} bg-white text-black hover:bg-white/90"}
                        >
                            <HugeiconsIcon
                                icon={Ticket01Icon}
                                strokeWidth={2}
                                className="size-4"
                                aria-hidden="true"
                            />
                            Sell tickets
                        </AppLink>}{show["can_scan"]
                        and <AppLink
                            to={section_path(slug, "scanner")}
                            testid="hero-scan"
                            className={f"{PILL} bg-white/15 text-white ring-1 ring-white/30 hover:bg-white/25"}
                        >
                            <HugeiconsIcon
                                icon={QrCodeIcon}
                                strokeWidth={2}
                                className="size-4"
                                aria-hidden="true"
                            />
                            Scan tickets
                        </AppLink>}
                </div>
            </div>
        </section>;
}

def NoShowtimes(slug: str, can_add: bool) -> JsxElement {
    return
        <section
            data-testid="home-no-showtimes"
            className="flex min-h-48 flex-col items-start justify-end gap-3 rounded-3xl bg-card p-6 ring-1 ring-foreground/10 sm:p-8"
        >
            <h2 className="font-display text-3xl uppercase leading-none">
                No showtimes today
            </h2>
            <p className="text-sm text-muted-foreground">
                Today's showtimes appear here, with their seats and the way to sell or scan.
            </p>
            {can_add
                and <AppLink
                    to={section_path(slug, "screenings")}
                    className={f"{PILL} bg-primary text-primary-foreground hover:bg-primary/90"}
                >
                    Add a showtime
                </AppLink>}
        </section>;
}

def Stat(label: str, value: str, testid: str) -> JsxElement {
    return
        <div
            className="flex flex-col gap-1 rounded-2xl bg-card p-4 ring-1 ring-foreground/10"
        >
            <span className="text-xs text-muted-foreground">{label}</span>
            <span
                data-testid={testid}
                className="text-xl font-semibold tabular-nums sm:text-2xl"
            >
                {value}
            </span>
        </div>;
}

def ShowtimeCard(
    show: dict[str, any],  # jac:ignore[W1037]
    slug: str,
    tz: str
) -> JsxElement {
    # A poster card: time and title on the artwork, seats, then Sell or Scan.
    return
        <li
            data-testid="home-showtime"
            className="flex w-40 shrink-0 snap-start flex-col gap-2 sm:w-auto"
        >
            <div className="relative overflow-hidden rounded-2xl bg-black">
                <ShowtimeArt
                    slug={slug}
                    screening_id={show["screening_id"]}
                    kind="poster"
                    available={show["has_poster"]}
                    className="aspect-[2/3]"
                />
                <div
                    className="absolute inset-x-0 bottom-0 flex flex-col gap-1 bg-gradient-to-t from-black/90 via-black/70 to-transparent p-3 pt-10 text-white"
                >
                    <span className="text-lg font-semibold tabular-nums leading-none">
                        {time_label(show["starts_at"], tz)}
                    </span>
                    <span className="truncate text-sm font-medium">
                        {show["movie_title"]}
                    </span>
                    <span className="truncate text-xs text-white/80">
                        {show["screen"]}
                    </span>
                </div>
            </div>
            <SeatsBar
                sold={int(show["seats_sold"])}
                seats={int(show["seats_on_sale"])}
                light={False}
                testid="home-showtime-seats"
            />
            <div className="flex gap-2">
                {show["can_sell"]
                    and <AppLink
                        to={section_path(slug, "box-office")}
                        testid="home-sell"
                        className={f"{PILL} flex-1 bg-primary px-3 text-primary-foreground hover:bg-primary/90"}
                    >
                        Sell
                    </AppLink>}{show["can_scan"]
                    and <AppLink
                        to={section_path(slug, "scanner")}
                        testid="home-scan"
                        className={f"{PILL} flex-1 px-3 ring-1 ring-foreground/15 hover:bg-muted"}
                    >
                        Scan
                    </AppLink>}
            </div>
        </li>;
}

def QuickAction(
    to: str,
    label: str,
    icon: any,  # jac:ignore[W1037]
    testid: str
) -> JsxElement {
    return
        <li>
            <AppLink
                to={to}
                testid={testid}
                className="flex min-h-11 items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium transition-colors hover:bg-muted focus-visible:outline-2"
            >
                <HugeiconsIcon
                    icon={icon}
                    strokeWidth={2}
                    className="size-5 text-muted-foreground"
                    aria-hidden="true"
                />
                {label}
            </AppLink>
        </li>;
}

def QuickActions(slug: str, permissions: list[str]) -> JsxElement {
    # The jobs this member's roles allow.
    actions = [];
    if "bookings.create" in permissions {
        actions.append(
            <QuickAction
                key="sell"
                to={section_path(slug, "box-office")}
                label="Sell tickets"
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
                icon={UserAdd01Icon}
                testid="quick-invite"
            />
        );
    }
    if len(actions) == 0 {
        return <span/>;
    }
    return
        <section aria-labelledby="quick-heading" className={TILE}>
            <h2 id="quick-heading" className="px-3 text-sm font-semibold">
                Quick actions
            </h2>
            <ul className="flex flex-col">{actions}</ul>
        </section>;
}

def SetupChecklist(
    setup: dict[str, any],  # jac:ignore[W1037]
    slug: str
) -> JsxElement {
    # Until every step is done: what's done, and a link to do the rest.
    done = int(setup["done"]);
    total = int(setup["total"]);
    if done >= total {
        return <span/>;
    }
    return
        <section
            aria-labelledby="setup-heading"
            data-testid="setup-checklist"
            className={TILE}
        >
            <div className="flex items-baseline justify-between gap-3 px-3">
                <h2 id="setup-heading" className="text-sm font-semibold">
                    Get your cinema ready
                </h2>
                <span
                    data-testid="setup-progress"
                    className="text-xs text-muted-foreground tabular-nums"
                >
                    {done} of {total} done
                </span>
            </div>
            <span
                aria-hidden="true"
                className="mx-3 h-1.5 overflow-hidden rounded-full bg-muted"
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
                            className="flex min-h-11 items-center gap-3 rounded-xl px-3 py-2 text-sm hover:bg-muted"
                        >
                            <HugeiconsIcon
                                icon={CheckmarkCircle02Icon
                                    if step["done"]
                                    else CircleIcon}
                                strokeWidth={2}
                                className={"size-5 shrink-0 text-primary"
                                    if step["done"]
                                    else "size-5 shrink-0 text-muted-foreground"}
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
            className={TILE}
        >
            <div className="flex items-baseline justify-between gap-3 px-3">
                <h2 id="activity-heading" className="text-sm font-semibold">
                    Recent activity
                </h2>
                <AppLink
                    to={section_path(slug, "audit")}
                    className="inline-flex min-h-11 min-w-11 items-center justify-center px-2 text-xs font-medium text-muted-foreground underline underline-offset-4 hover:text-foreground"
                >
                    See all
                </AppLink>
            </div>
            {len(activity) == 0
                and <p className="px-3 text-sm text-muted-foreground">Nothing yet.</p>}
            <ul className="flex flex-col gap-1">
                {[
                    <li
                        key={e["event_id"]}
                        className="flex items-start gap-3 rounded-xl px-3 py-2"
                    >
                        <span
                            aria-hidden="true"
                            className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg bg-muted text-xs font-semibold tabular-nums"
                        >
                            {time_label(e["at"], tz)[:2]}
                        </span>
                        <span className="flex min-w-0 flex-col">
                            <span className="truncate text-sm font-medium">
                                {action_label(e["action"])}
                            </span>
                            <span className="truncate text-xs text-muted-foreground">
                                {time_label(e["at"], tz)} · {e["actor"]
                                    or "Staff member"}{e["result"] != "ok"
                                    and f" · {result_label(e['result'])}"}
                            </span>
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
    today_text = "";
    if home is not None {
        loaded: dict[str, any] = home;  # jac:ignore[W1037]
        place: dict[str, str] = loaded["cinema"];
        hello = greeting(place["timezone"]);
        today_text = day_label(place["today"]) + " · ";
    }
    header = <div
        className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between"
    >
        <div className="flex flex-col gap-1">
            <p
                data-testid="home-greeting"
                className="font-display text-3xl uppercase leading-none sm:text-4xl"
            >
                {hello}
            </p>
            <p className="text-sm text-muted-foreground">
                {today_text}Signed in as {", ".join(roles)}
            </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
            {shift_open
                and <span
                    data-testid="shift-status"
                    className="inline-flex min-h-11 items-center gap-2 rounded-full bg-card px-4 text-sm ring-1 ring-foreground/10"
                >
                    <span
                        aria-hidden="true"
                        className="size-2 rounded-full bg-emerald-500"
                    />
                    On shift
                </span>}
            <a
                href={f"/c/{slug}"}
                target="_blank"
                rel="noopener"
                className="inline-flex min-h-11 items-center gap-1 rounded-full bg-card px-4 text-sm font-medium ring-1 ring-foreground/10 hover:bg-muted"
            >
                View storefront
                <HugeiconsIcon
                    icon={ArrowUpRight01Icon}
                    strokeWidth={2}
                    className="size-4"
                    aria-hidden="true"
                />
                <span className="sr-only">(opens in a new tab)</span>
            </a>
        </div>
    </div>;

    if not shift_open {
        return
            <div className="mx-auto flex w-full max-w-7xl flex-col gap-6">
                {header}
                <p
                    data-testid="home-off-shift"
                    className="rounded-3xl border border-dashed p-8 text-center text-sm text-muted-foreground"
                >
                    Start your shift to see today's showtimes, sales and your setup steps.
                </p>
            </div>;
    }
    if home is None {
        return
            <div className="mx-auto flex w-full max-w-7xl flex-col gap-6">
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
    has_side = got["setup"] is not None or got["activity"] is not None;
    nxt = _next_index(shows) if len(shows) > 0 else -1;
    upcoming = False;
    if nxt >= 0 {
        first_start: float = new(Date, shows[nxt]["starts_at"]).getTime();  # jac:ignore[W2001]
        upcoming = first_start >= new(Date).getTime();  # jac:ignore[W2001]
    }
    return
        <div className="mx-auto flex w-full max-w-7xl flex-col gap-6">
            {header}
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
                <div className="flex min-w-0 flex-col gap-6">
                    {nxt >= 0
                        and <Hero
                            show={shows[nxt]}
                            slug={slug}
                            tz={tz}
                            upcoming={upcoming}
                        />}{nxt < 0
                        and <NoShowtimes
                            slug={slug}
                            can_add={"showtimes.create" in permissions}
                        />}{figures is not None
                        and <section
                            aria-labelledby="today-heading"
                            className="flex flex-col gap-3"
                        >
                            <div className="flex items-baseline justify-between gap-3">
                                <h2
                                    id="today-heading"
                                    className="text-lg font-semibold"
                                >
                                    Today so far
                                </h2>
                                <AppLink
                                    to={section_path(slug, "reports")}
                                    testid="open-reports"
                                    className="inline-flex min-h-11 min-w-11 items-center justify-center px-2 text-sm font-medium text-muted-foreground underline underline-offset-4 hover:text-foreground"
                                >
                                    Reports
                                </AppLink>
                            </div>
                            <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
                                <Stat
                                    label="Money taken"
                                    value={money_label(
                                        figures["takings_net_cents"],
                                        figures["currency"]
                                    )}
                                    testid="today-net"
                                />
                                <Stat
                                    label="Tickets"
                                    value={f"{figures['tickets_sold']}"}
                                    testid="today-tickets"
                                />
                                <Stat
                                    label="Occupancy"
                                    value={percent(figures["occupancy_pct"])}
                                    testid="today-occupancy"
                                />
                                <Stat
                                    label="Showtimes"
                                    value={f"{figures['showtimes']}"}
                                    testid="today-showtimes"
                                />
                            </div>
                        </section>}{len(shows) > 0
                        and <section
                            aria-labelledby="shows-heading"
                            className="flex min-w-0 flex-col gap-3"
                        >
                            <div className="flex items-baseline justify-between gap-3">
                                <h2
                                    id="shows-heading"
                                    className="text-lg font-semibold"
                                >
                                    Today's showtimes
                                </h2>
                                <span className="text-sm text-muted-foreground">
                                    {len(shows)} today
                                </span>
                            </div>
                            <ul
                                className="-mx-4 flex snap-x gap-4 overflow-x-auto px-4 pb-2 sm:mx-0 sm:grid sm:grid-cols-3 sm:overflow-visible sm:px-0 xl:grid-cols-4"
                            >
                                {[
                                    <ShowtimeCard
                                        key={s["screening_id"]}
                                        show={s}
                                        slug={slug}
                                        tz={tz}
                                    /> for s in shows
                                ]}
                            </ul>
                        </section>}
                </div>
                <aside className="flex flex-col gap-6" aria-label="Shortcuts and setup">
                    <QuickActions slug={slug} permissions={permissions}/>
                    {got["setup"] is not None
                        and <SetupChecklist setup={got["setup"]} slug={slug}/>}
                    {got["activity"] is not None
                        and <RecentActivity
                            activity={got["activity"]}
                            slug={slug}
                            tz={tz}
                        />}
                    {not has_side and <span className="sr-only">No setup steps.</span>}
                </aside>
            </div>
        </div>;
}
