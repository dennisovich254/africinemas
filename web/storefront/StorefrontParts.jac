"""Pieces the storefront pages share (P4.1): a movie's poster and a showtime link.

A poster keeps its 2:3 frame while it loads, and when the movie has none, so nothing
moves when it arrives. It's decorative: the movie's title is always next to it.
"""

import from react { useState, useEffect }
import from ..shell.AppLink { AppLink }
import from core.catalog.storefront_api { public_poster }
import from .showtimes { time_label, day_label, where_label }

def:pub Poster(
    slug: str, movie_key: str, has_poster: bool, className: str = ""
) -> JsxElement {
    [src, set_src] = useState("");

    async def load {
        if not has_poster {
            set_src("");
            return;
        }
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_poster(slug, movie_key);
        } except Exception as e {
            console.warn("poster load failed", e);
            return;
        }
        set_src(shown["poster"] if shown["ok"] else "");
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, movie_key, has_poster]);

    return
        <div
            aria-hidden="true"
            className={f"aspect-[2/3] overflow-hidden rounded-md bg-muted {className}"}
        >
            {src
                and <img
                    src={src}
                    alt=""
                    loading="lazy"
                    className="h-full w-full object-cover"
                />}
        </div>;
}

def:pub ShowtimeLink(
    slug: str,
    showtime: dict[str, any],  # jac:ignore[W1037]
    tz: str,
    with_day: bool = False,
    with_place: bool = False
) -> JsxElement {
    # A showtime as a button-sized link to its page: "Fri 3 Oct · 18:15" on the movie
    # list, or "18:15" over "Westgate · Screen 1" under a day heading.
    starts_at: str = showtime["starts_at"];
    return
        <AppLink
            to={f"/c/{slug}/s/{showtime['screening_id']}"}
            testid="showtime"
            className="inline-flex min-h-11 min-w-11 flex-col justify-center rounded-md border bg-background px-3 py-1.5 text-left transition-colors hover:border-primary hover:bg-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
        >
            <span className="font-medium tabular-nums">
                {f"{day_label(starts_at, tz)} · " if with_day else ""}{time_label(
                    starts_at, tz
                )}
            </span>
            {with_place
                and <span className="text-xs text-muted-foreground">
                    {where_label(showtime)}
                </span>}
        </AppLink>;
}
