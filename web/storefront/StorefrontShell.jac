"""The frame of every storefront page (P4.1): the cinema's published theme, its name or
logo with links to the page's sections (a sticky header, P4.1c), and the footer.

The theme's CSS comes from public_branding, which builds it on the server from checked
tokens only (core/theming/css.jac), so it can be added to the page as it is (as a <style>
in <head>, removed when the visitor leaves). It overrides the platform's storefront
defaults (styles/brand.css) for this cinema alone. An unknown or closed cinema gets
"Cinema not found" instead of the page.

Every page but a showtime's (whose seat bar is fixed to the bottom) has "Ask <cinema>",
the cinema's own chat (P8.4, ChatPanel.jac).

The header (P4.1d) has the cinema's name or logo; Movies, Showtimes and Cinemas;
search; Sign in or My tickets (AccountLinks.jac, P8.6c); a venue picker when the cinema has more than one venue; and Book tickets. On
phones the links and the picker move into a menu sheet, and search and Book stay in
view. The footer links to the storefront's pages by topic.
"""

import from react { useState, useEffect }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Menu01Icon, Cancel01Icon }
import from ...components.ui.spinner { Spinner }
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
import from ..theme.ThemeProvider { ThemeProvider }
import from ..shell.AppLink { AppLink }
import from core.theming.branding_api { public_branding }
import from core.catalog.storefront_api { public_venues }
import from .StorefrontSearch { StorefrontSearch }
import from .venue_choice { use_venue, choose_venue }
import from .ChatPanel { ChatLauncher }
import from .AccountLinks { AccountLinks }

glob NAV_LINK: str = "inline-flex min-h-11 items-center rounded-md px-3 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring";

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

def:pub HomeSkeleton -> JsxElement {
    # The home page's shape while it loads: a hero, a row of days, a row of posters.
    bar = "rounded-lg bg-muted motion-safe:animate-pulse";
    return
        <div role="status" aria-label="Loading" className="flex flex-col gap-10">
            <div className={f"h-72 {bar}"}/>
            <div className="flex gap-2">
                {[<div key={f"{i}"} className={f"h-11 w-24 {bar}"}/> for i in range(4)]}
            </div>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
                {[
                    <div key={f"{i}"} className={f"aspect-[2/3] {bar}"}/>
                    for i in range(4)
                ]}
            </div>
        </div>;
}

def:pub LoadError(on_retry: any) -> JsxElement {  # jac:ignore[W1037]
    # A part of the storefront that couldn't load, and a way to try again.
    return
        <div
            role="alert"
            data-testid="load-error"
            className="flex flex-col items-start gap-3 rounded-lg border bg-card p-6"
        >
            <p className="font-medium">We couldn't load this cinema's programme.</p>
            <p className="text-sm text-muted-foreground">
                Check your connection, then try again.
            </p>
            <Button className="min-h-11 px-5" onClick={on_retry}>Try again</Button>
        </div>;
}

def VenuePicker(slug: str, venues: list[str], testid: str) -> JsxElement {
    # Which venue's programme to show; "All venues" by default. Remembered per cinema.
    venue = use_venue(slug);
    chosen: str = venue if venue in venues else "";
    return
        <label className="flex min-h-11 items-center gap-2 text-sm">
            <span className="text-muted-foreground">Venue</span>
            <select
                data-testid={testid}
                value={chosen}
                onChange={lambda (e: any) { choose_venue(slug, e.target.value); }}  # jac:ignore[W1037]
                className="min-h-11 rounded-md border border-input bg-background px-2 text-sm"
            >
                <option value="">All venues</option>
                {[<option key={v} value={v}>{v}</option> for v in venues]}
            </select>
        </label>;
}

def NavItems(slug: str, block: bool = False) -> JsxElement {
    # The storefront's pages: Movies, Showtimes (on the home page) and Cinemas.
    item = NAV_LINK + (" w-full" if block else "");
    return
        <ul className={"flex flex-col gap-1" if block else "flex items-center gap-1"}>
            <li>
                <AppLink to={f"/c/{slug}/movies"} className={item}>Movies</AppLink>
            </li>
            <li>
                <a href={f"/c/{slug}#showtimes"} className={item}>Showtimes</a>
            </li>
            <li>
                <AppLink to={f"/c/{slug}/cinemas"} className={item}>Cinemas</AppLink>
            </li>
        </ul>;
}

def FooterColumn(title: str, links: list[list[str]]) -> JsxElement {
    return
        <div className="flex flex-col gap-1">
            <h2 className="text-sm font-semibold text-foreground">{title}</h2>
            <ul className="flex flex-col">
                {[
                    <li key={link[1]}>
                        <a
                            href={link[1]}
                            className="inline-flex min-h-11 min-w-11 items-center text-sm hover:text-foreground hover:underline"
                        >
                            {link[0]}
                        </a>
                    </li> for link in links
                ]}
            </ul>
        </div>;
}

def:pub StorefrontShell(
    slug: str,
    hero: any = None,  # jac:ignore[W1037] a full-width hero above the page (P4.1d)
    chat: bool = True,
    children: any = None  # jac:ignore[W1037] pass-through children (jac-cl-organization idiom)
) -> JsxElement {
    # With a `hero`, the header lies over it: see-through, in the theme's dark colours,
    # until the visitor scrolls, then solid as on every other page.
    [scrolled, set_scrolled] = useState(False);

    def watch_scroll -> any {  # jac:ignore[W1037]
        win: any = window;  # jac:ignore[W1037,W2001]
        def moved {
            set_scrolled(win.scrollY > 24);
        }
        moved();
        win.addEventListener("scroll", moved, {"passive": True});
        return lambda { win.removeEventListener("scroll", moved); };
    }
    useEffect(watch_scroll, []);
    [branding, set_branding] = useState(None);
    [cinema, set_cinema] = useState(None);
    [missing, set_missing] = useState(False);
    [venues, set_venues] = useState([]);
    [menu_open, set_menu_open] = useState(False);

    async def load_venues {
        places: any = None;  # jac:ignore[W1037]
        try {
            places = await public_venues(slug);
        } except Exception as e {
            console.warn("venues load failed", e);
            return;
        }
        if places["ok"] {
            set_venues([v["name"] for v in places["venues"]]);
        }
    }

    def start_venues {
        load_venues();
    }
    useEffect(start_venues, [slug]);

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
    over: bool = hero is not None and not scrolled;
    place: dict[str, str] = cinema;
    names: list[str] = venues;
    several: bool = len(names) > 1;
    book = <a
        href={f"/c/{slug}#showtimes"}
        data-testid="header-book"
        className="inline-flex min-h-11 shrink-0 items-center rounded-md bg-primary px-4 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary/90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
    >
        <span className="sm:hidden">Book</span>
        <span className="hidden sm:inline">Book tickets</span>
    </a>;
    return
        <ThemeProvider surface="storefront">
            <div data-testid="storefront" className="flex min-h-svh flex-col">
                <div className={"sticky top-0 z-30 " + ("dark" if over else "")}>
                    <header
                        data-surface="storefront"
                        data-testid="storefront-header"
                        data-over-hero={"true" if over else "false"}
                        className={"text-foreground transition-colors duration-200 motion-reduce:transition-none "
                            + (
                                "border-b border-transparent bg-linear-to-b from-background/80 to-transparent"
                                    if over
                                    else "border-b bg-card/95 backdrop-blur supports-[backdrop-filter]:bg-card/80"
                            )}
                    >
                        <div
                            className="mx-auto flex w-full max-w-5xl items-center gap-2 px-4 py-2"
                        >
                            <h1
                                data-testid="storefront-name"
                                className="mr-auto min-w-0 font-display text-2xl leading-none sm:text-3xl"
                            >
                                <AppLink
                                    to={f"/c/{slug}"}
                                    className="flex min-h-11 min-w-0 items-center"
                                >
                                    {look["logo"]
                                        and <img
                                            src={look["logo"]}
                                            alt={place["name"]}
                                            className="h-10 w-auto max-w-[45vw]"
                                        />}{not look["logo"]
                                        and <span className="truncate">
                                            {place["name"]}
                                        </span>}
                                </AppLink>
                            </h1>
                            <nav aria-label="Storefront" className="hidden md:block">
                                <NavItems slug={slug}/>
                            </nav>
                            {several
                                and <div className="hidden lg:block">
                                    <VenuePicker
                                        slug={slug}
                                        venues={names}
                                        testid="venue-picker"
                                    />
                                </div>}
                            <div className="hidden md:block">
                                <AccountLinks slug={slug} link_class={NAV_LINK}/>
                            </div>
                            <StorefrontSearch slug={slug} compact={True}/>
                            {book}
                            <Sheet open={menu_open} onOpenChange={set_menu_open}>
                                <SheetTrigger asChild={True}>
                                    <Button
                                        variant="ghost"
                                        size="icon"
                                        className={"size-11 "
                                            + ("lg:hidden" if several else "md:hidden")}
                                        aria-label="Open menu"
                                        data-testid="storefront-menu"
                                    >
                                        <HugeiconsIcon
                                            icon={Menu01Icon}
                                            strokeWidth={2}
                                        />
                                    </Button>
                                </SheetTrigger>
                                <SheetContent
                                    side="right"
                                    showCloseButton={False}
                                    className="w-72 gap-4 bg-card p-4"
                                    data-testid="storefront-menu-sheet"
                                >
                                    <SheetHeader
                                        className="flex-row items-center justify-between p-0"
                                    >
                                        <SheetTitle
                                            className="font-display text-2xl leading-none"
                                        >
                                            {place["name"]}
                                        </SheetTitle>
                                        <SheetClose asChild={True}>
                                            <Button
                                                variant="ghost"
                                                size="icon"
                                                className="size-11"
                                                aria-label="Close menu"
                                            >
                                                <HugeiconsIcon
                                                    icon={Cancel01Icon}
                                                    strokeWidth={2}
                                                />
                                            </Button>
                                        </SheetClose>
                                    </SheetHeader>
                                    <SheetDescription className="sr-only">
                                        The storefront's pages
                                    </SheetDescription>
                                    <nav aria-label="Storefront menu">
                                        <NavItems slug={slug} block={True}/>
                                    </nav>
                                    <div className="border-t pt-4 md:hidden">
                                        <AccountLinks
                                            slug={slug}
                                            link_class={NAV_LINK}
                                            block={True}
                                        />
                                    </div>
                                    {several
                                        and <VenuePicker
                                            slug={slug}
                                            venues={names}
                                            testid="venue-picker-menu"
                                        />}
                                </SheetContent>
                            </Sheet>
                        </div>
                    </header>
                </div>
                {hero}
                <main
                    className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-6 px-4 py-8"
                >
                    {children}
                </main>
                {chat and <ChatLauncher slug={slug} cinema={place["name"]}/>}
                <footer className="border-t bg-card">
                    <div
                        className="mx-auto grid w-full max-w-5xl gap-6 px-4 py-8 text-sm text-muted-foreground sm:grid-cols-3"
                    >
                        <FooterColumn
                            title="Movies"
                            links={[
                                ["Now showing", f"/c/{slug}/movies"],
                                ["Coming soon", f"/c/{slug}/movies#coming-soon"]
                            ]}
                        />
                        <FooterColumn
                            title="Tickets"
                            links={[
                                ["Showtimes", f"/c/{slug}#showtimes"],
                                ["Book tickets", f"/c/{slug}#showtimes"],
                                ["My tickets", f"/c/{slug}/my-tickets"]
                            ]}
                        />
                        <FooterColumn
                            title="Cinemas"
                            links={[
                                ["Find a cinema", f"/c/{slug}/cinemas"],
                                ["Visit us", f"/c/{slug}/cinemas#visit-us"]
                            ]}
                        />
                    </div>
                    <div
                        className="mx-auto flex w-full max-w-5xl flex-wrap items-center justify-between gap-2 border-t px-4 py-4 text-sm text-muted-foreground"
                    >
                        <span className="font-medium text-foreground">
                            {place["name"]}
                        </span>
                        <span>Tickets by AfriCinemas</span>
                    </div>
                </footer>
            </div>
        </ThemeProvider>;
}
