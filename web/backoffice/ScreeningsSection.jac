"""`/app/:slug/screenings`: the screenings programme, one screen at a time (P3.7b).

Pick a screen, then add screenings (a movie and a start time; the form opens from "Add
screening"), publish them to the storefront, unpublish, move and cancel them (asked
first). The server's draft and scheduled states are both shown as "Not published", and
Publish makes both steps (P3.5a/b). Times are entered and shown in the viewer's own time
zone and sent with its offset. Refusals (a clash, a time in the past, a screen without a
published seat layout) are shown where they apply.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from core.catalog.movie_api { list_movies }  # jac:ignore[W2037]
import from core.catalog.screening_api {
    list_screenings,  # jac:ignore[W2037]
    create_screening,  # jac:ignore[W2037]
    reschedule_screening,  # jac:ignore[W2037]
    schedule_screening,  # jac:ignore[W2037]
    publish_screening,  # jac:ignore[W2037]
    unpublish_screening,  # jac:ignore[W2037]
    cancel_screening  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from .form_parts { FieldError, ConfirmDelete, error_id, on_input, submit_with }

glob SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm",
     NOT_PUBLISHED: list[str] = ["draft", "scheduled"],
     ON_STOREFRONT: list[str] = ["published", "on_sale", "sales_closed"],
     TIME_CODES: list[str] = ["overlap", "in_past", "invalid_time", "screen_busy"];

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

def:pub date_label(stamp: str) -> str {
    # "Fri 2 Oct", in the viewer's language.
    moment: any = new(Date, stamp);  # jac:ignore[W1037,W2001]
    return moment.toLocaleDateString(
        [], {"weekday": "short", "day": "numeric", "month": "short"}
    );
}

def:pub state_label(state: str) -> str {
    if state in NOT_PUBLISHED {
        return "Not published";
    }
    if state in ON_STOREFRONT {
        return "On the storefront";
    }
    if state == "cancelled" {
        return "Cancelled";
    }
    return "Finished";
}

def:pub ScreeningsSection(slug: str) -> JsxElement {
    [venues, set_venues] = useState(None);
    [movies, set_movies] = useState([]);
    [screen_id, set_screen_id] = useState("");
    [screenings, set_screenings] = useState(None);
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [errors, set_errors] = useState({});
    [message, set_message] = useState("");
    [adding, set_adding] = useState(False);
    [form, set_form] = useState({"movie": "", "day": "", "clock": ""});
    [layout_problem, set_layout_problem] = useState("");
    [moving, set_moving] = useState("");
    [move_to, set_move_to] = useState({"day": "", "clock": ""});
    [confirming, set_confirming] = useState(None);

    async def load_screenings(which: str) {
        answer: any = None;  # jac:ignore[W1037]
        if not which {
            set_screenings([]);
            return;
        }
        try {
            answer = await list_screenings(slug, which);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_screenings failed", e);
            set_failed(
                "We couldn't load the screenings. Refresh the page to try again."
            );
            return;
        }
        if answer["ok"] {
            set_screenings(answer["screenings"]);
        } else {
            set_failed(answer["error"]["message"]);
        }
    }

    async def load {
        places: any = None;  # jac:ignore[W1037]
        films: any = None;  # jac:ignore[W1037]
        try {
            places = await list_venues(slug);  # jac:ignore[W2037]
            films = await list_movies(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("loading the programme failed", e);
            set_failed("We couldn't load your screens. Refresh the page to try again.");
            return;
        }
        if not places["ok"] {
            set_failed(places["error"]["message"]);
            return;
        }
        set_venues(places["venues"]);
        set_movies(films["movies"] if films["ok"] else []);
        first = "";
        for v in places["venues"] {
            for a in v["auditoriums"] {
                if not first {
                    first = a["auditorium_id"];
                }
            }
        }
        set_screen_id(first);
        await load_screenings(first);
    }

    # A named function, not a one-statement lambda (JI-028).
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    field_errors: dict[str, str] = errors;
    values: dict[str, str] = form;
    new_time: dict[str, str] = move_to;

    def only_error(field_id: str, text: str) {
        shown: dict[str, str] = {};
        if field_id {
            shown[field_id] = text;
        }
        set_errors(shown);
    }

    def change(key: str, value: str) {
        next_form: dict[str, str] = {};
        for k in values {
            next_form[k] = values[k];
        }
        next_form[key] = value;
        set_form(next_form);
    }

    def change_move(key: str, value: str) {
        next_move: dict[str, str] = {};
        for k in new_time {
            next_move[k] = new_time[k];
        }
        next_move[key] = value;
        set_move_to(next_move);
    }

    async def choose_screen(which: str) {
        set_screen_id(which);
        set_adding(False);
        set_moving("");
        set_confirming(None);
        set_message("");
        set_layout_problem("");
        only_error("", "");
        set_screenings(None);
        await load_screenings(which);
    }

    async def step(call: any, where: str, done: str) -> bool {  # jac:ignore[W1037]
        # Runs one change for a screening; refusals show at `where` (its row).
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

    async def add {
        movie_id = values["movie"];
        starts = local_iso(values["day"], values["clock"]);
        answer: any = None;  # jac:ignore[W1037]
        set_layout_problem("");
        if not movie_id {
            only_error("screening-movie", "Choose a movie.");
            return;
        }
        if not starts {
            only_error("screening-time", "Choose a date and a start time.");
            return;
        }
        set_busy(True);
        try {
            answer = await create_screening(slug, screen_id, movie_id, starts);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("create_screening failed", e);
            set_busy(False);
            set_message(
                "We couldn't add the screening. Check your connection and try again."
            );
            return;
        }
        set_busy(False);
        if not answer["ok"] {
            code = answer["error"]["code"];
            if code in TIME_CODES {
                only_error("screening-time", answer["error"]["message"]);
            } elif code == "no_layout" {
                only_error("", "");
                set_layout_problem(answer["error"]["message"]);
            } else {
                only_error("", "");
                set_message(answer["error"]["message"]);
            }
            return;
        }
        only_error("", "");
        set_adding(False);
        set_form({"movie": "", "day": "", "clock": ""});
        set_message("Screening added. Publish it when you're ready to sell tickets.");
        await load_screenings(screen_id);
    }

    async def publish(s: dict[str, any]) {  # jac:ignore[W1037]
        sid: str = s["screening_id"];
        where = f"problem-{sid}";
        if s["state"] == "draft" {
            ok = await step(
                lambda -> any { return schedule_screening(slug, sid); },  # jac:ignore[W1037,W2037]
                where,
                ""
            );
            if not ok {
                return;
            }
        }
        await step(
            lambda -> any { return publish_screening(slug, sid); },  # jac:ignore[W1037,W2037]
            where,
            "Published: it's on your storefront now."
        );
        await load_screenings(screen_id);
    }

    async def unpublish(sid: str) {
        await step(
            lambda -> any { return unpublish_screening(slug, sid); },  # jac:ignore[W1037,W2037]
            f"problem-{sid}",
            "Unpublished: it's off your storefront."
        );
        await load_screenings(screen_id);
    }

    def start_move(s: dict[str, any]) {  # jac:ignore[W1037]
        set_moving(s["screening_id"]);
        set_move_to({"day": day_of(s["starts_at"]), "clock": clock_of(s["starts_at"])});
        set_confirming(None);
        only_error("", "");
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
            await load_screenings(screen_id);
        }
    }

    async def confirm_cancel {
        target: dict[str, str] = confirming;
        set_confirming(None);
        await step(
            lambda -> any { return cancel_screening(slug, target["id"]); },  # jac:ignore[W1037,W2037]
            f"problem-{target['id']}",
            "Screening cancelled."
        );
        await load_screenings(screen_id);
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
    places: list[dict[str, any]] = venues;  # jac:ignore[W1037]
    films: list[dict[str, any]] = movies;  # jac:ignore[W1037]
    screen_name = "";
    for v in places {
        for a in v["auditoriums"] {
            if a["auditorium_id"] == screen_id {
                screen_name = a["name"];
            }
        }
    }
    if not screen_id {
        return
            <div className="flex flex-col gap-3 rounded-lg border bg-card p-6">
                <div className="flex flex-col gap-1">
                    <h2 className="text-base font-semibold">No screens yet</h2>
                    <p className="text-sm text-muted-foreground">
                        Screenings are scheduled on a screen. Add a venue and its screens first.
                    </p>
                </div>
                <Button asChild={True} className="min-h-11 w-fit px-5">
                    <AppLink to={f"/app/{slug}/screens"}>Go to Screens</AppLink>
                </Button>
            </div>;
    }
    asking: dict[str, str] | None = confirming;
    time_error = field_errors["screening-time"] or "";
    movie_error = field_errors["screening-movie"] or "";

    picker = <div className="flex max-w-md flex-col gap-1.5">
        <Label htmlFor="screening-screen">Screen</Label>
        <select
            id="screening-screen"
            value={screen_id}
            onChange={on_input(lambda (text: str) { choose_screen(text); })}
            className={SELECT_CLASSES}
        >
            {[
                <optgroup key={v["venue_id"]} label={v["name"]}>
                    {[
                        <option key={a["auditorium_id"]} value={a["auditorium_id"]}>
                            {a["name"]}
                        </option> for a in v["auditoriums"]
                    ]}
                </optgroup> for v in places
            ]}
        </select>
    </div>;

    add_form = <form
        data-testid="add-screening"
        className="grid gap-3 rounded-lg border p-4 sm:grid-cols-3"
        noValidate={True}
        onSubmit={submit_with(lambda { add(); })}
    >
        <h2 className="text-lg font-semibold sm:col-span-3">
            Add a screening on {screen_name}
        </h2>
        {layout_problem
            and <Alert variant="destructive" role="alert" className="sm:col-span-3">
                <AlertTitle>{layout_problem}</AlertTitle>
                <AlertDescription>
                    <AppLink
                        to={f"/app/{slug}/screens/{screen_id}"}
                        className="inline-flex min-h-11 items-center font-medium underline underline-offset-4"
                    >
                        Open {screen_name}'s seat layout
                    </AppLink>
                </AlertDescription>
            </Alert>}
        <div className="flex flex-col gap-1.5 sm:col-span-3">
            <Label htmlFor="screening-movie">Movie</Label>
            <select
                id="screening-movie"
                value={values["movie"]}
                autoFocus={True}
                aria-invalid={"true" if movie_error else "false"}
                aria-describedby={error_id("screening-movie") if movie_error else None}
                onChange={on_input(lambda (text: str) { change("movie", text); })}
                className={SELECT_CLASSES}
            >
                <option value="">Choose a movie</option>
                {[
                    <option key={m["movie_id"]} value={m["movie_id"]}>
                        {m["title"]} ({m["runtime_minutes"]} min)
                    </option> for m in films
                ]}
            </select>
            {movie_error
                and <FieldError field_id="screening-movie" error={movie_error}/>}
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
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="screening-date">Date</Label>
            <Input
                id="screening-date"
                type="date"
                value={values["day"]}
                onChange={on_input(lambda (text: str) { change("day", text); })}
                className="min-h-11"
            />
        </div>
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="screening-time">Start time</Label>
            <Input
                id="screening-time"
                type="time"
                value={values["clock"]}
                aria-invalid={"true" if time_error else "false"}
                aria-describedby={error_id("screening-time") if time_error else None}
                onChange={on_input(lambda (text: str) { change("clock", text); })}
                className="min-h-11"
            />
        </div>
        <div className="sm:col-span-3">
            {time_error and <FieldError field_id="screening-time" error={time_error}/>}
        </div>
        <div className="flex flex-wrap gap-3 sm:col-span-3">
            <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                Create screening
            </Button>
            <Button
                type="button"
                variant="ghost"
                className="min-h-11 px-5"
                onClick={lambda {
                    set_adding(False);
                    set_layout_problem("");
                    only_error("", "");
                }}
            >
                Cancel
            </Button>
        </div>
    </form>;

    def Row(s: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        sid: str = s["screening_id"];
        state: str = s["state"];
        problem = field_errors[f"problem-{sid}"] or "";
        move_error = field_errors[f"move-time-{sid}"] or "";
        live = state in ON_STOREFRONT;
        open_state = state in NOT_PUBLISHED;
        actions = <div className="flex flex-wrap gap-2">
            {open_state
                and <Button
                    className="min-h-11 px-4"
                    disabled={busy}
                    onClick={lambda { publish(s); }}
                >
                    Publish
                </Button>}{live
                and <Button
                    variant="outline"
                    className="min-h-11 px-4"
                    disabled={busy}
                    onClick={lambda { unpublish(sid); }}
                >
                    Unpublish
                </Button>}{open_state
                and moving != sid
                and <Button
                    variant="outline"
                    className="min-h-11 px-4"
                    disabled={busy}
                    onClick={lambda { start_move(s); }}
                >
                    Move
                </Button>}{(open_state or live)
                and <Button
                    variant="ghost"
                    className="min-h-11 px-4"
                    disabled={busy}
                    onClick={lambda {
                        set_confirming({"id": sid, "title": s["movie_title"]});
                        set_moving("");
                    }}
                >
                    Cancel screening
                </Button>}
        </div>;
        return
            <li
                key={sid}
                data-testid="screening"
                className={"flex flex-col gap-3 rounded-lg border bg-card p-4"
                    + (" opacity-70" if state == "cancelled" else "")}
            >
                <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="flex min-w-0 flex-col gap-1">
                        <span className="font-medium">
                            {s["movie_title"] or "Movie"}
                        </span>
                        <span className="text-sm text-muted-foreground">
                            {date_label(s["starts_at"])} · {clock_of(s["starts_at"])}
                        </span>
                    </div>
                    <Badge
                        variant={"default" if live else "secondary"}
                        data-testid="screening-state"
                    >
                        {state_label(state)}
                    </Badge>
                </div>
                {(open_state or live) and actions}
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
                        detail="It comes off your storefront and can't be scheduled again. Add a new screening instead if you need one."
                        confirm_label="Cancel screening"
                        cancel_label="Keep it"
                        on_confirm={confirm_cancel}
                        on_cancel={lambda { set_confirming(None); }}
                        busy={busy}
                    />}
                {problem and <FieldError field_id={f"problem-{sid}"} error={problem}/>}
            </li>;
    }

    listed: list[dict[str, any]] = screenings or [];  # jac:ignore[W1037]
    return
        <div className="flex flex-col gap-6" data-testid="screenings-page">
            <div className="flex flex-wrap items-end justify-between gap-4">
                {picker}{not adding
                    and <Button
                        className="min-h-11 w-fit px-5"
                        onClick={lambda {
                            set_adding(True);
                            set_moving("");
                            only_error("", "");
                        }}
                    >
                        Add screening
                    </Button>}
            </div>
            <p role="status" aria-live="polite" className="text-sm empty:hidden">
                {message}
            </p>
            {adding and add_form}
            <section
                aria-labelledby="programme-heading"
                className="flex flex-col gap-3"
            >
                <h2 id="programme-heading" className="text-lg font-semibold">
                    {screen_name} programme
                </h2>
                {screenings is None
                    and <p
                        role="status"
                        className="flex items-center gap-2 text-muted-foreground"
                    >
                        <Spinner aria-hidden="true"/>
                        Loading screenings…
                    </p>}
                {screenings is not None
                    and len(listed) == 0
                    and <p className="text-sm text-muted-foreground">
                        No screenings on {screen_name} yet
                    </p>}
                {len(listed) > 0
                    and <ul className="grid gap-3 lg:grid-cols-2">
                        {[Row(s) for s in listed]}
                    </ul>}
            </section>
        </div>;
}
