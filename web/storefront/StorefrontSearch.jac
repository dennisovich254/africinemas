"""Search on a cinema's storefront (P4.1d): movies (on sale and coming soon) and venues,
in a panel that slides down from the top.

Everything searched is already public (public_home, public_venues), so it's loaded
once, when the panel first opens, and matched as the visitor types: case and accents
don't matter. Results are grouped (Movies, Cinemas); with nothing to match the panel
says so and suggests what to try.
"""

import from react { useState }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Search01Icon }
import from ...components.ui.button { Button }
import from ...components.ui.sheet {
    Sheet,
    SheetTrigger,
    SheetContent,
    SheetHeader,
    SheetTitle,
    SheetDescription,
    SheetClose
}
import from ..shell.AppLink { AppLink }
import from core.catalog.storefront_api { public_home, public_venues }

glob RESULT_LINK: str = "flex min-h-11 flex-col justify-center rounded-md px-3 py-1.5 hover:bg-muted focus-visible:outline-2 focus-visible:outline-ring";

def:pub folded(text: str) -> str {
    # `text` without case or accents, for matching ("Café" ~ "cafe").
    lower: any = text.lower();  # jac:ignore[W1037]
    return lower.normalize("NFD").replace(new(RegExp, "[\\u0300-\\u036f]", "g"), "");  # jac:ignore[W2001]
}

def:pub matches(query: str, words: list[str]) -> bool {
    # Whether every word of `query` appears in one of `words`.
    wanted = folded(query).split(" ");
    haystack = folded(" ".join(words));
    for w in wanted {
        if w and w not in haystack {
            return False;
        }
    }
    return True;
}

def:pub StorefrontSearch(slug: str, compact: bool = False) -> JsxElement {
    [open, set_open] = useState(False);
    [query, set_query] = useState("");
    [loaded, set_loaded] = useState(False);
    [failed, set_failed] = useState(False);
    [movies, set_movies] = useState([]);
    [venues, set_venues] = useState([]);

    async def load {
        home: any = None;  # jac:ignore[W1037]
        places: any = None;  # jac:ignore[W1037]
        try {
            home = await public_home(slug);
            places = await public_venues(slug);
        } except Exception as e {
            console.warn("search load failed", e);
            set_failed(True);
            return;
        }
        found: list[dict[str, any]] = [];  # jac:ignore[W1037]
        if home["ok"] {
            for m in home["movies"] {
                found.append(
                    {"key": m["movie_key"], "title": m["title"], "soon": False}
                );
            }
            for s in home["page"]["sections"] {
                if s["type"] == "coming_soon" {
                    for m in s["movies"] {
                        found.append(
                            {"key": m["movie_key"], "title": m["title"], "soon": True}
                        );
                    }
                }
            }
        }
        set_movies(found);
        set_venues(places["venues"] if places["ok"] else []);
        set_failed(False);
        set_loaded(True);
    }

    def opened(now_open: bool) {
        set_open(now_open);
        if now_open and not loaded {
            load();
        }
    }

    def close {
        set_open(False);
    }

    all_movies: list[dict[str, any]] = movies;  # jac:ignore[W1037]
    all_venues: list[dict[str, any]] = venues;  # jac:ignore[W1037]
    typed: str = query.strip();
    movie_hits = [
        m
        for m in all_movies
        if typed and matches(typed, [m["title"]])
    ];
    venue_hits = [
        v
        for v in all_venues
        if typed and matches(typed, [v["name"], v["city"], v["address"]])
    ];
    return
        <Sheet open={open} onOpenChange={opened}>
            <SheetTrigger asChild={True}>
                <Button
                    variant="ghost"
                    data-testid="search-button"
                    aria-label="Search movies and cinemas"
                    className={"min-h-11 gap-2 "
                        + ("size-11 px-0" if compact else "px-3")}
                >
                    <HugeiconsIcon
                        icon={Search01Icon}
                        strokeWidth={2}
                        aria-hidden="true"
                    />
                    {not compact and <span>Search</span>}
                </Button>
            </SheetTrigger>
            <SheetContent
                side="top"
                className="max-h-[85svh] gap-3 overflow-y-auto bg-card p-4"
                data-testid="search-panel"
            >
                <SheetHeader className="p-0">
                    <SheetTitle>Search</SheetTitle>
                    <SheetDescription>Find a movie or a cinema.</SheetDescription>
                </SheetHeader>
                <label htmlFor="storefront-search" className="sr-only">
                    Movie or cinema
                </label>
                <input
                    id="storefront-search"
                    type="search"
                    autoFocus={True}
                    autoComplete="off"
                    placeholder="Movie or cinema"
                    value={query}
                    onChange={lambda (e: any) { set_query(e.target.value); }}  # jac:ignore[W1037]
                    className="min-h-11 w-full rounded-md border border-input bg-background px-3 text-base"
                />
                <div
                    aria-live="polite"
                    data-testid="search-results"
                    className="flex flex-col gap-4"
                >
                    {failed
                        and <p role="alert" className="text-sm text-destructive">
                            We couldn't load the programme. Close search and try again.
                        </p>}{not failed
                        and typed
                        and not loaded
                        and <p className="text-sm text-muted-foreground">
                            Searching…
                        </p>}{loaded
                        and typed
                        and len(movie_hits) == 0
                        and len(venue_hits) == 0
                        and <p
                            data-testid="search-empty"
                            className="text-sm text-muted-foreground"
                        >
                            {f"Nothing matches “{typed}”. Try part of a movie title or a cinema's name."}
                        </p>}{len(movie_hits) > 0
                        and <section
                            aria-labelledby="search-movies"
                            className="flex flex-col gap-1"
                        >
                            <h2
                                id="search-movies"
                                className="text-sm font-semibold text-muted-foreground"
                            >
                                Movies
                            </h2>
                            <ul className="flex flex-col">
                                {[
                                    <li key={m["key"]}>
                                        <SheetClose asChild={True}>
                                            <AppLink
                                                to={f"/c/{slug}/movies#coming-soon"
                                                    if m["soon"]
                                                    else f"/c/{slug}/m/{m['key']}"}
                                                className={RESULT_LINK}
                                            >
                                                <span className="font-medium">
                                                    {m["title"]}
                                                </span>
                                                {m["soon"]
                                                    and <span
                                                        className="text-xs text-muted-foreground"
                                                    >
                                                        Coming soon
                                                    </span>}
                                            </AppLink>
                                        </SheetClose>
                                    </li> for m in movie_hits
                                ]}
                            </ul>
                        </section>}{len(venue_hits) > 0
                        and <section
                            aria-labelledby="search-cinemas"
                            className="flex flex-col gap-1"
                        >
                            <h2
                                id="search-cinemas"
                                className="text-sm font-semibold text-muted-foreground"
                            >
                                Cinemas
                            </h2>
                            <ul className="flex flex-col">
                                {[
                                    <li key={v["name"]}>
                                        <SheetClose asChild={True}>
                                            <AppLink
                                                to={f"/c/{slug}/cinemas"}
                                                className={RESULT_LINK}
                                            >
                                                <span className="font-medium">
                                                    {v["name"]}
                                                </span>
                                                <span
                                                    className="text-xs text-muted-foreground"
                                                >
                                                    {v["address"] or v["city"]}
                                                </span>
                                            </AppLink>
                                        </SheetClose>
                                    </li> for v in venue_hits
                                ]}
                            </ul>
                        </section>}
                </div>
                <SheetClose asChild={True}>
                    <Button
                        variant="outline"
                        className="min-h-11 w-fit px-4"
                        onClick={close}
                    >
                        Close
                    </Button>
                </SheetClose>
            </SheetContent>
        </Sheet>;
}
