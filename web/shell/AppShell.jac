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
import from "@hugeicons/core-free-icons" {
    Menu01Icon,
    Cancel01Icon,
    Home01Icon,
    ChartLineData01Icon,
    Building03Icon,
    SeatSelectorIcon,
    Film02Icon,
    Calendar03Icon,
    Tag01Icon,
    Ticket02Icon,
    QrCode01Icon,
    PackageDeliveredIcon,
    UserGroupIcon,
    FileSearchIcon,
    IdVerifiedIcon,
    CheckmarkBadge01Icon,
    Settings01Icon,
    Projector01Icon,
    HelpCircleIcon,
    CustomerSupportIcon,
    UserCircleIcon,
    CheckListIcon,
    LegalDocument01Icon,
    Invoice01Icon
}
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

glob LINK_CLASSES: str = "flex min-h-11 items-center gap-3 rounded-md px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground aria-[current=page]:bg-muted aria-[current=page]:text-foreground";

# Each back-office section's icon, by its key (web/backoffice/nav.jac), and the platform
# console's (web/platform/PlatformConsole.jac); a link whose key isn't here shows its
# label alone.
glob NAV_ICONS: dict[str, any] = {  # jac:ignore[W1037]
         "": Home01Icon,
         "reports": ChartLineData01Icon,
         "venues": Building03Icon,
         "screens": SeatSelectorIcon,
         "movies": Film02Icon,
         "screenings": Calendar03Icon,
         "prices": Tag01Icon,
         "box-office": Ticket02Icon,
         "scanner": QrCode01Icon,
         "snack-counter": PackageDeliveredIcon,
         "staff": UserGroupIcon,
         "audit": FileSearchIcon,
         "verification": IdVerifiedIcon,
         "settings": Settings01Icon,
         "cinemas": Projector01Icon,
         "reviews": IdVerifiedIcon,
         "help": HelpCircleIcon,
         "support": CustomerSupportIcon,
         "profile": UserCircleIcon,
         "registrations": CheckListIcon,
         "fees": Tag01Icon,
         "agreement": LegalDocument01Icon,
         "billing": Invoice01Icon
     };

def nav_icon(section: any) -> any {  # jac:ignore[W1037]
    if section == "snacks" {
        return
            <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={1.75}
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
                focusable="false"
                className="shrink-0"
            >
                <path
                    d="M5 10C2 8 3 5 6 5C6 2 10 1 12 4C14 1 18 2 18 5C21 5 22 8 19 10"
                />
                <path d="M4 10H20L18 22H6L4 10Z"/>
                <rect x="5.5" y="11.5" width="5" height="4" rx="1.3"/>
                <rect x="13.5" y="11.5" width="5" height="4" rx="1.3"/>
                <path d="M10.5 13H13.5M9 18L9.5 22M15 18L14.5 22"/>
            </svg>;
    }
    if not isinstance(section, str) or section not in NAV_ICONS {
        return None;
    }
    return
        <HugeiconsIcon
            icon={NAV_ICONS[section]}
            size={18}
            strokeWidth={1.75}
            aria-hidden="true"
        />;
}

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
                            {nav_icon(item["key"])}{item["label"]}{item["count"]
                                and <span
                                    className="ml-auto rounded-full bg-primary px-2 text-xs font-semibold text-primary-foreground tabular-nums"
                                    data-testid={f"nav-count-{item['key']}"}
                                >
                                    {item["count"]}
                                    <span className="sr-only"> waiting for you</span>
                                </span>}
                        </Link>
                    </li> for item in items
                ]}
            </ul>
        </nav>;
}

def Verified(verified: str) -> JsxElement {
    # The cinema's Verified mark (P14.5), with the date AfriCinemas checked it.
    if not verified {
        return <span className="hidden"/>;
    }
    return
        <span
            className="inline-flex shrink-0 items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary"
            title={f"Verified by AfriCinemas on {verified[:10]}"}
            data-testid="backoffice-verified"
        >
            <HugeiconsIcon
                icon={CheckmarkBadge01Icon}
                size={14}
                strokeWidth={2}
                aria-hidden="true"
            />
            Verified
        </span>;
}

def Brand(name: str, home: str, logo: str = "", verified: str = "") -> JsxElement {
    # The cinema's published logo (P3.8b) beside its name, or the name alone; and its
    # Verified mark once AfriCinemas has checked it (P14.5).
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
            <Verified verified={verified}/>
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
    title_hidden: bool = False,
    verified: str = ""
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
                <Brand name={brand} home={home} logo={logo} verified={verified}/>
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
                            <div
                                className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-2"
                                data-testid="drawer-links"
                            >
                                <NavLinks
                                    items={nav}
                                    current={location.pathname}
                                    on_navigate={close_drawer}
                                />
                            </div>
                            {account
                                and <div className="shrink-0 border-t p-2">
                                    {account}
                                </div>}
                        </SheetContent>
                    </Sheet>
                    <Brand name={brand} home={home} logo={logo} verified={verified}/>
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
