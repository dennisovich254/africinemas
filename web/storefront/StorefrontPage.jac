"""`/c/:slug`: a cinema's public storefront, wearing its published theme (P3.8b).

The theme's CSS comes from public_branding, which builds it on the server from checked
tokens only (core/theming/css.jac), so it can be added to the page as it is (as a <style>
in <head>, removed when the visitor leaves). It overrides
the platform's storefront defaults (styles/brand.css) for this cinema alone. The page
lists what's on (public_screenings); movie pages, seat maps and checkout come in Phase 4.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from ...components.ui.empty { Empty, EmptyHeader, EmptyTitle, EmptyDescription }
import from ...components.ui.spinner { Spinner }
import from ..theme.ThemeProvider { ThemeProvider }
import from core.theming.branding_api { public_branding }
import from core.catalog.screening_api { public_screenings }

def when(starts_at: str) -> str {
    # "Fri 2 Oct, 18:15", in the visitor's time zone.
    return new(Date, starts_at).toLocaleString(  # jac:ignore[W2001]
        [],
        {
            "weekday": "short",
            "day": "numeric",
            "month": "short",
            "hour": "2-digit",
            "minute": "2-digit"
        }
    );
}

def Screening(s: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    return
        <li className="flex flex-col gap-1 rounded-lg border bg-card p-4">
            <span className="font-display text-2xl leading-none">
                {s["movie"]["title"] or "Untitled"}
            </span>
            <span
                className="w-fit rounded-md bg-primary px-2 py-0.5 text-sm font-medium text-primary-foreground"
            >
                {when(s["starts_at"])}
            </span>
            <span className="text-sm text-muted-foreground">
                {s["venue"]["name"] or ""}{s["screen"]["name"]
                    and f" · {s['screen']['name']}"}
            </span>
        </li>;
}

def:pub StorefrontPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    [branding, set_branding] = useState(None);
    [cinema, set_cinema] = useState(None);
    [screenings, set_screenings] = useState([]);
    [missing, set_missing] = useState(False);

    async def load {
        shown: any = None;  # jac:ignore[W1037]
        programme: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_branding(slug);
            programme = await public_screenings(slug);
        } except Exception as e {
            console.warn("storefront load failed", e);
            set_missing(True);
            return;
        }
        if not shown["ok"] {
            set_missing(True);
            return;
        }
        set_branding(shown["branding"]);
        set_cinema(shown["cinema"]);
        set_screenings(programme["screenings"] if programme["ok"] else []);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    def wear_theme -> any {  # jac:ignore[W1037]
        # The cinema's theme CSS, added after the platform stylesheet so it wins, and
        # removed again when the visitor leaves this storefront.
        doc: any = document;  # jac:ignore[W1037,W2001]
        tag: any = doc.createElement("style");  # jac:ignore[W1037]
        shown: dict[str, any] | None = branding;  # jac:ignore[W1037]
        tag.textContent = shown["css"] if shown is not None else "";
        doc.head.appendChild(tag);
        return lambda { doc.head.removeChild(tag); };
    }
    useEffect(wear_theme, [branding]);

    if missing {
        return
            <ThemeProvider surface="storefront">
                <main className="mx-auto flex max-w-xl flex-col gap-3 px-4 py-16">
                    <h1 className="font-display text-4xl">Cinema not found</h1>
                    <p className="text-muted-foreground">
                        There's no cinema at this address. Check the link and try again.
                    </p>
                </main>
            </ThemeProvider>;
    }
    if branding is None {
        return
            <ThemeProvider surface="storefront">
                <main className="flex min-h-svh items-center justify-center">
                    <p
                        role="status"
                        className="flex items-center gap-2 text-muted-foreground"
                    >
                        <Spinner aria-hidden="true"/>
                        Loading…
                    </p>
                </main>
            </ThemeProvider>;
    }
    look: dict[str, any] = branding;  # jac:ignore[W1037]
    place: dict[str, str] = cinema;
    listed: list[dict[str, any]] = screenings;  # jac:ignore[W1037]
    return
        <ThemeProvider surface="storefront">
            <div data-testid="storefront" className="flex min-h-svh flex-col">
                <header className="border-b bg-card">
                    <div
                        className="mx-auto flex w-full max-w-5xl items-center px-4 py-3"
                    >
                        <h1
                            data-testid="storefront-name"
                            className="font-display text-3xl leading-none"
                        >
                            {look["logo"]
                                and <img
                                    src={look["logo"]}
                                    alt={place["name"]}
                                    className="h-10 w-auto max-w-[70vw]"
                                />}{not look["logo"] and place["name"]}
                        </h1>
                    </div>
                </header>
                <main
                    className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-4 px-4 py-8"
                >
                    <h2 className="font-display text-4xl leading-none">What's on</h2>
                    {len(listed) == 0
                        and <Empty className="border">
                            <EmptyHeader>
                                <EmptyTitle>
                                    <h3 className="text-base font-semibold">
                                        Nothing on sale yet
                                    </h3>
                                </EmptyTitle>
                                <EmptyDescription>
                                    New showtimes will appear here. Check back soon.
                                </EmptyDescription>
                            </EmptyHeader>
                        </Empty>}
                    {len(listed) > 0
                        and <ul className="grid gap-3 sm:grid-cols-2">
                            {[
                                <Screening key={s["screening_id"]} s={s}/>
                                for s in listed
                            ]}
                        </ul>}
                </main>
                <footer
                    className="border-t px-4 py-4 text-center text-sm text-muted-foreground"
                >
                    Tickets by AfriCinemas
                </footer>
            </div>
        </ThemeProvider>;
}
