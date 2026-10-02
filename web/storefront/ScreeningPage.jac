"""`/c/:slug/s/:screening`: one showtime on a cinema's storefront (P4.1).

The movie, the day and time, and where (public_screening). Seat selection and checkout
come here in P4.6. A showtime that isn't on sale (unpublished, started or unknown) says
so and leads back to the cinema.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from ..shell.AppLink { AppLink }
import from core.catalog.storefront_api { public_screening }
import from .StorefrontShell { StorefrontShell, Loading, NotOnSale }
import from .venue_choice { use_title }
import from .StorefrontParts { Poster }
import from .showtimes { long_day_label, time_label, where_label, details_line }

def Fact(name: str, text: str, testid: str = "") -> JsxElement {
    return
        <div className="flex flex-col gap-0.5">
            <dt className="text-sm text-muted-foreground">{name}</dt>
            <dd data-testid={testid or None} className="text-lg font-medium">{text}</dd>
        </div>;
}

def:pub ScreeningPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    screening_id: str = params["screening"] or "";
    [page, set_page] = useState(None);

    async def load {
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_screening(slug, screening_id);
        } except Exception as e {
            console.warn("showtime load failed", e);
            set_page({"ok": False});
            return;
        }
        set_page(shown);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, screening_id]);

    found: dict[str, any] | None = page;  # jac:ignore[W1037]
    use_title(
        f"{found['screening']['movie']['title']}, {long_day_label(
            found['screening']['starts_at'], found['cinema']['timezone']
        )} · {found['cinema']['name']}"
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
                <NotOnSale slug={slug} title="Showtime not found"/>
            </StorefrontShell>;
    }
    screening: dict[str, any] = found["screening"];  # jac:ignore[W1037]
    movie: dict[str, any] = screening["movie"];  # jac:ignore[W1037]
    starts_at: str = screening["starts_at"];
    tz: str = found["cinema"]["timezone"];
    return
        <StorefrontShell slug={slug}>
            <div data-testid="screening-page" className="flex flex-col gap-8">
                <AppLink
                    to={f"/c/{slug}/m/{movie['movie_key']}"}
                    testid="back-to-movie"
                    className="inline-flex min-h-11 w-fit items-center text-sm font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
                >
                    {f"← {movie['title']}"}
                </AppLink>
                <div
                    className="grid grid-cols-[6rem_1fr] gap-4 sm:grid-cols-[8rem_1fr] sm:gap-6"
                >
                    <Poster
                        slug={slug}
                        movie_key={movie["movie_key"]}
                        has_poster={movie["has_poster"]}
                    />
                    <div className="flex min-w-0 flex-col gap-2">
                        <h2 className="font-display text-4xl leading-none">
                            {movie["title"]}
                        </h2>
                        <p className="text-sm text-muted-foreground">
                            {details_line(movie)}
                        </p>
                    </div>
                </div>
                <dl className="grid gap-4 rounded-lg border bg-card p-4 sm:grid-cols-3">
                    <Fact name="Day" text={long_day_label(starts_at, tz)}/>
                    <Fact
                        name="Time"
                        text={time_label(starts_at, tz)}
                        testid="screening-time"
                    />
                    <Fact name="Where" text={where_label(screening)}/>
                </dl>
                <p className="text-muted-foreground">
                    Online seat booking for this showtime opens soon.
                </p>
            </div>
        </StorefrontShell>;
}
