"""`/c/:slug`: a cinema's public storefront, wearing its published theme (P3.8b).

Lists the movies on sale (public_home, P4.1), each once, the soonest first: its poster,
details and next showtimes. A movie's title leads to its page (MoviePage), a showtime to
its page (ScreeningPage). Each cinema's own sections and templates come in P4.1b.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from ..shell.AppLink { AppLink }
import from core.catalog.storefront_api { public_home }
import from .StorefrontShell { StorefrontShell, Loading }
import from .StorefrontParts { Poster, ShowtimeLink }
import from .showtimes { details_line }

def MovieCard(slug: str, movie: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    showtimes: list[dict[str, any]] = movie["next"];  # jac:ignore[W1037]
    return
        <li
            data-testid="movie-card"
            className="grid grid-cols-[6rem_1fr] gap-4 rounded-lg border bg-card p-4 sm:grid-cols-[7.5rem_1fr]"
        >
            <Poster
                slug={slug}
                movie_key={movie["movie_key"]}
                has_poster={movie["has_poster"]}
            />
            <div className="flex min-w-0 flex-col gap-3">
                <div className="flex flex-col gap-1">
                    <h3 className="font-display text-2xl leading-tight">
                        <AppLink
                            to={f"/c/{slug}/m/{movie['movie_key']}"}
                            className="inline-flex min-h-11 items-center underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
                        >
                            {movie["title"]}
                        </AppLink>
                    </h3>
                    <p className="text-sm text-muted-foreground">
                        {details_line(movie)}
                    </p>
                </div>
                <ul aria-label="Next showtimes" className="flex flex-wrap gap-2">
                    {[
                        <li key={s["screening_id"]}>
                            <ShowtimeLink slug={slug} showtime={s} with_day={True}/>
                        </li> for s in showtimes
                    ]}
                </ul>
            </div>
        </li>;
}

def:pub StorefrontPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    [movies, set_movies] = useState(None);

    async def load {
        home: any = None;  # jac:ignore[W1037]
        try {
            home = await public_home(slug);
        } except Exception as e {
            console.warn("storefront load failed", e);
            set_movies([]);
            return;
        }
        set_movies(home["movies"] if home["ok"] else []);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    listed: list[dict[str, any]] | None = movies;  # jac:ignore[W1037]
    return
        <StorefrontShell slug={slug}>
            <h2 className="font-display text-4xl leading-none">Now showing</h2>
            {listed is None and <Loading/>}
            {listed is not None
                and len(listed) == 0
                and <div className="flex flex-col gap-1 rounded-lg border bg-card p-6">
                    <h3 className="text-base font-semibold">Nothing on sale yet</h3>
                    <p className="text-sm text-muted-foreground">
                        New showtimes will appear here. Check back soon.
                    </p>
                </div>}
            {listed is not None
                and len(listed) > 0
                and <ul className="grid gap-4 lg:grid-cols-2">
                    {[
                        <MovieCard key={m["movie_key"]} slug={slug} movie={m}/>
                        for m in listed
                    ]}
                </ul>}
        </StorefrontShell>;
}
