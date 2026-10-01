"""`/c/:slug/m/:movie`: a movie on a cinema's storefront (P4.1).

The poster, details and synopsis, then every upcoming showtime grouped by day
(public_movie). A movie that isn't on sale says so and leads back to the cinema.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from ..shell.AppLink { AppLink }
import from core.catalog.storefront_api { public_movie }
import from .StorefrontShell { StorefrontShell, Loading, NotOnSale }
import from .StorefrontParts { Poster, ShowtimeLink }
import from .showtimes { details_line, by_day }

def DayGroup(slug: str, group: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    # One day's showtimes, under the day's name.
    showtimes: list[dict[str, any]] = group["showtimes"];  # jac:ignore[W1037]
    day: str = group["day"];
    return
        <div data-testid="showtime-day" className="flex flex-col gap-2">
            <h4 className="text-sm font-semibold">{day}</h4>
            <ul className="flex flex-wrap gap-2">
                {[
                    <li key={s["screening_id"]}>
                        <ShowtimeLink slug={slug} showtime={s} with_place={True}/>
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
    days: list[dict[str, any]] = by_day(found["screenings"]);  # jac:ignore[W1037]
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
                <div className="grid gap-6 sm:grid-cols-[12rem_1fr]">
                    <div className="w-40 sm:w-48">
                        <Poster
                            slug={slug}
                            movie_key={movie["movie_key"]}
                            has_poster={movie["has_poster"]}
                        />
                    </div>
                    <div className="flex max-w-prose flex-col gap-3">
                        <h2 className="font-display text-4xl leading-none">
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
                            and <p className="leading-relaxed">{movie["synopsis"]}</p>}
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
                    {[<DayGroup key={d["day"]} slug={slug} group={d}/> for d in days]}
                </section>
            </div>
        </StorefrontShell>;
}
