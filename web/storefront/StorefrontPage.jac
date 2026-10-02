"""`/c/:slug`: a cinema's public storefront, wearing its published theme (P3.8b).

Draws the cinema's published home page (public_home): its sections in its template's
order and layout (HomeSections.jac, P4.1b), filled from the programme; Marquee's hero
runs full width (P4.1d). The visitor's chosen venue narrows the showtimes and movies. A
movie's title leads to its page (MoviePage), a showtime to its page (ScreeningPage).
While it loads the page shows its shape; if it can't load it says so, with Try again.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from core.catalog.storefront_api { public_home }
import from .StorefrontShell { StorefrontShell, HomeSkeleton, LoadError }
import from .HomeSections { HomeBlock, home_blocks, for_venue, FeaturedHero }
import from .venue_choice { use_venue, use_title, scroll_to_hash }

def:pub StorefrontPage -> JsxElement {
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
            console.warn("storefront load failed", e);
            set_failed(True);
            return;
        }
        if not answer["ok"] {
            # The shell says "Cinema not found"; show an empty page under it.
            set_home(
                {
                    "cinema": {"name": "", "timezone": "Africa/Nairobi"},
                    "page": {"template": "marquee", "sections": []},
                    "showtimes": []
                }
            );
            return;
        }
        set_home(answer);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    def retry {
        load();
    }

    found: dict[str, any] | None = home;  # jac:ignore[W1037]
    name: str = found["cinema"]["name"] if found is not None else "";
    use_title(f"{name} · Showtimes and tickets" if name else "");
    scroll_to_hash(found is not None);
    if failed {
        return
            <StorefrontShell slug={slug}>
                <LoadError on_retry={retry}/>
            </StorefrontShell>;
    }
    if found is None {
        return
            <StorefrontShell slug={slug}>
                <HomeSkeleton/>
            </StorefrontShell>;
    }
    tz: str = found["cinema"]["timezone"];
    template: str = found["page"]["template"];
    sections = for_venue(found["page"]["sections"], venue);
    blocks = home_blocks(sections);
    # Marquee draws its hero full width, above the page (P4.1d).
    hero: any = None;  # jac:ignore[W1037]
    if template == "marquee" and len(blocks) > 0 and blocks[0][0]["type"] == "hero" {
        hero = <FeaturedHero slug={slug} section={blocks[0][0]}/>;
        blocks = blocks[1:];
    }
    return
        <StorefrontShell slug={slug} hero={hero}>
            <div
                data-testid="home-page"
                data-template={template}
                className={"@container flex flex-col gap-12 "
                    + ("mx-auto w-full max-w-2xl" if template == "compact" else "")}
            >
                {len(sections) == 0
                    and <div
                        className="flex flex-col gap-1 rounded-lg border bg-card p-6"
                    >
                        <h2 className="text-base font-semibold">Nothing on sale yet</h2>
                        <p className="text-sm text-muted-foreground">
                            New showtimes will appear here. Check back soon.
                        </p>
                    </div>}{[
                    <HomeBlock
                        key={f"{n}"}
                        slug={slug}
                        block={b}
                        tz={tz}
                        template={template}
                    /> for (n, b) in enumerate(blocks)
                ]}
            </div>
        </StorefrontShell>;
}
