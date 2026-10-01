"""The frame of every storefront page (P4.1): the cinema's published theme, its name or
logo, and the footer.

The theme's CSS comes from public_branding, which builds it on the server from checked
tokens only (core/theming/css.jac), so it can be added to the page as it is (as a <style>
in <head>, removed when the visitor leaves). It overrides the platform's storefront
defaults (styles/brand.css) for this cinema alone. An unknown or closed cinema gets
"Cinema not found" instead of the page.
"""

import from react { useState, useEffect }
import from ...components.ui.spinner { Spinner }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..shell.AppLink { AppLink }
import from core.theming.branding_api { public_branding }

def:pub Loading -> JsxElement {
    return
        <p
            role="status"
            className="flex items-center justify-center gap-2 py-16 text-muted-foreground"
        >
            <Spinner aria-hidden="true"/>
            Loading…
        </p>;
}

def:pub NotOnSale(slug: str, title: str) -> JsxElement {
    # A movie or showtime link that leads nowhere (not published, started or unknown).
    return
        <div
            data-testid="storefront-missing"
            className="flex flex-col items-start gap-3 rounded-lg border bg-card p-6"
        >
            <h2 className="font-display text-3xl leading-none">{title}</h2>
            <p className="text-muted-foreground">
                This isn't on sale any more, or the link is wrong.
            </p>
            <AppLink
                to={f"/c/{slug}"}
                testid="back-to-cinema"
                className="inline-flex min-h-11 items-center rounded-md bg-primary px-4 font-medium text-primary-foreground"
            >
                See what's on
            </AppLink>
        </div>;
}

def:pub StorefrontShell(
    slug: str,
    children: any = None  # jac:ignore[W1037] pass-through children (jac-cl-organization idiom)
) -> JsxElement {
    [branding, set_branding] = useState(None);
    [cinema, set_cinema] = useState(None);
    [missing, set_missing] = useState(False);

    async def load {
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_branding(slug);
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
                    <Loading/>
                </main>
            </ThemeProvider>;
    }
    look: dict[str, any] = branding;  # jac:ignore[W1037]
    place: dict[str, str] = cinema;
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
                    className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-6 px-4 py-8"
                >
                    {children}
                </main>
                <footer
                    className="border-t px-4 py-4 text-center text-sm text-muted-foreground"
                >
                    Tickets by AfriCinemas
                </footer>
            </div>
        </ThemeProvider>;
}
