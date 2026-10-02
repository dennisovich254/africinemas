"""`/c/:slug/m/:movie`: a movie on a cinema's storefront (P4.1).

The poster, details and synopsis, then every upcoming showtime grouped by day
(public_movie). A movie that isn't on sale says so and leads back to the cinema.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from ..shell.AppLink { AppLink }
import from core.catalog.storefront_api { public_movie }
import from .StorefrontShell { StorefrontShell, Loading, NotOnSale }
import from .venue_choice { use_title }
import from .StorefrontParts { Poster, Backdrop, ShowtimeLink }
import from .showtimes { details_line, by_day }

def DayGroup(slug: str, group: dict[str, any], tz: str) -> JsxElement {  # jac:ignore[W1037]
    # One day's showtimes, under the day's name.
    showtimes: list[dict[str, any]] = group["showtimes"];  # jac:ignore[W1037]
    day: str = group["day"];
    return
        <div data-testid="showtime-day" className="flex flex-col gap-2">
            <h4 className="text-sm font-semibold">{day}</h4>
            <ul className="flex flex-wrap gap-2">
                {[
                    <li key={s["screening_id"]}>
                        <ShowtimeLink
                            slug={slug}
                            showtime={s}
                            tz={tz}
                            with_place={True}
                        />
                    </li> for s in showtimes
                ]}
            </ul>
        </div>;
}

def:pub MoviePage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    movie_key: str = params["movie"] or "";
    [page, set_page] = useState(None);

    async def load {
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_movie(slug, movie_key);
        } except Exception as e {
            console.warn("movie load failed", e);
            set_page({"ok": False});
            return;
        }
        set_page(shown);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, movie_key]);

    found: dict[str, any] | None = page;  # jac:ignore[W1037]
    use_title(
        f"{found['movie']['title']} · {found['cinema']['name']}"
            if found is not None and found["ok"]
            else ""
    );
    if found is None {
        return
            <StorefrontShell slug={slug}>
                <Loading/>
            </StorefrontShell>;
    }
    if not found["ok"] {
        return
            <StorefrontShell slug={slug}>
                <NotOnSale slug={slug} title="Movie not found"/>
            </StorefrontShell>;
    }
    movie: dict[str, any] = found["movie"];  # jac:ignore[W1037]
    tz: str = found["cinema"]["timezone"];
    days: list[dict[str, any]] = by_day(found["screenings"], tz);  # jac:ignore[W1037]
    return
        <StorefrontShell slug={slug}>
            <div data-testid="movie-page" className="flex flex-col gap-8">
                <AppLink
                    to={f"/c/{slug}"}
                    testid="back-to-cinema"
                    className="inline-flex min-h-11 w-fit items-center text-sm font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
                >
                    {"← All movies"}
                </AppLink>
                <div
                    data-testid="movie-hero"
                    className="relative isolate overflow-hidden rounded-xl border bg-card"
                >
                    <Backdrop slug={slug} movie={movie}/>
                    <div
                        aria-hidden="true"
                        className="absolute inset-0 -z-10 bg-linear-to-t from-card via-card/90 to-card/40"
                    />
                    <div
                        className="landing-rise grid gap-6 p-5 sm:grid-cols-[12rem_1fr] sm:items-end sm:p-8"
                    >
                        <div className="w-36 sm:w-full">
                            <Poster
                                slug={slug}
                                movie_key={movie["movie_key"]}
                                has_poster={movie["has_poster"]}
                                className="shadow-lg"
                            />
                        </div>
                        <div className="flex max-w-prose flex-col gap-3">
                            <h2
                                className="font-display text-4xl leading-none sm:text-5xl"
                            >
                                {movie["title"]}
                            </h2>
                            <p className="text-sm text-muted-foreground">
                                {details_line(movie)}
                            </p>
                            {movie["language"]
                                and <p className="text-sm text-muted-foreground">
                                    {f"Language: {movie['language']}"}
                                </p>}
                            {movie["synopsis"]
                                and <p className="leading-relaxed">
                                    {movie["synopsis"]}
                                </p>}
                        </div>
                    </div>
                </div>
                <section
                    aria-labelledby="showtimes-heading"
                    className="flex flex-col gap-4"
                >
                    <h3
                        id="showtimes-heading"
                        className="font-display text-2xl leading-none"
                    >
                        Showtimes
                    </h3>
                    {[
                        <DayGroup key={d["day"]} slug={slug} group={d} tz={tz}/>
                        for d in days
                    ]}
                </section>
            </div>
        </StorefrontShell>;
}
