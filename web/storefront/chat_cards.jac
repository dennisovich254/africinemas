"""The cards in a cinema's chat (P8.4), drawn from the server's card data (core/agent/cards.jac).

The server builds every card from what its tools returned, never from the model's
words, so a card only ever shows real showtimes. Two kinds:

- programme: the days, each with its movies (poster, title) and their times;
- movie: poster, details, Play trailer, and its showtimes.

Times link to the showtime's own page, where the visitor picks seats (booking in the chat
comes in 8.5); titles link to the movie's page. Showtimes arrive in the cinema's local
time ("2026-10-10 18:15"), so they're shown as they are.
"""

import from ..shell.AppLink { AppLink }
import from .StorefrontParts { Poster }
import from .TrailerPlayer { TrailerPlayer }

glob LINK: str = "underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring",
     TIME: str = "inline-flex min-h-11 min-w-11 flex-col justify-center rounded-md border bg-background px-3 py-1 text-left transition-colors hover:border-primary hover:bg-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring";

def:pub day_name(day: str) -> str {
    # "2026-10-10" as "Sat 10 Oct": a calendar date, read at noon UTC so it never slips.
    if len(day) != 10 {
        return day;
    }
    noon: any = new(Date, f"{day}T12:00:00Z");  # jac:ignore[W1037,W2001]
    return noon.toLocaleDateString(
        "en-GB",
        {"weekday": "short", "day": "numeric", "month": "short", "timeZone": "UTC"}
    );
}

def:pub facts_line(card: dict[str, any]) -> str {  # jac:ignore[W1037]
    minutes: int = card["runtime_minutes"] or 0;
    length = "";
    if minutes > 0 {
        length = f"{minutes // 60} h {minutes % 60} min"
            if minutes >= 60
            else f"{minutes} min";
    }
    genres: list[str] = card["genres"] or [];
    parts = [card["age_rating"], length, ", ".join(genres)];
    return " · ".join(
        [
            p
            for p in parts
            if p
        ]
    );
}

def TimeLink(slug: str, showtime: dict[str, any], with_day: bool) -> JsxElement {  # jac:ignore[W1037]
    starts: str = showtime["starts"];
    place = " · ".join(
        [
            p
            for p in [showtime["venue"], showtime["screen"]]
            if p
        ]
    );
    return
        <AppLink
            to={f"/c/{slug}/s/{showtime['showtime_id']}"}
            testid="chat-showtime"
            className={TIME}
        >
            <span className="font-medium tabular-nums">
                {(day_name(starts[:10]) + " · " if with_day else "") + starts[11:16]}
            </span>
            {place and <span className="text-xs text-muted-foreground">{place}</span>}
        </AppLink>;
}

def ProgrammeMovie(
    slug: str,
    movie: dict[str, str],
    showtimes: list[dict[str, any]]  # jac:ignore[W1037]
) -> JsxElement {
    # One movie on one day: its poster and title (to its page), then its times.
    return
        <li className="flex gap-3">
            <div className="w-16 shrink-0">
                <Poster slug={slug} movie_key={movie["movie_key"]} has_poster={True}/>
            </div>
            <div className="flex min-w-0 flex-col gap-2">
                <AppLink
                    to={f"/c/{slug}/m/{movie['movie_key']}"}
                    className={"inline-flex min-h-11 items-center font-semibold "
                        + LINK}
                >
                    {movie["title"]}
                </AppLink>
                <div className="flex flex-wrap gap-2">
                    {[
                        <TimeLink
                            key={s["showtime_id"]}
                            slug={slug}
                            showtime={s}
                            with_day={False}
                        /> for s in showtimes
                    ]}
                </div>
            </div>
        </li>;
}

def ProgrammeDay(
    slug: str,
    day: dict[str, any],  # jac:ignore[W1037]
    movies: list[dict[str, str]]
) -> JsxElement {
    shown: list[dict[str, any]] = day["showtimes"];  # jac:ignore[W1037]
    return
        <section className="flex flex-col gap-3">
            <h4 className="text-sm font-semibold">{day_name(day["day"])}</h4>
            <ul className="flex flex-col gap-4">
                {[
                    <ProgrammeMovie
                        key={m["movie_key"]}
                        slug={slug}
                        movie={m}
                        showtimes={[
                            s
                            for s in shown
                            if s["movie_key"] == m["movie_key"]
                        ]}
                    />
                    for m in movies
                    if len(
                        [
                            s
                            for s in shown
                            if s["movie_key"] == m["movie_key"]
                        ]
                    )
                        > 0
                ]}
            </ul>
        </section>;
}

def ProgrammeCard(card: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    slug: str = card["cinema_slug"];
    days: list[dict[str, any]] = card["days"];  # jac:ignore[W1037]
    return
        <div
            data-testid="chat-programme"
            className="flex flex-col gap-4 rounded-xl border bg-card p-4"
        >
            <h3 className="font-semibold">{f"What's on at {card['cinema']}"}</h3>
            {len(days) == 0
                and <p className="text-sm text-muted-foreground">
                    Nothing is on sale right now.
                </p>}
            {[
                <ProgrammeDay
                    key={d["day"]}
                    slug={slug}
                    day={d}
                    movies={card["movies"]}
                /> for d in days
            ]}
        </div>;
}

def MovieCard(card: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    slug: str = card["cinema_slug"];
    times: list[dict[str, any]] = card["showtimes"];  # jac:ignore[W1037]
    facts = facts_line(card);
    return
        <div
            data-testid="chat-movie"
            className="flex flex-col gap-4 rounded-xl border bg-card p-4"
        >
            <div className="flex gap-4">
                <div className="w-24 shrink-0">
                    <Poster
                        slug={slug}
                        movie_key={card["movie_key"]}
                        has_poster={True}
                    />
                </div>
                <div className="flex min-w-0 flex-col gap-1">
                    <h3 className="font-display text-2xl leading-none">
                        {card["title"]}
                    </h3>
                    {facts and <p className="text-sm text-muted-foreground">{facts}</p>}
                    {card["synopsis"]
                        and <p className="line-clamp-3 text-sm">{card["synopsis"]}</p>}
                    <AppLink
                        to={f"/c/{slug}/m/{card['movie_key']}"}
                        className={"inline-flex min-h-11 w-fit items-center text-sm font-medium "
                            + LINK}
                    >
                        More about this movie
                    </AppLink>
                </div>
            </div>
            {card["trailer_embed"]
                and <TrailerPlayer
                    embed={card["trailer_embed"]}
                    title={card["title"]}
                />}
            {len(times) > 0
                and <div className="flex flex-wrap gap-2">
                    {[
                        <TimeLink
                            key={s["showtime_id"]}
                            slug={slug}
                            showtime={s}
                            with_day={True}
                        /> for s in times
                    ]}
                </div>}
            {len(times) == 0
                and <p className="text-sm text-muted-foreground">
                    No showtimes on sale.
                </p>}
        </div>;
}

def:pub ChatCard(card: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    if card["type"] == "programme" {
        return <ProgrammeCard card={card}/>;
    }
    if card["type"] == "movie" {
        return <MovieCard card={card}/>;
    }
    return <span hidden={True}></span>;
}
