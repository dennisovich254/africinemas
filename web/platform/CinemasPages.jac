"""The platform console's Cinemas section (P13.2): the directory and a cinema's page.

`/cinemas`: every cinema on the platform, newest first, 20 a page, with a search (a
name, a slug or an owner's email; it runs once typing pauses) and a state filter. Each
row opens `/cinemas/<slug>`: the cinema's details, owners, venues and screens, staff
count, tickets sold and takings so far, and its state history. Counts only, never a
customer's details. The server checks every request (core/platform/cinemas_api.jac).
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { CheckmarkBadge01Icon }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.platform.cinemas_api {
    platform_cinemas,  # jac:ignore[W2037] authenticated endpoint
    platform_cinema,  # jac:ignore[W2037]
    platform_approve_cinema  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from ..backoffice.form_parts { on_input }
import from ..backoffice.report_view { money_label }
import from ..site { storefront_address }
import from ..support.HealthPanel { HealthPanel }

glob SEARCH_PAUSE_MS: int = 350,
     OFFLINE: str = "We couldn't reach the server. Check your connection and try again.",
     SELECT_CLASSES: str = "min-h-11 rounded-md border border-input bg-background px-3 text-sm",
     HISTORY_LABELS: dict[str, str] = {
         "signed_up": "Signed up",
         "platform.cinema_approved": "Approved: now public",
         "platform.verification_approved": "Verification approved: now public",
         "platform.verification_changes_requested": "Asked for changes to its verification",
         "platform.verification_rejected": "Verification rejected",
         "platform.verification_file_viewed": "Opened a verification document",
         "platform.support_replied": "We replied to a help request",
         "platform.support_closed": "We closed a help request",
         "platform.support_reopened": "We reopened a help request"
     };

def day_label(at: str) -> str {
    # "12 Oct 2026", or "" when there's no date.
    if not at {
        return "";
    }
    shown: any = new(Date, at);  # jac:ignore[W1037,W2001]
    return shown.toLocaleDateString(
        "en-GB", {"day": "numeric", "month": "short", "year": "numeric"}
    );
}

def CinemaRow(cinema: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    owners: list[str] = cinema["owners"] or [];
    return
        <li data-testid="platform-cinema">
            <AppLink
                to={f"/cinemas/{cinema['slug']}"}
                className="flex min-h-11 flex-col gap-1 p-4 hover:bg-muted sm:flex-row sm:items-center sm:justify-between"
            >
                <span className="flex min-w-0 flex-col gap-0.5">
                    <span className="break-words font-medium">{cinema["name"]}</span>
                    <span className="break-all text-sm text-muted-foreground">
                        {cinema["slug"]}{owners and f" · {', '.join(owners)}"}
                    </span>
                </span>
                <span className="flex shrink-0 flex-wrap items-center gap-3 text-sm">
                    <VerifiedMark cinema={cinema}/>
                    <Badge variant="outline">{cinema["state_label"]}</Badge>
                    <span className="text-muted-foreground">
                        {f"Joined {day_label(cinema['signed_up_at'])}"}
                    </span>
                </span>
            </AppLink>
        </li>;
}

def VerifiedMark(cinema: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    # Verified (with the date it was checked), or waiting for its review (P14.5).
    if cinema["verified_at"] {
        return
            <Badge
                className="gap-1"
                data-testid="cinema-verified"
                title={f"Checked on {cinema['verified_at'][:10]}"}
            >
                <HugeiconsIcon
                    icon={CheckmarkBadge01Icon}
                    size={14}
                    strokeWidth={2}
                    aria-hidden="true"
                />
                Verified
            </Badge>;
    }
    if cinema["verification"] == "submitted" {
        return
            <Badge variant="secondary" data-testid="cinema-waiting">
                Waiting for review
            </Badge>;
    }
    return <span className="hidden"/>;
}

def:pub CinemasList -> JsxElement {
    [typed, set_typed] = useState("");
    [search, set_search] = useState("");
    [state, set_state] = useState("");
    [page, set_page] = useState(1);
    [shown, set_shown] = useState(None);
    [loading, set_loading] = useState(False);
    [problem, set_problem] = useState("");

    async def load(wanted: str, chosen: str, number: int) {
        set_loading(True);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_cinemas(wanted, chosen, str(number));  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_cinemas failed", e);
        }
        set_loading(False);
        if answer is None {
            set_problem(OFFLINE);
            return;
        }
        if not answer["ok"] {
            set_problem(answer["error"]["message"]);
            return;
        }
        set_problem("");
        set_shown(answer);
    }

    def start {
        load(search, state, page);
    }
    useEffect(start, [search, state, page]);

    def wait_for_pause -> any {  # jac:ignore[W1037]
        # The search runs once typing pauses, not on every key.
        win: any = window;  # jac:ignore[W1037,W2001]
        def run {
            if typed.strip() != search {
                set_page(1);
                set_search(typed.strip());
            }
        }
        timer: any = win.setTimeout(run, SEARCH_PAUSE_MS);  # jac:ignore[W1037,W6001] client-only debounce
        return lambda { win.clearTimeout(timer); };  # jac:ignore[W6001]
    }
    useEffect(wait_for_pause, [typed]);

    def pick_state(chosen: str) {
        set_page(1);
        set_state(chosen);
    }

    if shown is None and not problem {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading cinemas…
            </p>;
    }
    nothing = {"cinemas": [], "total": 0, "page": 1, "pages": 1, "states": []};
    found: dict[str, any] = shown or nothing;  # jac:ignore[W1037]
    rows: list[dict[str, any]] = found["cinemas"];  # jac:ignore[W1037]
    states: list[dict[str, str]] = found["states"];
    count: int = found["total"];
    narrowed = search != "" or state != "";
    return
        <div className="flex max-w-4xl flex-col gap-4" data-testid="platform-cinemas">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
                <div className="flex w-full flex-col gap-1.5 sm:w-80">
                    <Label htmlFor="cinema-search">Search</Label>
                    <Input
                        id="cinema-search"
                        type="search"
                        data-testid="cinema-search"
                        value={typed}
                        placeholder="Name, slug or owner's email"
                        onChange={on_input(set_typed)}
                        className="min-h-11"
                    />
                </div>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="cinema-state">State</Label>
                    <select
                        id="cinema-state"
                        data-testid="cinema-state"
                        value={state}
                        onChange={on_input(pick_state)}
                        className={SELECT_CLASSES}
                    >
                        <option value="">All states</option>
                        {[
                            <option key={s["key"]} value={s["key"]}>
                                {s["label"]}
                            </option> for s in states
                        ]}
                    </select>
                </div>
            </div>
            {problem
                and <Alert variant="destructive" role="alert">
                    <AlertDescription>{problem}</AlertDescription>
                </Alert>}
            {len(rows) == 0
                and not problem
                and <p
                    data-testid="cinemas-empty"
                    className="text-sm text-muted-foreground"
                >
                    {"No cinema matches. Try another search or state."
                        if narrowed
                        else "No cinemas have signed up yet."}
                </p>}
            {len(rows) > 0
                and <ul
                    aria-busy={"true" if loading else "false"}
                    className="flex flex-col divide-y rounded-lg border bg-card"
                >
                    {[<CinemaRow key={c["slug"]} cinema={c}/> for c in rows]}
                </ul>}
            {len(rows) > 0
                and <nav
                    aria-label="Cinema pages"
                    className="flex flex-wrap items-center justify-between gap-3"
                >
                    <p
                        className="text-sm text-muted-foreground"
                        data-testid="cinemas-count"
                        aria-live="polite"
                    >
                        {f"{count} {'cinema' if count == 1 else 'cinemas'}"}
                    </p>
                    <div className="flex items-center gap-2">
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            data-testid="cinemas-prev"
                            disabled={loading or found["page"] <= 1}
                            onClick={lambda { set_page(found["page"] - 1); }}
                        >
                            ← Previous
                        </Button>
                        <span className="px-2 text-sm tabular-nums">
                            {f"Page {found['page']} of {found['pages']}"}
                        </span>
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            data-testid="cinemas-next"
                            disabled={loading or found["page"] >= found["pages"]}
                            onClick={lambda { set_page(found["page"] + 1); }}
                        >
                            {loading and <Spinner aria-hidden="true"/>}Next →
                        </Button>
                    </div>
                </nav>}
        </div>;
}

def Figure(label: str, value: str, testid: str = "") -> JsxElement {
    return
        <div className="flex flex-col gap-0.5 rounded-lg border bg-card p-4">
            <span className="text-sm text-muted-foreground">{label}</span>
            <span
                className="text-xl font-semibold tabular-nums"
                data-testid={testid or None}
            >
                {value}
            </span>
        </div>;
}

def:pub CinemaDetail(
    slug: str, audit: bool = False, review: bool = False
) -> JsxElement {
    # `review`: the caller may make a cinema live (P14.1; 14.5 brings the full review).
    # `audit`: the caller reads the platform's audit log, so the page links to this
    # cinema's events there (P13.3).
    [found, set_found] = useState(None);
    [problem, set_problem] = useState("");
    [approving, set_approving] = useState(False);

    async def approve {
        set_approving(True);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_approve_cinema(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_approve_cinema failed", e);
        }
        set_approving(False);
        if answer is None {
            set_problem(OFFLINE);
        } elif not answer["ok"] {
            set_problem(answer["error"]["message"]);
        } else {
            set_found(answer["cinema"]);
        }
    }

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_cinema(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_cinema failed", e);
        }
        if answer is None {
            set_problem(OFFLINE);
        } elif not answer["ok"] {
            set_problem(answer["error"]["message"]);
        } else {
            set_found(answer["cinema"]);
        }
    }

    def start {
        load();
    }
    useEffect(start, [slug]);

    back = <AppLink
        to="/cinemas"
        className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline-offset-4 hover:underline"
    >
        ← All cinemas
    </AppLink>;
    if problem {
        return
            <div className="flex max-w-3xl flex-col gap-4">
                {back}
                <Alert variant="destructive" role="alert">
                    <AlertDescription>{problem}</AlertDescription>
                </Alert>
            </div>;
    }
    if found is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading the cinema…
            </p>;
    }
    cinema: dict[str, any] = found;  # jac:ignore[W1037]
    owners: list[str] = cinema["owners"] or [];
    venues: list[dict[str, any]] = cinema["venues"] or [];  # jac:ignore[W1037]
    history: list[dict[str, str]] = cinema["history"] or [];
    return
        <div
            className="flex max-w-3xl flex-col gap-6"
            data-testid="platform-cinema-page"
        >
            {back}
            <section className="flex flex-col gap-2">
                <h2 className="break-words text-2xl font-semibold">{cinema["name"]}</h2>
                <p
                    className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground"
                >
                    <VerifiedMark cinema={cinema}/>
                    <Badge variant="outline" data-testid="cinema-state-label">
                        {cinema["state_label"]}
                    </Badge>
                    <span className="break-all">{cinema["slug"]}</span>
                    <span>{f"Joined {day_label(cinema['signed_up_at'])}"}</span>
                </p>
                <a
                    href={storefront_address(cinema["slug"])}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline underline-offset-4"
                >
                    Open its storefront
                </a>
                {review
                    and cinema["state"] in ["configuring", "ready_for_go_live"]
                    and <div
                        className="flex flex-col gap-1 rounded-lg border bg-card p-3"
                    >
                        <p className="text-sm">
                            Not public yet: only its team sees its storefront.
                        </p>
                        <Button
                            className="min-h-11 w-fit px-4"
                            disabled={approving}
                            onClick={approve}
                            data-testid="approve-cinema"
                        >
                            {approving
                                and <Spinner
                                    aria-hidden="true"
                                />}Approve: make it public
                        </Button>
                    </div>}
                {review
                    and cinema["verification"] == "submitted"
                    and <AppLink
                        to={f"/reviews/{cinema['slug']}"}
                        testid="review-cinema"
                        className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline underline-offset-4"
                    >
                        It sent its details: review them
                    </AppLink>}
                {audit
                    and <AppLink
                        to={f"/audit?cinema={cinema['slug']}"}
                        className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline underline-offset-4"
                    >
                        The team's actions on it
                    </AppLink>}
            </section>
            <section className="grid gap-3 sm:grid-cols-3" aria-label="So far">
                <Figure
                    label="Tickets sold"
                    value={str(cinema["tickets_sold"])}
                    testid="cinema-tickets"
                />
                <Figure
                    label="Takings"
                    value={money_label(cinema["takings_net_cents"], cinema["currency"])}
                    testid="cinema-takings"
                />
                <Figure
                    label="Staff"
                    value={str(cinema["staff"])}
                    testid="cinema-staff"
                />
            </section>
            {cinema["health"] and <HealthPanel health={cinema["health"]}/>}
            <section className="flex flex-col gap-2 rounded-lg border bg-card p-4">
                <h3 className="font-semibold">Owners</h3>
                {len(owners) == 0
                    and <p className="text-sm text-muted-foreground">
                        No owner's email recorded.
                    </p>}
                <ul className="flex flex-col gap-1">
                    {[
                        <li key={o} className="break-all text-sm">{o}</li>
                        for o in owners
                    ]}
                </ul>
            </section>
            <section className="flex flex-col gap-2 rounded-lg border bg-card p-4">
                <h3 className="font-semibold">Venues and screens</h3>
                {len(venues) == 0
                    and <p className="text-sm text-muted-foreground">No venues yet.</p>}
                <ul className="flex flex-col gap-2" data-testid="cinema-venues">
                    {[
                        <li key={v["name"]} className="text-sm">
                            <span className="font-medium">{v["name"]}</span>
                            {v["city"] and f", {v['city']}"}
                            <span className="block text-muted-foreground">
                                {", ".join(v["screens"])
                                    if v["screens"]
                                    else "No screens yet"}
                            </span>
                        </li> for v in venues
                    ]}
                </ul>
            </section>
            <section className="flex flex-col gap-2 rounded-lg border bg-card p-4">
                <h3 className="font-semibold">History</h3>
                <ol className="flex flex-col gap-2" data-testid="cinema-history">
                    {[
                        <li key={f"{h['at']}-{h['what']}"} className="text-sm">
                            <span className="font-medium">
                                {HISTORY_LABELS.get(h["what"], h["what"])}
                            </span>
                            <span className="text-muted-foreground">
                                {f" · {day_label(h['at'])}"}{h["by"]
                                    and f" · by {h['by']}"}
                            </span>
                            {h["why"]
                                and <span className="block text-muted-foreground">
                                    {h["why"]}
                                </span>}
                        </li> for h in history
                    ]}
                </ol>
            </section>
        </div>;
}
