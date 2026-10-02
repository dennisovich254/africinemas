"""`/c/:slug/cinemas`: a cinema's venues and how to visit (P4.1d).

A card per venue (address, directions, screens, how many showtimes this week) with "See
what's on", which picks that venue for the visitor and shows its showtimes; then the
home page's Visit us information (location and hours, contact, questions), if the
cinema has published any.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams, useNavigate }
import from ...components.ui.button { Button }
import from core.catalog.storefront_api { public_home, public_venues }
import from .StorefrontShell { StorefrontShell, HomeSkeleton, LoadError }
import from .HomeSections { HomeBlock, home_blocks }
import from .venue_choice { choose_venue, use_title, scroll_to_hash }

glob VISIT_TYPES: list[str] = ["location", "contact", "faq"];

def directions_url(venue: dict[str, any]) -> str {  # jac:ignore[W1037]
    # A map search for the venue's address (opens the visitor's maps).
    win: any = window;  # jac:ignore[W1037,W2001]
    query: str = ", ".join(
        [
            p
            for p in [venue["name"], venue["address"], venue["city"]]
            if p
        ]
    );
    return "https://www.google.com/maps/search/?api=1&query="
        + win.encodeURIComponent(query);
}

def VenueCard(venue: dict[str, any], on_pick: any) -> JsxElement {  # jac:ignore[W1037]
    showtimes: int = venue["showtimes"];
    screens: int = venue["screens"];
    return
        <li
            data-testid="venue-card"
            className="flex flex-col gap-3 rounded-xl border bg-card p-5"
        >
            <h3 className="font-display text-2xl leading-none">{venue["name"]}</h3>
            {(venue["address"] or venue["city"])
                and <p className="text-sm">
                    {", ".join(
                        [
                            p
                            for p in [venue["address"], venue["city"]]
                            if p
                        ]
                    )}
                </p>}
            <p className="text-sm text-muted-foreground">
                {(f"{screens} screen" + ("" if screens == 1 else "s"))
                    + " · "
                    + (
                        f"{showtimes} showtime"
                            + ("" if showtimes == 1 else "s")
                            + " coming up"
                            if showtimes
                            else "no showtimes yet"
                    )}
            </p>
            <div className="mt-auto flex flex-wrap gap-2">
                {showtimes > 0
                    and <Button
                        className="min-h-11 px-4"
                        onClick={lambda { on_pick(venue["name"]); }}
                    >
                        See what's on
                    </Button>}
                <a
                    href={directions_url(venue)}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex min-h-11 items-center rounded-md border px-4 text-sm font-medium hover:bg-muted"
                >
                    Directions
                </a>
            </div>
        </li>;
}

def:pub CinemasPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    navigate: any = useNavigate();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    [data, set_data] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        set_failed(False);
        places: any = None;  # jac:ignore[W1037]
        home: any = None;  # jac:ignore[W1037]
        try {
            places = await public_venues(slug);
            home = await public_home(slug);
        } except Exception as e {
            console.warn("cinemas load failed", e);
            set_failed(True);
            return;
        }
        if not places["ok"] {
            set_data({"ok": False});
            return;
        }
        visit_sections = [
            s
            for s in home["page"]["sections"]
            if s["type"] in VISIT_TYPES
        ]
            if home["ok"]
            else [];
        set_data(
            {
                "ok": True,
                "cinema": places["cinema"],
                "venues": places["venues"],
                "visit": visit_sections,
                "tz": places["cinema"]["timezone"]
            }
        );
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    def retry {
        load();
    }

    def pick(name: str) {
        choose_venue(slug, name);
        navigate(f"/c/{slug}#showtimes");
    }

    found: dict[str, any] | None = data;  # jac:ignore[W1037]
    ready: bool = found is not None and found["ok"];
    name: str = found["cinema"]["name"] if ready else "";
    use_title(f"Cinemas · {name}" if name else "");
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
    venues: list[dict[str, any]] = found["venues"];  # jac:ignore[W1037]
    visit_sections: list[dict[str, any]] = found["visit"];  # jac:ignore[W1037]
    return
        <StorefrontShell slug={slug}>
            <div data-testid="cinemas-page" className="@container flex flex-col gap-12">
                <section
                    aria-labelledby="cinemas-heading"
                    className="flex flex-col gap-4"
                >
                    <h2
                        id="cinemas-heading"
                        className="font-display text-4xl leading-none"
                    >
                        Find a cinema
                    </h2>
                    {len(venues) == 0
                        and <p className="rounded-lg border bg-card p-6">
                            This cinema hasn't listed its venues yet.
                        </p>}
                    <ul className="grid gap-4 @xl:grid-cols-2">
                        {[
                            <VenueCard key={v["name"]} venue={v} on_pick={pick}/>
                            for v in venues
                        ]}
                    </ul>
                </section>
                {len(visit_sections) > 0
                    and [
                        <HomeBlock
                            key={f"{n}"}
                            slug={slug}
                            block={b}
                            tz={found["tz"]}
                            template="marquee"
                        /> for (n, b) in enumerate(home_blocks(visit_sections))
                    ]}
            </div>
        </StorefrontShell>;
}
