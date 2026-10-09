"""The box office's showtime picker (P7.4 redesign of P6.5's list).

Day pills along the top (Today, Tomorrow, Fri 16 Oct, …), then that day's showtimes as
poster cards: the poster with the time on it, the title, screen and venue, and seats
left with a bar. A sold-out showtime can't be chosen. Once one is chosen the picker
folds into a strip (poster, title, when and where, seats left, "Change showtime"), so
the seat map and payment below get the width.
"""

import from react { useState }
import from ...components.ui.button { Button }
import from ..storefront.showtimes {
    time_label,
    long_day_label,
    cinema_date,
    cinema_today,
    date_label,
    sorted_unique
}
import from .ShowtimeArt { ShowtimeArt }

def _left(show: dict[str, any]) -> int {  # jac:ignore[W1037]
    return max(0, int(show["seats_on_sale"]) - int(show["seats_sold"]));
}

def SeatsLeft(show: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    seats = int(show["seats_on_sale"]);
    left = _left(show);
    filled = ((seats - left) * 100 / seats) if seats > 0 else 0;
    return
        <span
            className="flex items-center gap-2 text-xs text-muted-foreground tabular-nums"
        >
            <span
                aria-hidden="true"
                className="h-1.5 w-full max-w-24 overflow-hidden rounded-full bg-muted"
            >
                <span
                    className="block h-full rounded-full bg-(--chart-bar)"
                    style={{"width": f"{filled}%"}}
                />
            </span>
            <span className="whitespace-nowrap">
                {"Sold out" if left == 0 else f"{left} seats left"}
            </span>
        </span>;
}

def DayPill(day: str, label: str, chosen: bool, on_pick: any) -> JsxElement {  # jac:ignore[W1037]
    return
        <button
            type="button"
            data-testid="counter-day"
            aria-pressed={"true" if chosen else "false"}
            onClick={lambda { on_pick(day); }}
            className={"inline-flex min-h-11 shrink-0 items-center rounded-full px-4 text-sm font-medium transition-colors "
                + (
                    "bg-primary text-primary-foreground"
                        if chosen
                        else "bg-card ring-1 ring-foreground/10 hover:bg-muted"
                )}
        >
            {label}
        </button>;
}

def ShowtimeCard(
    show: dict[str, any],  # jac:ignore[W1037]
    slug: str,
    tz: str,
    on_choose: any  # jac:ignore[W1037]
) -> JsxElement {
    sold_out = _left(show) == 0;
    return
        <li>
            <button
                type="button"
                data-testid="counter-showtime"
                disabled={sold_out}
                onClick={lambda { on_choose(show["screening_id"]); }}
                className="group flex w-full flex-col gap-2 rounded-2xl text-left focus-visible:outline-2 focus-visible:outline-offset-2 disabled:opacity-50"
            >
                <span
                    className="relative block overflow-hidden rounded-2xl bg-black ring-1 ring-foreground/10 transition-shadow group-hover:ring-2 group-hover:ring-primary"
                >
                    <ShowtimeArt
                        slug={slug}
                        screening_id={show["screening_id"]}
                        kind="poster"
                        available={show["has_poster"]}
                        className="aspect-[2/3]"
                    />
                    <span
                        className="absolute left-2 top-2 rounded-full bg-black/75 px-3 py-1 text-sm font-semibold text-white tabular-nums"
                    >
                        {time_label(show["starts_at"], tz)}
                    </span>
                </span>
                <span className="flex flex-col gap-1 px-1">
                    <span className="truncate font-medium">{show["movie_title"]}</span>
                    <span className="truncate text-xs text-muted-foreground">
                        {show["screen"]} · {show["venue"]}
                    </span>
                    <SeatsLeft show={show}/>
                </span>
            </button>
        </li>;
}

def:pub CounterPicker(
    showtimes: list[dict[str, any]],  # jac:ignore[W1037]
    slug: str,
    tz: str,
    chosen: str,
    on_choose: any  # jac:ignore[W1037]
) -> JsxElement {
    [day, set_day] = useState("");
    today = cinema_today(tz);
    days: list[str] = sorted_unique(
        [cinema_date(s["starts_at"], tz) for s in showtimes]
    );
    shown_day: str = day if day in days else (days[0] if len(days) > 0 else "");
    if chosen {
        picked: list[dict[str, any]] = [  # jac:ignore[W1037]
            s
            for s in showtimes
            if s["screening_id"] == chosen
        ];
        if len(picked) > 0 {
            show = picked[0];
            return
                <div
                    data-testid="counter-chosen"
                    className="flex flex-wrap items-center gap-4 rounded-2xl bg-card p-3 ring-1 ring-foreground/10 print:hidden"
                >
                    <ShowtimeArt
                        slug={slug}
                        screening_id={show["screening_id"]}
                        kind="poster"
                        available={show["has_poster"]}
                        className="aspect-[2/3] w-12 shrink-0 rounded-lg bg-muted"
                    />
                    <span className="flex min-w-0 flex-1 flex-col gap-1">
                        <span className="truncate font-semibold">
                            {show["movie_title"]}
                        </span>
                        <span className="text-sm text-muted-foreground">
                            {long_day_label(show["starts_at"], tz)}, {time_label(
                                show["starts_at"], tz
                            )} · {show["screen"]} · {show["venue"]}
                        </span>
                        <SeatsLeft show={show}/>
                    </span>
                    <Button
                        type="button"
                        variant="outline"
                        className="min-h-11"
                        data-testid="counter-change"
                        onClick={lambda { on_choose(""); }}
                    >
                        Change showtime
                    </Button>
                </div>;
        }
    }
    return
        <section
            aria-labelledby="pick-heading"
            className="flex flex-col gap-4 print:hidden"
        >
            <h2 id="pick-heading" className="text-lg font-semibold">
                Choose a showtime
            </h2>
            <div
                className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0"
            >
                {[
                    <DayPill
                        key={d}
                        day={d}
                        label={date_label(d, today)}
                        chosen={d == shown_day}
                        on_pick={set_day}
                    /> for d in days
                ]}
            </div>
            <ul
                className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5"
            >
                {[
                    <ShowtimeCard
                        key={s["screening_id"]}
                        show={s}
                        slug={slug}
                        tz={tz}
                        on_choose={on_choose}
                    />
                    for s in showtimes
                    if cinema_date(s["starts_at"], tz) == shown_day
                ]}
            </ul>
        </section>;
}
