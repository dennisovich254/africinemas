"""`/c/:slug/movies`: every movie on a cinema's storefront (P4.1d).

Now showing (with filters and sort, narrowed to the visitor's chosen venue) and Coming
soon (the home page's list, with release dates), whatever sections the home page
shows. Loading, empty and error states as on the home page.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from core.catalog.storefront_api { public_home }
import from .StorefrontShell { StorefrontShell, HomeSkeleton, LoadError }
import from .HomeSections { NowShowing, ComingSoon }
import from .venue_choice { use_venue, use_title, scroll_to_hash }

def:pub MoviesPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    [home, set_home] = useState(None);
    [failed, set_failed] = useState(False);
    venue = use_venue(slug);

    async def load {
        set_failed(False);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await public_home(slug);
        } except Exception as e {
            console.warn("movies load failed", e);
            set_failed(True);
            return;
        }
        set_home(answer if answer["ok"] else {"ok": False});
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    def retry {
        load();
    }

    found: dict[str, any] | None = home;  # jac:ignore[W1037]
    ready: bool = found is not None and found["ok"];
    name: str = found["cinema"]["name"] if ready else "";
    use_title(f"Movies · {name}" if name else "");
    scroll_to_hash(ready);
    if failed {
        return
            <StorefrontShell slug={slug}>
                <LoadError on_retry={retry}/>
            </StorefrontShell>;
    }
    if not ready {
        return
            <StorefrontShell slug={slug}>
                <HomeSkeleton/>
            </StorefrontShell>;
    }
    tz: str = found["cinema"]["timezone"];
    on_sale = [
        m
        for m in found["movies"]
        if not venue or venue in (m.get("venues") or [])
    ];
    soon: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in found["page"]["sections"] {
        if s["type"] == "coming_soon" {
            soon = s["movies"];
        }
    }
    return
        <StorefrontShell slug={slug}>
            <div data-testid="movies-page" className="@container flex flex-col gap-12">
                <h2 className="font-display text-4xl leading-none">Movies</h2>
                {len(on_sale) == 0
                    and <div
                        data-testid="movies-empty"
                        className="rounded-lg border bg-card p-6"
                    >
                        <p>
                            {f"Nothing is showing at {venue} right now. Choose All venues to see the rest."
                                if venue
                                else "Nothing is on sale yet. New showtimes will appear here."}
                        </p>
                    </div>}
                {len(on_sale) > 0
                    and <NowShowing
                        slug={slug}
                        section={{
                            "type": "now_showing",
                            "fields": {"title": "Now showing"},
                            "movies": on_sale
                        }}
                        tz={tz}
                        template="marquee"
                    />}
                {len(soon) > 0
                    and <ComingSoon
                        slug={slug}
                        section={{
                            "type": "coming_soon",
                            "fields": {"title": "Coming soon"},
                            "movies": soon
                        }}
                    />}
            </div>
        </StorefrontShell>;
}
