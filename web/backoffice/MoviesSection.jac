"""`/app/:slug/movies`: the cinema's movies (P3.7a).

A list of the cinema's films with their posters, and a way to add one. Each poster is
fetched on its own (get_poster returns base64 WebP: JI-033) into a space already
sized 2:3, so the list doesn't jump while they load.
"""

import from react { useState, useEffect }
import from ..shell.AppLink { AppLink }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.catalog.movie_api {
    list_movies,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    get_poster  # jac:ignore[W2037]
}

def:pub movie_path(slug: str, movie_id: str) -> str {
    return f"/app/{slug}/movies/{movie_id}";
}

def:pub movie_facts(m: dict[str, any]) -> str {  # jac:ignore[W1037]
    # "83 min · 18 · Drama, Romance"
    parts = [f"{m['runtime_minutes']} min"];
    if m["age_rating"] {
        parts.append(m["age_rating"]);
    }
    if len(m["genres"]) > 0 {
        parts.append(", ".join(m["genres"]));
    }
    return " · ".join(parts);
}

def:pub PosterThumb(
    slug: str,
    movie: dict[str, any],  # jac:ignore[W1037]
    size: str = "w-16"
) -> JsxElement {  # jac:ignore[W1037]
    [src, set_src] = useState("");
    async def load {
        answer: any = None;  # jac:ignore[W1037]
        if not movie["has_poster"] {
            set_src("");
            return;
        }
        try {
            answer = await get_poster(slug, movie["movie_id"]);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("get_poster failed", e);
            return;
        }
        if answer["ok"] {
            set_src(f"data:{answer['content_type']};base64,{answer['data_base64']}");
        }
    }
    def start_loading {
        load();
    }
    useEffect(start_loading, [movie["movie_id"], movie["has_poster"]]);
    return
        <span
            className={f"{size} aspect-[2/3] shrink-0 overflow-hidden rounded-md border bg-muted"}
        >
            {src
                and <img
                    src={src}
                    alt=""
                    data-testid="movie-poster"
                    className="size-full object-cover"
                />}
        </span>;
}

def:pub MoviesSection(slug: str, permissions: list[str]) -> JsxElement {
    [movies, set_movies] = useState(None);
    [failed, set_failed] = useState("");
    can_add = "movies.create" in permissions;

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_movies(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_movies failed", e);
            set_failed("We couldn't load your movies. Refresh the page to try again.");
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_movies(answer["movies"]);
    }
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if movies is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading movies…
            </p>;
    }
    listed: list[dict[str, any]] = movies;  # jac:ignore[W1037]
    add = <Button asChild={True} className="min-h-11 w-fit px-5">
        <AppLink to={f"/app/{slug}/movies/new"}>Add movie</AppLink>
    </Button>;
    return
        <div className="flex flex-col gap-6" data-testid="movies-page">
            {len(listed) == 0
                and <div className="flex flex-col gap-3 rounded-lg border bg-card p-6">
                    <div className="flex flex-col gap-1">
                        <h2 className="text-base font-semibold">No movies yet</h2>
                        <p className="text-sm text-muted-foreground">
                            Add the films you'll show, with a poster, so you can schedule them on your screens.
                        </p>
                    </div>
                    {can_add and add}
                </div>}{len(listed) > 0
                and <div className="flex flex-col gap-4">
                    <div className="flex flex-wrap items-center justify-between gap-3">
                        <h2 className="text-lg font-semibold">
                            {"1 movie" if len(listed) == 1 else f"{len(listed)} movies"}
                        </h2>
                        {can_add and add}
                    </div>
                    <ul className="grid gap-3 md:grid-cols-2" data-testid="movie-list">
                        {[
                            <li key={m["movie_id"]}>
                                <AppLink
                                    to={movie_path(slug, m["movie_id"])}
                                    className="flex min-h-14 items-center gap-4 rounded-lg border bg-card p-3 transition-colors hover:bg-muted"
                                >
                                    <PosterThumb slug={slug} movie={m}/>
                                    <span className="flex min-w-0 flex-col gap-1">
                                        <span className="truncate font-medium">
                                            {m["title"]}
                                        </span>
                                        <span className="text-sm text-muted-foreground">
                                            {movie_facts(m)}
                                        </span>
                                    </span>
                                </AppLink>
                            </li> for m in listed
                        ]}
                    </ul>
                </div>}
        </div>;
}
