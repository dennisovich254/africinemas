"""Responsive application shell (P0.8c): a sidebar on desktop, a drawer on phones.

At `lg` and wider the navigation is a sticky sidebar. Below `lg` it moves into a
left-hand drawer (a Radix dialog: focus is trapped while open and returns to the menu
button on close). Colours come only from theme tokens, via the shadcn variables.
`actions` (typically a BottomActionBar) is pinned under the page content. `account`
(switch cinema, sign out) sits at the foot of the sidebar and of the drawer.
"""

import from react { useState }
import from "@jac/runtime" { Link, useLocation }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Menu01Icon, Cancel01Icon }
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

glob LINK_CLASSES: str = "flex min-h-11 items-center rounded-md px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground aria-[current=page]:bg-muted aria-[current=page]:text-foreground";

# `on_navigate: any` is a click handler passed through to each link.
def active_link(items: list[dict[str, str]], current: str) -> str {
    # The item the current page belongs to: the longest link that is the page or a page
    # under it. So /app/nova/screens/42 marks Screens, while Overview (/app/nova) is
    # marked on its own page only.
    best = "";
    for item in items {
        to = item["to"];
        if (current == to or current.startswith(to + "/")) and len(to) > len(best) {
            best = to;
        }
    }
    return best;
}

def NavLinks(
    items: list[dict[str, str]],
    current: str,
    on_navigate: any = None  # jac:ignore[W1037]
) -> JsxElement {
    active = active_link(items, current);
    return
        <nav aria-label="Main">
            <ul className="flex flex-col gap-1">
                {[
                    <li key={item["to"]}>
                        <Link
                            to={item["to"]}
                            aria-current={"page" if item["to"] == active else None}
                            className={LINK_CLASSES}
                            onClick={on_navigate}
                        >
                            {item["label"]}
                        </Link>
                    </li> for item in items
                ]}
            </ul>
        </nav>;
}

def Brand(name: str, home: str, logo: str = "") -> JsxElement {
    # The cinema's published logo (P3.8b) beside its name, or the name alone.
    return
        <Link
            to={home}
            className="font-display inline-flex min-h-11 min-w-0 items-center gap-2 text-2xl leading-none"
        >
            {logo
                and <img
                    src={logo}
                    alt=""
                    data-testid="brand-logo"
                    className="h-7 w-auto max-w-24 shrink-0"
                />}
            <span className="truncate">{name}</span>
        </Link>;
}

# `children` and `actions` are pass-through JSX (jac-cl-organization idiom).
def:pub AppShell(  # jac:ignore[W3030] the shell: title, nav, brand, logo, home and three slots
    title: str,
    nav: list[dict[str, str]],
    brand: str = "AfriCinemas",
    home: str = "/",
    logo: str = "",
    children: any = None,  # jac:ignore[W1037]
    actions: any = None,  # jac:ignore[W1037]
    account: any = None,  # jac:ignore[W1037]
    title_hidden: bool = False
) -> JsxElement {
    # title_hidden: the page shows its own heading (the back office's home, P7.4); the
    # title stays the page's h1 for screen readers.
    location = useLocation();
    [open, set_open] = useState(False);
    close_drawer = lambda { set_open(False); };
    return
        <div className="flex min-h-svh" data-testid="app-shell">
            <a
                href="#content"
                className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-md focus:bg-card focus:px-4 focus:py-3 focus:text-sm focus:font-medium"
            >
                Skip to content
            </a>
            <aside
                data-testid="shell-sidebar"
                className="sticky top-0 hidden h-svh w-64 shrink-0 flex-col gap-6 overflow-y-auto border-r bg-card p-4 lg:flex"
            >
                <Brand name={brand} home={home} logo={logo}/>
                <NavLinks items={nav} current={location.pathname}/>
                {account and <div className="mt-auto border-t pt-4">{account}</div>}
            </aside>
            <div className="flex min-w-0 flex-1 flex-col">
                <header
                    className="sticky top-0 z-30 flex h-14 items-center gap-2 border-b bg-card px-2 lg:hidden"
                >
                    <Sheet open={open} onOpenChange={set_open}>
                        <SheetTrigger asChild={True}>
                            <Button
                                variant="ghost"
                                size="icon"
                                className="size-11"
                                aria-label="Open navigation"
                                data-testid="shell-menu-button"
                            >
                                <HugeiconsIcon icon={Menu01Icon} strokeWidth={2}/>
                            </Button>
                        </SheetTrigger>
                        <SheetContent
                            side="left"
                            showCloseButton={False}
                            className="w-72 gap-0 bg-card p-0"
                            data-testid="shell-drawer"
                        >
                            <SheetHeader
                                className="flex-row items-center justify-between border-b py-2 pr-2"
                            >
                                <SheetTitle
                                    className="font-display text-2xl leading-none"
                                >
                                    {brand}
                                </SheetTitle>
                                <SheetClose asChild={True}>
                                    <Button
                                        variant="ghost"
                                        size="icon"
                                        className="size-11"
                                        aria-label="Close navigation"
                                    >
                                        <HugeiconsIcon
                                            icon={Cancel01Icon}
                                            strokeWidth={2}
                                        />
                                    </Button>
                                </SheetClose>
                            </SheetHeader>
                            <SheetDescription className="sr-only">
                                Main navigation
                            </SheetDescription>
                            <div className="p-2">
                                <NavLinks
                                    items={nav}
                                    current={location.pathname}
                                    on_navigate={close_drawer}
                                />
                            </div>
                            {account
                                and <div className="mt-auto border-t p-2">
                                    {account}
                                </div>}
                        </SheetContent>
                    </Sheet>
                    <Brand name={brand} home={home} logo={logo}/>
                </header>
                <main
                    id="content"
                    tabIndex={-1}
                    className="flex-1 px-4 py-6 lg:px-8 lg:py-8"
                >
                    <div className="mx-auto flex w-full max-w-5xl flex-col gap-6">
                        <h1
                            className={"sr-only"
                                if title_hidden
                                else "font-display text-4xl leading-none lg:text-5xl"}
                            data-testid="shell-title"
                        >
                            {title}
                        </h1>
                        {children}
                    </div>
                </main>
                {actions}
            </div>
        </div>;
}
