"""`/app/:slug/screenings`: the programme board and scheduling (P3.7b, improvements #7).

The board shows one venue's day at a time: a strip of dates (two weeks, moved a week at
a time), and under it each screen as a lane with that day's showtimes in time order,
each with its poster, start and end time (running time plus cleaning) and its state,
Draft or On sale. From a showtime: Publish (both server steps, P3.5a/b), Unpublish,
Move (drafts only), Cancel (asked first). "Publish all drafts" puts the day's drafts on
sale.

"Schedule a movie" makes many showtimes at once: a movie, one or more screens, start
times, a date range with chosen weekdays, and "Put on sale now". Before anything is
sent it lists every showtime it will make, flagging those that clash with what's
already on the board (or with each other); then it makes them one by one and says, for
each, whether it was added or why not (a clash, a time in the past, a screen without a
published seat layout). Every check still runs on the server.

Times are entered and shown in the viewer's own time zone and sent with its offset.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.dialog {
    Dialog,
    DialogContent,
    DialogHeader,
    DialogTitle,
    DialogDescription,
    DialogClose
}
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037] authenticated endpoint
import from core.catalog.movie_api {
    list_movies,  # jac:ignore[W2037]
    get_poster  # jac:ignore[W2037]
}
import from core.catalog.screening_api {
    list_screenings,  # jac:ignore[W2037]
    create_screening,  # jac:ignore[W2037]
    reschedule_screening,  # jac:ignore[W2037]
    set_screening_format,  # jac:ignore[W2037]
    schedule_screening,  # jac:ignore[W2037]
    publish_screening,  # jac:ignore[W2037]
    unpublish_screening,  # jac:ignore[W2037]
    cancel_screening  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from .form_parts { FieldError, ConfirmDelete, error_id, on_input, submit_with }
import from .CounterSeatsEditor { ShowtimeCounterSeats }

glob SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm",
     NOT_PUBLISHED: list[str] = ["draft", "scheduled"],
     ON_STOREFRONT: list[str] = ["published", "on_sale", "sales_closed"],
     # The days the strip shows at once, and the most showtimes one scheduling makes.
     STRIP_DAYS: int = 14,
     BATCH_MAX: int = 60,
     # Minutes between showings on a screen (core/catalog/screening_rules.jac).
     CLEANING_MIN: int = 15,
     # (getDay() number, short name), Monday first.
     WEEKDAYS: list[tuple[int, str]] = [
         (1, "Mon"),
         (2, "Tue"),
         (3, "Wed"),
         (4, "Thu"),
         (5, "Fri"),
         (6, "Sat"),
         (0, "Sun")
     ];

def two(n: int) -> str {
    return f"0{n}" if n < 10 else str(n);
}

def:pub local_iso(day: str, clock: str) -> str {
    # "2026-10-02" + "19:30" in this browser's time zone -> "2026-10-02T19:30:00+03:00",
    # or "" when either is missing or invalid.
    if not day or not clock {
        return "";
    }
    moment: any = new(Date, f"{day}T{clock}:00");  # jac:ignore[W1037,W2001]
    if isNaN(moment.getTime()) {  # jac:ignore[W2001]
        return "";
    }
    offset = 0 - moment.getTimezoneOffset();
    sign = "+" if offset >= 0 else "-";
    size = offset if offset >= 0 else 0 - offset;
    hours = int(size / 60);
    return f"{day}T{clock}:00{sign}{two(hours)}:{two(size - hours * 60)}";
}

def:pub day_of(stamp: str) -> str {
    # The local date of an ISO time, as YYYY-MM-DD (for a date input).
    moment: any = new(Date, stamp);  # jac:ignore[W1037,W2001]
    return f"{moment.getFullYear()}-{two(moment.getMonth() + 1)}-{two(
        moment.getDate()
    )}";
}

def:pub clock_of(stamp: str) -> str {
    # The local time of an ISO time, as HH:MM (for a time input and for display).
    moment: any = new(Date, stamp);  # jac:ignore[W1037,W2001]
    return f"{two(moment.getHours())}:{two(moment.getMinutes())}";
}

def:pub counter_release_words(grid: any) -> str {  # jac:ignore[W1037]
    # When a showtime's counter seats go on sale online, or that they have.
    at = clock_of(grid["released_at"]);
    if grid["released"] {
        return f"Released at {at}: unsold counter seats are on sale online. Tick seats to keep them for the counter until the show starts.";
    }
    return f"Unsold counter seats go on sale online at {at}.";
}

def:pub date_label(stamp: str) -> str {
    # "Fri 2 Oct", in the viewer's language.
    moment: any = new(Date, stamp);  # jac:ignore[W1037,W2001]
    return moment.toLocaleDateString(
        [], {"weekday": "short", "day": "numeric", "month": "short"}
    );
}

def:pub state_label(state: str) -> str {
    if state in NOT_PUBLISHED {
        return "Draft";
    }
    if state in ON_STOREFRONT {
        return "On sale";
    }
    if state == "cancelled" {
        return "Cancelled";
    }
    return "Finished";
}

def:pub add_days(day: str, n: int) -> str {
    # "2026-10-02" plus `n` days, as YYYY-MM-DD.
    moment: any = new(Date, f"{day}T12:00:00");  # jac:ignore[W1037,W2001]
    moment.setDate(moment.getDate() + n);
    return f"{moment.getFullYear()}-{two(moment.getMonth() + 1)}-{two(
        moment.getDate()
    )}";
}

def:pub today_iso -> str {
    moment: any = new(Date);  # jac:ignore[W1037,W2001]
    return f"{moment.getFullYear()}-{two(moment.getMonth() + 1)}-{two(
        moment.getDate()
    )}";
}

def:pub weekday_of(day: str) -> int {
    moment: any = new(Date, f"{day}T12:00:00");  # jac:ignore[W1037,W2001]
    return int(moment.getDay());
}

def:pub ms_of(stamp: str) -> float {
    moment: any = new(Date, stamp);  # jac:ignore[W1037,W2001]
    return float(moment.getTime());
}

def:pub clock_after(stamp: str, minutes: int) -> str {
    # The local HH:MM `minutes` after an ISO time.
    moment: any = new(Date, ms_of(stamp) + minutes * 60000);  # jac:ignore[W1037,W2001]
    return f"{two(moment.getHours())}:{two(moment.getMinutes())}";
}

def:pub planned_showtimes(
    from_day: str,
    to_day: str,
    weekdays: list[int],
    screens: list[str],
    times: list[str]
) -> list[dict[str, str]] {
    # Every (day, screen, time) the scheduling form asks for, in day and time order.
    # The weekdays narrow a range of days; one day is that day, whatever they say.
    out: list[dict[str, str]] = [];
    if not from_day or not to_day or to_day < from_day {
        return out;
    }
    day = from_day;
    guard = 0;
    while day <= to_day and guard < 400 {
        if from_day == to_day or weekday_of(day) in weekdays {
            for clock in sorted(times) {
                for screen in screens {
                    starts = local_iso(day, clock);
                    if starts {
                        out.append(
                            {
                                "day": day,
                                "clock": clock,
                                "screen": screen,
                                "starts": starts
                            }
                        );
                    }
                }
            }
        }
        day = add_days(day, 1);
        guard += 1;
    }
    return out;
}

def start_key(s: dict[str, any]) -> str {  # jac:ignore[W1037]
    return s["starts_at"];
}

def:pub timing_of(s: dict[str, any]) -> str {  # jac:ignore[W1037]
    # "showing" from its start to its end, "ended" after, "" before: nothing moves a
    # showtime's state on when it starts, so the board goes by the clock.
    at = Date.now();  # jac:ignore[W2001]
    if new(Date, s["ends_at"]).getTime() <= at {  # jac:ignore[W2001]
        return "ended";
    }
    if new(Date, s["starts_at"]).getTime() <= at {  # jac:ignore[W2001]
        return "showing";
    }
    return "";
}

def StateBadge(state: str, timing: str) -> JsxElement {
    live = state in ON_STOREFRONT and timing != "ended";
    return
        <Badge
            variant={"default" if live else "secondary"}
            data-testid="screening-state"
        >
            {state_label(state)
                if state == "cancelled" or not timing
                else ("Showing now" if timing == "showing" else "Ended")}
        </Badge>;
}

def:pub ScreeningsSection(slug: str) -> JsxElement {
    [venues, set_venues] = useState(None);
    [movies, set_movies] = useState([]);
    [posters, set_posters] = useState({});
    [venue_id, set_venue_id] = useState("");
    # Every screening of the chosen venue, by screen id.
    [shows, set_shows] = useState(None);
    [day, set_day] = useState(today_iso());
    [strip_start, set_strip_start] = useState(today_iso());
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [errors, set_errors] = useState({});
    [message, set_message] = useState("");
    [moving, set_moving] = useState("");
    # The showtime whose counter seats are open (2026-10-30).
    [counter_for, set_counter_for] = useState("");
    [move_to, set_move_to] = useState({"day": "", "clock": ""});
    [confirming, set_confirming] = useState(None);
    # The "Schedule a movie" panel.
    [scheduling, set_scheduling] = useState(False);
    [plan, set_plan] = useState(
        {
            "movie": "",
            "from": "",
            "to": "",
            "clock": "",
            "sell": True,
            "screens": [],
            "times": [],
            "weekdays": [1, 2, 3, 4, 5, 6, 0]
        }
    );
    [results, set_results] = useState([]);

    places: list[dict[str, any]] = venues or [];  # jac:ignore[W1037]
    films: list[dict[str, any]] = movies;  # jac:ignore[W1037]
    pictures: dict[str, str] = posters;
    by_screen: dict[str, list[dict[str, any]]] = shows or {};  # jac:ignore[W1037]
    field_errors: dict[str, str] = errors;
    new_time: dict[str, str] = move_to;
    wanted: dict[str, any] = plan;  # jac:ignore[W1037]
    outcome: list[dict[str, any]] = results;  # jac:ignore[W1037]

    def screens_of(which: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
        for v in places {
            if v["venue_id"] == which {
                return v["auditoriums"];
            }
        }
        return [];
    }

    def film(movie_id: str) -> dict[str, any] | None {  # jac:ignore[W1037]
        for m in films {
            if m["movie_id"] == movie_id {
                return m;
            }
        }
        return None;
    }

    async def load_shows(which: str, from_places: list[dict[str, any]]) {  # jac:ignore[W1037]
        found: dict[str, list[dict[str, any]]] = {};  # jac:ignore[W1037]
        lanes: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for v in from_places {
            if v["venue_id"] == which {
                lanes = v["auditoriums"];
            }
        }
        for a in lanes {
            answer: any = None;  # jac:ignore[W1037]
            try {
                answer = await list_screenings(slug, a["auditorium_id"]);  # jac:ignore[W2037]
            } except Exception as e {
                console.warn("list_screenings failed", e);
                set_failed(
                    "We couldn't load the screenings. Refresh the page to try again."
                );
                return;
            }
            found[a["auditorium_id"]] = answer["screenings"] if answer["ok"] else [];
        }
        set_shows(found);
    }

    async def load_posters(from_films: list[dict[str, any]]) {  # jac:ignore[W1037]
        seen: dict[str, str] = {};
        for m in from_films {
            if m["has_poster"] {
                answer: any = None;  # jac:ignore[W1037]
                try {
                    answer = await get_poster(slug, m["movie_id"]);  # jac:ignore[W2037]
                } except Exception as e {
                    console.warn("get_poster failed", e);
                    continue;
                }
                if answer["ok"] {
                    seen[m["movie_id"]] = f"data:{answer['content_type']};base64,{answer[
                        'data_base64'
                    ]}";
                }
            }
        }
        set_posters(seen);
    }

    async def load {
        got_places: any = None;  # jac:ignore[W1037]
        got_films: any = None;  # jac:ignore[W1037]
        try {
            got_places = await list_venues(slug);  # jac:ignore[W2037]
            got_films = await list_movies(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("loading the programme failed", e);
            set_failed("We couldn't load your screens. Refresh the page to try again.");
            return;
        }
        if not got_places["ok"] {
            set_failed(got_places["error"]["message"]);
            return;
        }
        listed_films = got_films["movies"] if got_films["ok"] else [];
        set_venues(got_places["venues"]);
        set_movies(listed_films);
        first = "";
        for v in got_places["venues"] {
            if not first and len(v["auditoriums"]) > 0 {
                first = v["venue_id"];
            }
        }
        set_venue_id(first);
        await load_shows(first, got_places["venues"]);
        load_posters(listed_films);
    }

    # A named function, not a one-statement lambda (JI-028).
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    async def reload {
        await load_shows(venue_id, places);
    }

    def only_error(field_id: str, text: str) {
        shown: dict[str, str] = {};
        if field_id {
            shown[field_id] = text;
        }
        set_errors(shown);
    }

    def show_day(which: str) {
        set_day(which);
        if which < strip_start or which >= add_days(strip_start, STRIP_DAYS) {
            set_strip_start(which);
        }
        set_moving("");
        set_confirming(None);
    }

    async def choose_venue(which: str) {
        set_venue_id(which);
        set_shows(None);
        set_moving("");
        set_confirming(None);
        set_message("");
        only_error("", "");
        await load_shows(which, places);
    }

    async def step(call: any, where: str, done: str) -> bool {  # jac:ignore[W1037]
        # Runs one change for a showtime; refusals show at `where` (its block).
        answer: any = None;  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        try {
            answer = await call();
        } except Exception as e {
            console.warn("screening change failed", e);
            set_busy(False);
            only_error(
                where, "We couldn't save that. Check your connection and try again."
            );
            return False;
        }
        set_busy(False);
        if not answer["ok"] {
            only_error(where, answer["error"]["message"]);
            return False;
        }
        only_error("", "");
        if done {
            set_message(done);
        }
        return True;
    }

    async def put_on_sale(sid: str, state: str, where: str) -> bool {
        # Both server steps for a draft: scheduled, then published.
        if state == "draft" {
            ok = await step(
                lambda -> any { return schedule_screening(slug, sid); },  # jac:ignore[W1037,W2037]
                where,
                ""
            );
            if not ok {
                return False;
            }
        }
        return await step(
            lambda -> any { return publish_screening(slug, sid); },  # jac:ignore[W1037,W2037]
            where,
            ""
        );
    }

    async def publish(s: dict[str, any]) {  # jac:ignore[W1037]
        sid: str = s["screening_id"];
        if await put_on_sale(sid, s["state"], f"problem-{sid}") {
            set_message("On sale: it's on your storefront now.");
        }
        await reload();
    }

    async def unpublish(sid: str) {
        await step(
            lambda -> any { return unpublish_screening(slug, sid); },  # jac:ignore[W1037,W2037]
            f"problem-{sid}",
            "Taken off sale: it's off your storefront."
        );
        await reload();
    }

    def start_move(s: dict[str, any]) {  # jac:ignore[W1037]
        set_moving(s["screening_id"]);
        set_move_to({"day": day_of(s["starts_at"]), "clock": clock_of(s["starts_at"])});
        set_confirming(None);
        only_error("", "");
    }

    def change_move(key: str, value: str) {
        next_move: dict[str, str] = {};
        for k in new_time {
            next_move[k] = new_time[k];
        }
        next_move[key] = value;
        set_move_to(next_move);
    }

    async def save_move(sid: str) {
        starts = local_iso(new_time["day"], new_time["clock"]);
        field_id = f"move-time-{sid}";
        if not starts {
            only_error(field_id, "Choose a date and a start time.");
            return;
        }
        ok = await step(
            lambda -> any { return reschedule_screening(slug, sid, starts); },  # jac:ignore[W1037,W2037]
            field_id,
            "Moved."
        );
        if ok {
            set_moving("");
            show_day(new_time["day"]);
            await reload();
        }
    }

    async def change_format(sid: str, format: str) {
        if await step(
            lambda -> any { return set_screening_format(slug, sid, format); },  # jac:ignore[W1037,W2037]
            f"problem-{sid}",
            f"Showtime changed to {format}."
        ) {
            await reload();
        }
    }

    async def confirm_cancel {
        target: dict[str, str] = confirming;
        set_confirming(None);
        await step(
            lambda -> any { return cancel_screening(slug, target["id"]); },  # jac:ignore[W1037,W2037]
            f"problem-{target['id']}",
            "Showtime cancelled."
        );
        await reload();
    }

    lanes = screens_of(venue_id);

    def day_shows(screen: str, which: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
        picked: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for s in (by_screen[screen] if screen in by_screen else []) {
            if day_of(s["starts_at"]) == which {
                picked.append(s);
            }
        }
        return sorted(picked, key=start_key);
    }

    def count_on(which: str) -> int {
        n = 0;
        for a in lanes {
            for s in day_shows(a["auditorium_id"], which) {
                if s["state"] != "cancelled" {
                    n += 1;
                }
            }
        }
        return n;
    }

    async def publish_day_drafts {
        failed_any = False;
        for a in lanes {
            for s in day_shows(a["auditorium_id"], day) {
                if s["state"] in NOT_PUBLISHED {
                    ok = await put_on_sale(
                        s["screening_id"], s["state"], f"problem-{s['screening_id']}"
                    );
                    failed_any = failed_any or not ok;
                }
            }
        }
        set_message(
            "Some drafts couldn't go on sale: see below."
                if failed_any
                else "The day's drafts are on sale."
        );
        await reload();
    }

    # --- Schedule a movie ---

    def change_plan(key: str, value: any) {  # jac:ignore[W1037]
        next_plan: dict[str, any] = {};  # jac:ignore[W1037]
        for k in wanted {
            next_plan[k] = wanted[k];
        }
        next_plan[key] = value;
        set_plan(next_plan);
    }

    def toggle(key: str, item: any) {  # jac:ignore[W1037]
        current: list[any] = wanted[key];  # jac:ignore[W1037]
        kept: list[any] = [];  # jac:ignore[W1037]
        found = False;
        for x in current {
            if x == item {
                found = True;
            } else {
                kept.append(x);
            }
        }
        if not found {
            kept.append(item);
        }
        change_plan(key, kept);
    }

    def toggle_sell(e: any) {  # jac:ignore[W1037]
        change_plan("sell", e.target.checked);
    }

    def add_time {
        clock = wanted["clock"];
        if not clock {
            only_error("screening-time", "Choose a start time, then add it.");
            return;
        }
        only_error("", "");
        if clock not in wanted["times"] {
            next_plan: dict[str, any] = {};  # jac:ignore[W1037]
            for k in wanted {
                next_plan[k] = wanted[k];
            }
            next_plan["times"] = sorted(wanted["times"] + [clock]);
            next_plan["clock"] = "";
            set_plan(next_plan);
        }
    }

    def open_scheduling {
        only_error("", "");
        set_results([]);
        set_moving("");
        set_confirming(None);
        single = [a["auditorium_id"] for a in lanes] if len(lanes) == 1 else [];
        set_plan(
            {
                "movie": "",
                "from": day,
                "to": day,
                "clock": "",
                "sell": True,
                "screens": single,
                "times": [],
                "weekdays": [1, 2, 3, 4, 5, 6, 0]
            }
        );
        set_scheduling(True);
    }

    chosen_film = film(wanted["movie"]) if wanted["movie"] else None;
    runtime = int(chosen_film["runtime_minutes"]) if chosen_film is not None else 0;
    planned = planned_showtimes(
        wanted["from"],
        wanted["to"],
        wanted["weekdays"],
        wanted["screens"],
        wanted["times"]
    )
        if scheduling
        else [];

    def screen_name(screen: str) -> str {
        for a in lanes {
            if a["auditorium_id"] == screen {
                return a["name"];
            }
        }
        return "";
    }

    def clash_of(item: dict[str, str], index: int) -> str {
        # What `item` would overlap on its screen: a showing already there, or one
        # planned before it; "" when nothing.
        if runtime == 0 {
            return "";
        }
        start = ms_of(item["starts"]);
        end = start + (runtime + CLEANING_MIN) * 60000;
        for s in (by_screen[item["screen"]] if item["screen"] in by_screen else []) {
            if s["state"] == "cancelled" {
                continue;
            }
            if start < ms_of(s["ends_at"]) and ms_of(s["starts_at"]) < end {
                return f"Clashes with {s['movie_title']} at {clock_of(s['starts_at'])}";
            }
        }
        for (i, other) in enumerate(planned) {
            if i < index and other["screen"] == item["screen"] {
                o_start = ms_of(other["starts"]);
                if start < o_start + (runtime + CLEANING_MIN) * 60000
                    and o_start < end {
                    return f"Overlaps your {other['clock']} showing";
                }
            }
        }
        return "";
    }

    async def schedule {
        if not wanted["movie"] {
            only_error("screening-movie", "Choose a movie.");
            return;
        }
        if len(wanted["screens"]) == 0 {
            only_error("screening-screens", "Choose at least one screen.");
            return;
        }
        if len(wanted["times"]) == 0 {
            only_error("screening-time", "Add at least one start time.");
            return;
        }
        if len(planned) == 0 {
            only_error(
                "screening-date",
                "Choose dates (and weekdays) that include at least one day."
            );
            return;
        }
        if len(planned) > BATCH_MAX {
            only_error(
                "screening-date",
                f"That's {len(planned)} showtimes; schedule up to {BATCH_MAX} at once."
            );
            return;
        }
        only_error("", "");
        set_busy(True);
        set_message("");
        done: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for item in planned {
            label = f"{date_label(item['starts'])} · {item['clock']} · {screen_name(
                item['screen']
            )}";
            answer: any = None;  # jac:ignore[W1037]
            try {
                answer = await create_screening(
                    slug, item["screen"], wanted["movie"], item["starts"]
                );  # jac:ignore[W2037]
            } except Exception as e {
                console.warn("create_screening failed", e);
                done.append(
                    {
                        "label": label,
                        "ok": False,
                        "why": "We couldn't reach the server.",
                        "code": "",
                        "screen": item["screen"]
                    }
                );
                continue;
            }
            if not answer["ok"] {
                done.append(
                    {
                        "label": label,
                        "ok": False,
                        "why": answer["error"]["message"],
                        "code": answer["error"]["code"],
                        "screen": item["screen"]
                    }
                );
                continue;
            }
            sid: str = answer["screening"]["screening_id"];
            note = "Added as a draft";
            if wanted["sell"] {
                note = "Added, on sale"
                    if await put_on_sale(sid, "draft", "")
                    else "Added as a draft (it couldn't go on sale)";
            }
            done.append(
                {
                    "label": label,
                    "ok": True,
                    "why": note,
                    "code": "",
                    "screen": item["screen"]
                }
            );
        }
        set_busy(False);
        only_error("", "");
        set_results(done);
        # The times are used up: left in the form they'd be checked against the
        # showtimes just made, and each would "clash" with itself. The results say what
        # wasn't added, to add again.
        cleared: dict[str, any] = {};  # jac:ignore[W1037]
        for k in wanted {
            cleared[k] = wanted[k];
        }
        cleared["times"] = [];
        set_plan(cleared);
        made = len(
            [
                d
                for d in done
                if d["ok"]
            ]
        );
        set_message(
            f"{made} of {len(done)} showtimes added."
                if made < len(done)
                else f"{made} showtime{'' if made == 1 else 's'} added."
        );
        if made > 0 {
            show_day(wanted["from"]);
        }
        await reload();
    }

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if venues is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading the programme…
            </p>;
    }
    if not venue_id {
        return
            <div className="flex flex-col gap-3 rounded-lg border bg-card p-6">
                <div className="flex flex-col gap-1">
                    <h2 className="text-base font-semibold">No screens yet</h2>
                    <p className="text-sm text-muted-foreground">
                        Showtimes are scheduled on a screen. Add a venue and its screens first.
                    </p>
                </div>
                <Button asChild={True} className="min-h-11 w-fit px-5">
                    <AppLink to={f"/app/{slug}/screens"}>Go to Screens</AppLink>
                </Button>
            </div>;
    }
    asking: dict[str, str] | None = confirming;
    with_screens = [
        v
        for v in places
        if len(v["auditoriums"]) > 0
    ];

    venue_picker = <div
        className="flex flex-wrap gap-2"
        role="group"
        aria-label="Venue"
    >
        {[
            <Button
                key={v["venue_id"]}
                variant={"default" if v["venue_id"] == venue_id else "outline"}
                className="min-h-11"
                aria-pressed={"true" if v["venue_id"] == venue_id else "false"}
                onClick={lambda { choose_venue(v["venue_id"]); }}
            >
                {v["name"]}
            </Button> for v in with_screens
        ]}
    </div>;

    strip_days = [add_days(strip_start, i) for i in range(STRIP_DAYS)];
    strip = <nav aria-label="Days" className="flex items-center gap-2">
        <Button
            variant="outline"
            size="icon"
            className="size-11 shrink-0"
            aria-label="Earlier days"
            onClick={lambda { set_strip_start(add_days(strip_start, -7)); }}
        >
            ‹
        </Button>
        <div className="flex min-w-0 flex-1 gap-2 overflow-x-auto pb-1">
            {[
                <button
                    key={d}
                    type="button"
                    data-day={d}
                    aria-pressed={"true" if d == day else "false"}
                    onClick={lambda { show_day(d); }}
                    className={"flex min-h-14 min-w-16 shrink-0 flex-col items-center justify-center rounded-lg border px-3 text-sm "
                        + (
                            "border-primary bg-primary text-primary-foreground"
                                if d == day
                                else "bg-card hover:bg-muted"
                        )}
                >
                    <span className="font-medium">
                        {"Today" if d == today_iso() else date_label(f"{d}T12:00:00")}
                    </span>
                    <span
                        className={"text-xs "
                            + ("" if d == day else "text-muted-foreground")}
                    >
                        {f"{count_on(d)} shows" if count_on(d) != 1 else "1 show"}
                    </span>
                </button> for d in strip_days
            ]}
        </div>
        <Button
            variant="outline"
            size="icon"
            className="size-11 shrink-0"
            aria-label="Later days"
            onClick={lambda { set_strip_start(add_days(strip_start, 7)); }}
        >
            ›
        </Button>
    </nav>;

    def Block(s: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        sid: str = s["screening_id"];
        state: str = s["state"];
        problem = field_errors[f"problem-{sid}"] or "";
        move_error = field_errors[f"move-time-{sid}"] or "";
        # Once it has started, nothing is left to change.
        timing = timing_of(s);
        live = state in ON_STOREFRONT and not timing;
        open_state = state in NOT_PUBLISHED and not timing;
        poster = pictures[s["movie_id"]] if s["movie_id"] in pictures else "";
        return
            <li
                key={sid}
                data-testid="screening"
                className={"flex flex-col gap-3 rounded-lg border bg-card p-3"
                    + (
                        " opacity-60"
                            if state == "cancelled" or timing == "ended"
                            else ""
                    )}
            >
                <div className="flex gap-3">
                    <span
                        className="aspect-[2/3] w-12 shrink-0 overflow-hidden rounded-md border bg-muted"
                    >
                        {poster
                            and <img
                                src={poster}
                                alt=""
                                className="size-full object-cover"
                            />}
                    </span>
                    <div className="flex min-w-0 flex-1 flex-col gap-1">
                        <div
                            className="flex flex-wrap items-start justify-between gap-2"
                        >
                            <span className="truncate font-medium">
                                {s["movie_title"] or "Movie"}
                            </span>
                            <StateBadge state={state} timing={timing}/>
                        </div>
                        <span className="text-sm tabular-nums text-muted-foreground">
                            {f"{s.get('format', '2D')} · {clock_of(s['starts_at'])} – {clock_of(
                                s['ends_at']
                            )}"}
                        </span>
                    </div>
                </div>
                {(open_state or live)
                    and <div className="flex flex-wrap gap-2">
                        {open_state
                            and <Button
                                className="min-h-11 px-4"
                                disabled={busy}
                                onClick={lambda { publish(s); }}
                            >
                                Publish
                            </Button>}
                        {state != "cancelled"
                            and <Button
                                variant="outline"
                                className="min-h-11 px-4"
                                disabled={busy}
                                onClick={lambda { change_format(
                                    sid, "2D" if s.get("format", "2D") == "3D" else "3D"
                                ); }}
                            >
                                {f"Change to {'2D'
                                    if s.get('format', '2D') == '3D'
                                    else '3D'}"}
                            </Button>}
                        {live
                            and <Button
                                variant="outline"
                                className="min-h-11 px-4"
                                disabled={busy}
                                onClick={lambda { unpublish(sid); }}
                            >
                                Unpublish
                            </Button>}
                        {open_state
                            and moving != sid
                            and <Button
                                variant="outline"
                                className="min-h-11 px-4"
                                disabled={busy}
                                onClick={lambda { start_move(s); }}
                            >
                                Move
                            </Button>}
                        <Button
                            variant="outline"
                            className="min-h-11 px-4"
                            data-testid="showtime-counter-seats"
                            onClick={lambda { set_counter_for(
                                "" if counter_for == sid else sid
                            ); }}
                        >
                            Counter seats
                        </Button>
                        <Button
                            variant="ghost"
                            className="min-h-11 px-4"
                            disabled={busy}
                            onClick={lambda {
                                set_confirming({"id": sid, "title": s["movie_title"]});
                                set_moving("");
                            }}
                        >
                            Cancel screening
                        </Button>
                    </div>}
                <Dialog
                    open={counter_for == sid}
                    onOpenChange={lambda (o: bool) { set_counter_for(
                        sid if o else ""
                    ); }}
                >
                    <DialogContent data-testid="showtime-counter-dialog">
                        <DialogHeader>
                            <DialogTitle>Counter seats</DialogTitle>
                            <DialogDescription>
                                {f"{s['movie_title'] or 'Movie'} · {s.get(
                                    'format', '2D'
                                )} · {clock_of(s['starts_at'])}"}
                            </DialogDescription>
                        </DialogHeader>
                        {counter_for == sid
                            and <ShowtimeCounterSeats
                                slug={slug}
                                screening_id={sid}
                                release_words={counter_release_words}
                            />}
                        <div className="flex justify-end">
                            <DialogClose asChild={True}>
                                <Button variant="outline" className="min-h-11 px-4">
                                    Done
                                </Button>
                            </DialogClose>
                        </div>
                    </DialogContent>
                </Dialog>
                {moving == sid
                    and <form
                        className="grid gap-3 rounded-lg border p-3 sm:grid-cols-2"
                        noValidate={True}
                        onSubmit={submit_with(lambda { save_move(sid); })}
                    >
                        <div className="flex flex-col gap-1.5">
                            <Label htmlFor={f"move-date-{sid}"}>New date</Label>
                            <Input
                                id={f"move-date-{sid}"}
                                type="date"
                                value={new_time["day"]}
                                onChange={on_input(
                                    lambda (text: str) { change_move("day", text); }
                                )}
                                className="min-h-11"
                            />
                        </div>
                        <div className="flex flex-col gap-1.5">
                            <Label htmlFor={f"move-time-{sid}"}>New start time</Label>
                            <Input
                                id={f"move-time-{sid}"}
                                type="time"
                                value={new_time["clock"]}
                                aria-invalid={"true" if move_error else "false"}
                                aria-describedby={error_id(f"move-time-{sid}")
                                    if move_error
                                    else None}
                                onChange={on_input(
                                    lambda (text: str) { change_move("clock", text); }
                                )}
                                className="min-h-11"
                            />
                        </div>
                        {move_error
                            and <div className="sm:col-span-2">
                                <FieldError
                                    field_id={f"move-time-{sid}"}
                                    error={move_error}
                                />
                            </div>}
                        <div className="flex flex-wrap gap-3 sm:col-span-2">
                            <Button
                                type="submit"
                                className="min-h-11 px-5"
                                disabled={busy}
                            >
                                Save time
                            </Button>
                            <Button
                                type="button"
                                variant="ghost"
                                className="min-h-11 px-5"
                                onClick={lambda {
                                    set_moving("");
                                    only_error("", "");
                                }}
                            >
                                Keep the time
                            </Button>
                        </div>
                    </form>}
                {asking is not None
                    and asking["id"] == sid
                    and <ConfirmDelete
                        question={f"Cancel {asking['title']} on {date_label(
                            s['starts_at']
                        )} at {clock_of(s['starts_at'])}?"}
                        detail="It comes off your storefront and can't be scheduled again. Schedule a new showtime instead if you need one."
                        confirm_label="Cancel screening"
                        cancel_label="Keep it"
                        on_confirm={confirm_cancel}
                        on_cancel={lambda { set_confirming(None); }}
                        busy={busy}
                    />}
                {problem and <FieldError field_id={f"problem-{sid}"} error={problem}/>}
            </li>;
    }

    drafts_today = 0;
    for a in lanes {
        for s in day_shows(a["auditorium_id"], day) {
            if s["state"] in NOT_PUBLISHED {
                drafts_today += 1;
            }
        }
    }

    board = <section
        aria-labelledby="board-heading"
        data-testid="programme-board"
        className="flex flex-col gap-4"
    >
        <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 id="board-heading" className="text-lg font-semibold">
                {"Today" if day == today_iso() else date_label(f"{day}T12:00:00")}
            </h2>
            {drafts_today > 0
                and <Button
                    variant="outline"
                    className="min-h-11"
                    data-testid="publish-day"
                    disabled={busy}
                    onClick={publish_day_drafts}
                >
                    Publish all drafts ({drafts_today})
                </Button>}
        </div>
        {shows is None
            and <p
                role="status"
                className="flex items-center gap-2 text-muted-foreground"
            >
                <Spinner aria-hidden="true"/>
                Loading showtimes…
            </p>}
        {shows is not None
            and <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                {[
                    <section
                        key={a["auditorium_id"]}
                        aria-labelledby={f"lane-{a['auditorium_id']}"}
                        data-testid="screen-lane"
                        className="flex flex-col gap-3 rounded-xl bg-muted/40 p-3"
                    >
                        <h3 id={f"lane-{a['auditorium_id']}"} className="font-semibold">
                            {a["name"]}
                        </h3>
                        {len(day_shows(a["auditorium_id"], day)) == 0
                            and <p className="text-sm text-muted-foreground">
                                Nothing on {a["name"]} this day
                            </p>}
                        {len(day_shows(a["auditorium_id"], day)) > 0
                            and <ul className="flex flex-col gap-3">
                                {[Block(s) for s in day_shows(a["auditorium_id"], day)]}
                            </ul>}
                    </section> for a in lanes
                ]}
            </div>}
    </section>;

    movie_error = field_errors["screening-movie"] or "";
    screens_error = field_errors["screening-screens"] or "";
    time_error = field_errors["screening-time"] or "";
    date_error = field_errors["screening-date"] or "";
    clashing = 0;
    for (i, item) in enumerate(planned) {
        if clash_of(item, i) {
            clashing += 1;
        }
    }

    panel = <form
        data-testid="add-screening"
        className="flex flex-col gap-5 rounded-xl border bg-card p-5"
        noValidate={True}
        onSubmit={submit_with(lambda { schedule(); })}
    >
        <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-lg font-semibold">Schedule a movie</h2>
            <Button
                type="button"
                variant="ghost"
                className="min-h-11"
                onClick={lambda {
                    set_scheduling(False);
                    only_error("", "");
                    set_results([]);
                }}
            >
                Close
            </Button>
        </div>
        <div className="grid gap-5 lg:grid-cols-2">
            <div className="flex flex-col gap-5">
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="screening-movie">Movie</Label>
                    <div className="flex items-center gap-3">
                        <span
                            className="aspect-[2/3] w-12 shrink-0 overflow-hidden rounded-md border bg-muted"
                        >
                            {chosen_film is not None
                                and chosen_film["movie_id"] in pictures
                                and <img
                                    src={pictures[chosen_film["movie_id"]]}
                                    alt=""
                                    className="size-full object-cover"
                                />}
                        </span>
                        <select
                            id="screening-movie"
                            value={wanted["movie"]}
                            autoFocus={True}
                            aria-invalid={"true" if movie_error else "false"}
                            aria-describedby={error_id("screening-movie")
                                if movie_error
                                else None}
                            onChange={on_input(
                                lambda (text: str) { change_plan("movie", text); }
                            )}
                            className={SELECT_CLASSES}
                        >
                            <option value="">Choose a movie</option>
                            {[
                                <option key={m["movie_id"]} value={m["movie_id"]}>
                                    {m["title"]} ({m["runtime_minutes"]} min)
                                </option> for m in films
                            ]}
                        </select>
                    </div>
                    {movie_error
                        and <FieldError
                            field_id="screening-movie"
                            error={movie_error}
                        />}
                    {len(films) == 0
                        and <p className="text-sm text-muted-foreground">
                            No movies yet.{" "}
                            <AppLink
                                to={f"/app/{slug}/movies/new"}
                                className="inline-flex min-h-11 items-center font-medium underline underline-offset-4"
                            >
                                Add one
                            </AppLink>
                        </p>}
                </div>
                <fieldset className="flex flex-col gap-2">
                    <legend className="mb-1.5 text-sm font-medium">Screens</legend>
                    <div className="flex flex-wrap gap-2">
                        {[
                            <label
                                key={a["auditorium_id"]}
                                className="flex min-h-11 cursor-pointer items-center gap-2 rounded-md border px-3 text-sm has-[:checked]:border-primary has-[:checked]:bg-primary/10"
                            >
                                <input
                                    type="checkbox"
                                    data-screen={a["auditorium_id"]}
                                    checked={a["auditorium_id"] in wanted["screens"]}
                                    onChange={lambda { toggle(
                                        "screens", a["auditorium_id"]
                                    ); }}
                                    className="size-4"
                                />
                                {a["name"]}
                            </label> for a in lanes
                        ]}
                    </div>
                    {screens_error
                        and <FieldError
                            field_id="screening-screens"
                            error={screens_error}
                        />}
                </fieldset>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="screening-time">Start times</Label>
                    <div className="flex gap-2">
                        <Input
                            id="screening-time"
                            type="time"
                            value={wanted["clock"]}
                            aria-invalid={"true" if time_error else "false"}
                            aria-describedby={error_id("screening-time")
                                if time_error
                                else None}
                            onChange={on_input(
                                lambda (text: str) { change_plan("clock", text); }
                            )}
                            onKeyDown={lambda (e: any) { if e.key == "Enter" {  # jac:ignore[W1037]
                                e.preventDefault();
                                add_time();
                            }}}
                            className="min-h-11 w-36"
                        />
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11"
                            data-testid="add-time"
                            onClick={add_time}
                        >
                            Add time
                        </Button>
                    </div>
                    {len(wanted["times"]) > 0
                        and <ul
                            className="flex flex-wrap gap-2"
                            aria-label="Chosen start times"
                        >
                            {[
                                <li key={t}>
                                    <Button
                                        type="button"
                                        variant="secondary"
                                        className="min-h-11 gap-2 tabular-nums"
                                        aria-label={f"Remove {t}"}
                                        onClick={lambda { toggle("times", t); }}
                                    >
                                        {t}{" "}
                                        <span aria-hidden="true">×</span>
                                    </Button>
                                </li> for t in wanted["times"]
                            ]}
                        </ul>}
                    {time_error
                        and <FieldError field_id="screening-time" error={time_error}/>}
                </div>
            </div>
            <div className="flex flex-col gap-5">
                <div className="grid gap-3 sm:grid-cols-2">
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="screening-date">From</Label>
                        <Input
                            id="screening-date"
                            type="date"
                            value={wanted["from"]}
                            aria-invalid={"true" if date_error else "false"}
                            aria-describedby={error_id("screening-date")
                                if date_error
                                else None}
                            onChange={on_input(
                                lambda (text: str) {
                                    next_plan: dict[str, any] = {};  # jac:ignore[W1037]
                                    for k in wanted {
                                        next_plan[k] = wanted[k];
                                    }
                                    next_plan["from"] = text;
                                    if not wanted["to"] or wanted["to"] < text {
                                        next_plan["to"] = text;
                                    }
                                    set_plan(next_plan);
                                }
                            )}
                            className="min-h-11"
                        />
                    </div>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="screening-until">Until</Label>
                        <Input
                            id="screening-until"
                            type="date"
                            value={wanted["to"]}
                            onChange={on_input(
                                lambda (text: str) { change_plan("to", text); }
                            )}
                            className="min-h-11"
                        />
                    </div>
                </div>
                {date_error
                    and <FieldError field_id="screening-date" error={date_error}/>}
                {wanted["from"] != wanted["to"]
                    and <fieldset
                        className="flex flex-col gap-2"
                        data-testid="weekdays"
                    >
                        <legend className="mb-1.5 text-sm font-medium">
                            On these days between them
                        </legend>
                        <div className="flex flex-wrap gap-2">
                            {[
                                <label
                                    key={n}
                                    className="flex min-h-11 min-w-14 cursor-pointer items-center justify-center gap-2 rounded-md border px-3 text-sm has-[:checked]:border-primary has-[:checked]:bg-primary/10"
                                >
                                    <input
                                        type="checkbox"
                                        data-weekday={n}
                                        checked={n in wanted["weekdays"]}
                                        onChange={lambda { toggle("weekdays", n); }}
                                        className="size-4"
                                    />
                                    {name}
                                </label> for (n, name) in WEEKDAYS
                            ]}
                        </div>
                    </fieldset>}
                <label
                    className="flex min-h-11 cursor-pointer items-center gap-3 text-sm"
                >
                    <input
                        id="sell-now"
                        type="checkbox"
                        checked={wanted["sell"]}
                        onChange={toggle_sell}
                        className="size-4"
                    />
                    Put on sale now (on your storefront at once)
                </label>
            </div>
        </div>
        <section
            aria-labelledby="schedule-preview-heading"
            data-testid="schedule-preview"
            className="flex flex-col gap-2 rounded-lg bg-muted/40 p-4"
        >
            <h3 id="schedule-preview-heading" className="font-semibold">
                {f"{len(planned)} showtime{'' if len(planned) == 1 else 's'}"}{clashing
                    > 0
                    and f" · {clashing} clash{'' if clashing == 1 else 'es'}"}
            </h3>
            {len(planned) == 0
                and <p className="text-sm text-muted-foreground">
                    Choose a movie, screens, start times and days: every showtime appears here before anything is saved.
                </p>}
            {len(planned) > 0
                and <ul
                    className="flex max-h-64 flex-col gap-1 overflow-y-auto text-sm"
                >
                    {[
                        <li
                            key={f"{item['starts']}-{item['screen']}"}
                            data-testid="planned"
                            className="flex flex-wrap justify-between gap-2 tabular-nums"
                        >
                            <span>
                                {date_label(item["starts"])} · {item["clock"]}{runtime
                                    > 0
                                    and f"–{clock_after(
                                        item['starts'], runtime + CLEANING_MIN
                                    )}"} · {screen_name(item["screen"])}
                            </span>
                            {clash_of(item, i)
                                and <span className="font-medium text-destructive">
                                    {clash_of(item, i)}
                                </span>}
                        </li> for (i, item) in enumerate(planned)
                    ]}
                </ul>}
        </section>
        <div className="flex flex-wrap items-center gap-3">
            <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                {busy and <Spinner aria-hidden="true"/>}{f"Schedule {len(
                    planned
                )} showtime{'' if len(planned) == 1 else 's'}"
                    if len(planned) > 0
                    else "Schedule showtimes"}
            </Button>
        </div>
        {len(outcome) > 0
            and <section
                aria-labelledby="schedule-results-heading"
                data-testid="schedule-results"
                className="flex flex-col gap-2"
            >
                <h3 id="schedule-results-heading" className="font-semibold">
                    What happened
                </h3>
                <ul className="flex flex-col gap-2 text-sm">
                    {[
                        <li
                            key={f"{r['label']}-{i}"}
                            data-testid="schedule-result"
                            data-ok={"true" if r["ok"] else "false"}
                            role={"status" if r["ok"] else "alert"}
                            className={"flex flex-col gap-1 rounded-md border p-2 "
                                + ("" if r["ok"] else "border-destructive/50")}
                        >
                            <span className="font-medium">{r["label"]}</span>
                            <span className={"" if r["ok"] else "text-destructive"}>
                                {r["why"]}
                            </span>
                            {r["code"] == "no_layout"
                                and <AppLink
                                    to={f"/app/{slug}/screens/{r['screen']}"}
                                    className="inline-flex min-h-11 items-center font-medium underline underline-offset-4"
                                >
                                    Open {screen_name(r["screen"])}'s seat layout
                                </AppLink>}
                        </li> for (i, r) in enumerate(outcome)
                    ]}
                </ul>
            </section>}
    </form>;

    return
        <div className="flex flex-col gap-6" data-testid="screenings-page">
            <div className="flex flex-wrap items-center justify-between gap-4">
                {len(with_screens) > 1 and venue_picker}{not scheduling
                    and <Button
                        className="min-h-11 w-fit px-5"
                        onClick={open_scheduling}
                    >
                        Schedule a movie
                    </Button>}
            </div>
            <p role="status" aria-live="polite" className="text-sm empty:hidden">
                {message}
            </p>
            {scheduling and panel}
            {strip}
            {board}
        </div>;
}
