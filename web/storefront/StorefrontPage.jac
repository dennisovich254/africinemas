"""`/c/:slug`: a cinema's public storefront, wearing its published theme (P3.8b).

Draws the cinema's published home page (public_home): its sections in its template's
order and layout (HomeSections.jac, P4.1b), filled from the programme. A movie's title
leads to its page (MoviePage), a showtime to its page (ScreeningPage). With nothing to
show yet, the page says so.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from core.catalog.storefront_api { public_home }
import from .StorefrontShell { StorefrontShell, Loading }
import from .HomeSections { HomeBlock, home_blocks, nav_links }

def:pub StorefrontPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    [page, set_page] = useState(None);
    [tz, set_tz] = useState("Africa/Nairobi");

    async def load {
        home: any = None;  # jac:ignore[W1037]
        try {
            home = await public_home(slug);
        } except Exception as e {
            console.warn("storefront load failed", e);
            set_page({"template": "marquee", "sections": []});
            return;
        }
        if not home["ok"] {
            set_page({"template": "marquee", "sections": []});
            return;
        }
        set_tz(home["cinema"]["timezone"]);
        set_page(home["page"]);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    shown: dict[str, any] | None = page;  # jac:ignore[W1037]
    if shown is None {
        return
            <StorefrontShell slug={slug}>
                <Loading/>
            </StorefrontShell>;
    }
    template: str = shown["template"];
    sections: list[dict[str, any]] = shown["sections"];  # jac:ignore[W1037]
    blocks = home_blocks(sections);
    return
        <StorefrontShell slug={slug} links={nav_links(sections)}>
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
