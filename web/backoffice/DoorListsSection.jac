"""Door lists (P17.2, core/booking/door_list.jac): every paid ticket of a showtime, to let
people in on paper when the scanner can't reach AfriCinemas.

Today's or tomorrow's showtimes (or any day), each with its PDF and its list on screen;
the day's lists in one PDF. A list is ready from noon the day before; until then the
showtime says when. Download them before doors open: they're needed when we're down.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.booking.door_list {
    door_lists,  # jac:ignore[W2037] authenticated endpoint
    door_list,  # jac:ignore[W2037] authenticated endpoint
    door_list_pdf,  # jac:ignore[W2037] authenticated endpoint
    day_door_lists_pdf  # jac:ignore[W2037] authenticated endpoint
}
import from ..storefront.showtimes { time_label, long_day_label }
import from .ScreeningsSection { today_iso, add_days }
import from .BillingSection { save_pdf }

def TicketRows(listing: any) -> JsxElement {  # jac:ignore[W1037]
    # The list on screen: one row per ticket, then the snacks to collect.
    tz: str = listing["timezone"];
    tickets: list[dict[str, any]] = listing["tickets"];  # jac:ignore[W1037]
    snacks: list[dict[str, any]] = listing["snacks"];  # jac:ignore[W1037]
    return
        <div className="flex flex-col gap-3" data-testid="door-list">
            {len(tickets) == 0
                and <p className="text-sm text-muted-foreground">
                    No tickets sold yet.
                </p>}
            <ul className="divide-y rounded-lg border">
                {[
                    <li
                        key={t["reference"]}
                        data-testid="door-list-ticket"
                        className="flex flex-wrap items-baseline gap-x-4 gap-y-1 px-3 py-2 text-sm"
                    >
                        <span className="w-12 font-semibold tabular-nums">
                            {t["seat"]}
                        </span>
                        <span className="font-mono">{t["reference"]}</span>
                        <span className="text-muted-foreground">
                            {t["ticket_type"]}
                        </span>
                        <span className="text-muted-foreground">
                            {f"M-Pesa {t['code']}"
                                if t["paid_with"] == "M-Pesa"
                                else "Cash"}{f" · phone …{t['phone_end']}"
                                if t["phone_end"]
                                else ""}
                        </span>
                        {t["used_at"]
                            and <span className="text-xs font-medium">
                                {f"Scanned {time_label(t['used_at'], tz)}"}
                            </span>}
                    </li> for t in tickets
                ]}
            </ul>
            {len(snacks) > 0
                and <div className="flex flex-col gap-1">
                    <h4 className="text-sm font-semibold">Snacks to collect</h4>
                    <ul className="divide-y rounded-lg border">
                        {[
                            <li
                                key={s["pickup"]}
                                className="flex flex-wrap gap-x-4 px-3 py-2 text-sm"
                            >
                                <span className="font-mono">{s["pickup"]}</span>
                                <span>{s["items"]}</span>
                                {s["collected"]
                                    and <span className="text-xs font-medium">
                                        Collected
                                    </span>}
                            </li> for s in snacks
                        ]}
                    </ul>
                </div>}
        </div>;
}

def ShowtimeRow(
    show: dict[str, any],  # jac:ignore[W1037]
    slug: str,
    tz: str
) -> JsxElement {
    # One showtime: when, where, its tickets, its PDF and its list on screen.
    [open, set_open] = useState(False);
    [listing, set_listing] = useState(None);
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    ready: bool = show["ready"];
    where = " · ".join(
        [
            x
            for x in [show["screen"], show["venue"]]
            if x
        ]
    );

    async def pdf {
        set_busy(True);
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await door_list_pdf(slug, show["screening_id"]);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("door list PDF failed", e);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem("We couldn't make the PDF. Try again.");
            return;
        }
        save_pdf(got["filename"], got["pdf"]);
    }

    async def toggle {
        if open {
            set_open(False);
            return;
        }
        set_open(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await door_list(slug, show["screening_id"]);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("door list failed", e);
        }
        if got is None or not got["ok"] {
            set_problem("We couldn't load the list. Try again.");
            set_open(False);
            return;
        }
        set_listing(got);
    }

    found: any = listing;  # jac:ignore[W1037]
    return
        <li
            data-testid="door-list-showtime"
            className="flex flex-col gap-3 rounded-lg border bg-card p-3"
        >
            <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex min-w-0 flex-col gap-0.5">
                    <span className="font-medium">
                        {f"{time_label(show['starts_at'], tz)} · {show['movie_title']}"}
                    </span>
                    <span className="text-sm text-muted-foreground">
                        {where}{f" · {show['tickets']} {'ticket'
                            if show['tickets'] == 1
                            else 'tickets'}"
                            if ready
                            else ""}
                    </span>
                    {not ready
                        and <span
                            className="text-sm text-muted-foreground"
                            data-testid="door-list-not-yet"
                        >
                            {f"Ready from {long_day_label(show['opens_at'], tz)} at {time_label(
                                show['opens_at'], tz
                            )}"}
                        </span>}
                </div>
                {ready
                    and <div className="flex gap-2">
                        <Button
                            variant="outline"
                            className="min-h-11"
                            data-testid="door-list-open"
                            aria-expanded={open}
                            onClick={toggle}
                        >
                            {"Hide list" if open else "Show list"}
                        </Button>
                        <Button
                            className="min-h-11"
                            data-testid="door-list-pdf"
                            disabled={busy}
                            onClick={pdf}
                        >
                            {"Making…" if busy else "PDF"}
                        </Button>
                    </div>}
            </div>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
            {open
                and (
                    <TicketRows listing={found}/>
                        if found is not None
                        else <Spinner aria-label="Loading"/>
                )}
        </li>;
}

def:pub DoorListsSection(slug: str, shift_open: bool = True) -> JsxElement {
    [day, set_day] = useState(today_iso());
    [got, set_got] = useState(None);
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);

    async def load {
        set_got(None);
        set_problem("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await door_lists(slug, day);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("door lists failed", e);
        }
        if answer is None or not answer["ok"] {
            set_problem(
                answer["error"]["message"]
                    if answer is not None
                    else "We couldn't load the showtimes. Reload the page to try again."
            );
            return;
        }
        set_got(answer);
    }

    def start {
        load();
    }
    useEffect(start, [slug, day, shift_open]);

    async def whole_day {
        set_busy(True);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await day_door_lists_pdf(slug, day);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("day door lists failed", e);
        }
        set_busy(False);
        if answer is None or not answer["ok"] {
            set_problem(
                answer["error"]["message"]
                    if answer is not None
                    else "We couldn't make the PDF. Try again."
            );
            return;
        }
        save_pdf(answer["filename"], answer["pdf"]);
    }

    today = today_iso();
    days = [(today, "Today"), (add_days(today, 1), "Tomorrow")];
    found: any = got;  # jac:ignore[W1037]
    shows: list[dict[str, any]] = found["showtimes"] if found is not None else [];  # jac:ignore[W1037]
    any_ready = len(
        [
            s
            for s in shows
            if s["ready"]
        ]
    )
        > 0;
    return
        <section className="flex max-w-3xl flex-col gap-4" data-testid="door-lists">
            <p className="text-sm text-muted-foreground">
                Every paid ticket of a showtime, to let people in on paper if the scanner can't reach AfriCinemas. Download today's lists before doors open, and keep them on paper or your phone.
            </p>
            <div className="flex flex-wrap items-center gap-2">
                {[
                    <Button
                        key={d}
                        variant={"default" if day == d else "outline"}
                        className="min-h-11"
                        aria-pressed={day == d}
                        onClick={lambda { set_day(d); }}
                    >
                        {label}
                    </Button> for (d, label) in days
                ]}
                <input
                    type="date"
                    aria-label="Another day"
                    value={day}
                    onChange={lambda (e: any) { set_day(e.target.value or today); }}  # jac:ignore[W1037]
                    className="min-h-11 rounded-md border border-input bg-background px-3 text-sm"
                />
                {any_ready
                    and <Button
                        variant="outline"
                        className="min-h-11"
                        data-testid="door-lists-day-pdf"
                        disabled={busy}
                        onClick={whole_day}
                    >
                        {"Making…" if busy else "The day's lists (PDF)"}
                    </Button>}
            </div>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
            {found is None and not problem and <Spinner aria-label="Loading"/>}
            {found is not None
                and len(shows) == 0
                and <p className="text-sm text-muted-foreground">
                    No showtimes this day.
                </p>}
            <ul className="flex flex-col gap-3">
                {[
                    <ShowtimeRow
                        key={s["screening_id"]}
                        show={s}
                        slug={slug}
                        tz={found["timezone"]}
                    /> for s in shows
                ]}
            </ul>
        </section>;
}
