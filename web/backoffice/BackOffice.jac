"""`/app/:slug[/:section]`: a cinema's back-office (P2.7b).

The navigation lists only the sections the member's roles allow (nav.jac), from
`my_access`, which the server rebuilds from the graph on every call (ADR-0008). Staff
actions need an open shift (ADR-0006), so until one is open every section shows a
"Start shift" banner. Signing out ends the shift.

Venues (P3.7a) manages the cinema's locations; Screens (P3.3, P3.7a) manages each
venue's screens and opens their seat layout designer;
Movies (P3.7a) lists, adds and edits the cinema's films; Screenings and Prices (P3.7b)
hold the programme and the price list; Staff (P3.7c) invites and manages the team; Settings
holds the cinema's branding (P3.8b), and the header shows its published logo; the other
sections arrive with their phases, and for now each shows what it will hold.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from ..shell.AppLink { AppLink }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Clock01Icon }
import from ...components.ui.button { Button }
import from ...components.ui.empty {
    Empty,
    EmptyHeader,
    EmptyTitle,
    EmptyDescription,
    EmptyContent
}
import from ...components.ui.spinner { Spinner }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..shell.AppShell { AppShell }
import from core.tenancy.tenant_api { my_access, start_shift }  # jac:ignore[W2037] authenticated endpoint
import from .nav { web_address, nav_for, section_label, section_path, role_label }
import from .PlainLayout { PlainLayout, AccountActions }
import from .ScreensSection { ScreensSection }
import from .SeatDesigner { SeatDesigner }
import from .BrandingSection { BrandingSection }
import from .HomePageSection { HomePageSection }
import from .ConnectSection { ConnectSection }
import from .MoviesSection { MoviesSection }
import from .VenuesSection { VenuesSection }
import from .ScreeningsSection { ScreeningsSection }
import from .ScannerSection { ScannerSection }
import from .SetupGuide { SetupGuide }
import from .BoxOfficeSection { BoxOfficeSection }
import from .PricesSection { PricesSection }
import from .SnackProductsPage { SnackProductsPage }
import from .SnackProductEditor { SnackProductEditor }
import from .SnackCategoriesPage { SnackCategoriesPage }
import from .SnackExtrasPage { SnackExtrasPage }
import from .SnackStockPage { SnackStockPage }
import from .SnackGlassesPage { SnackGlassesPage }
import from .SnackImportPage { SnackImportPage }
import from .StaffSection { StaffSection }
import from .ReportsSection { ReportsSection }
import from .StaffHome { StaffHome }
import from .AuditSection { AuditSection }
import from .HelpSection { HelpSection }
import from ..auth.EmailCheck { EmailCheckBanner }
import from .SiteInfoSection { SiteInfoSection }
import from .PoliciesSection { PoliciesSection }
import from .DocumentsSection { DocumentsSection }
import from .VerificationSection { VerificationSection }
import from ..support.live { use_waiting_for_cinema }
import from .SnackCounterSection { SnackCounterSection }
import from .ProfileSection { ProfileSection }
import from .AgreementSection { AgreementSection, AgreementNotice }
import from .BillingSection { BillingSection }
import from .BillingNotice { BillingNotice }
import from .ReconciliationSection { ReconciliationSection, use_open_exceptions }
import from .PaymentsSection { PaymentsSection }
import from .MovieEditor { MovieEditor }
import from core.theming.branding_api { public_branding }

glob SECTION_PREVIEW: dict[str, str] = {
         "screenings": "Set up your screens, seat layouts, movies and showtimes here.",
         "box-office": "Sell tickets at the counter and look up bookings here.",
         "scanner": "Scan customers' QR tickets at the door here.",
         "staff": "Invite your team and choose what each person can do here.",
         "settings": "Your cinema's name, branding and payment details live here."
     };

def ShiftBanner(busy: bool, failed: bool, on_start: any) -> JsxElement {  # jac:ignore[W1037]
    # One row above every section while the member is off shift (ADR-0006); wraps on a
    # phone, the button last.
    return
        <div
            role="region"
            aria-label="Shift"
            data-testid="shift-banner"
            className="flex flex-wrap items-center gap-3 rounded-xl bg-card px-4 py-3 ring-1 ring-foreground/10"
        >
            <HugeiconsIcon
                icon={Clock01Icon}
                strokeWidth={2}
                className="shrink-0 text-muted-foreground"
                aria-hidden="true"
            />
            <p className="min-w-0 flex-1 text-sm">
                {"We couldn't start your shift. Try again."
                    if failed
                    else "You're off shift. Start it to sell, scan tickets and make changes; it ends when you sign out."}
            </p>
            <Button className="min-h-11 px-5" disabled={busy} onClick={on_start}>
                {busy and <Spinner aria-hidden="true"/>}{"Starting…"
                    if busy
                    else "Start shift"}
            </Button>
        </div>;
}

def role_keys(assignments: list[dict[str, any]]) -> list[str] {  # jac:ignore[W1037]
    # [{"role": "usher", "venue_ids": ["venue-1"]}] -> ["usher@venue-1"]
    keys: list[str] = [];
    for a in assignments {
        if a["venue_ids"] {
            for v in a["venue_ids"] {
                keys.append(f"{a['role']}@{v}");
            }
        } else {
            keys.append(a["role"]);
        }
    }
    return keys;
}

def SectionPreview(section: str, slug: str) -> JsxElement {
    return
        <Empty className="border">
            <EmptyHeader>
                <EmptyTitle>
                    <h2 className="text-base font-semibold">Coming soon</h2>
                </EmptyTitle>
                <EmptyDescription>{SECTION_PREVIEW[section]}</EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
                <Button asChild={True} variant="outline" className="min-h-11">
                    <AppLink to={section_path(slug, "")}>Back to overview</AppLink>
                </Button>
            </EmptyContent>
        </Empty>;
}

def NoAccess(slug: str) -> JsxElement {
    return
        <Empty className="border" data-testid="no-access">
            <EmptyHeader>
                <EmptyTitle>
                    <h2 className="text-base font-semibold">
                        This section isn't part of your role
                    </h2>
                </EmptyTitle>
                <EmptyDescription>
                    Ask your cinema's owner or an admin if you need access.
                </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
                <Button asChild={True} variant="outline" className="min-h-11">
                    <AppLink to={section_path(slug, "")}>Back to overview</AppLink>
                </Button>
            </EmptyContent>
        </Empty>;
}

def SettingsPage(
    slug: str,
    tab: str,
    cinema: str,
    branding: any  # jac:ignore[W1037] the Branding page, drawn by BackOffice
) -> JsxElement {
    # Settings: Branding (/app/:slug/settings), the home page
    # (/app/:slug/settings/home-page, P4.1b), the website information
    # (/app/:slug/settings/website, P14.3a), the policies
    # (/app/:slug/settings/policies, P14.3b), the public documents
    # (/app/:slug/settings/documents, P14.3d), the AI chat connector
    # (/app/:slug/settings/ai-chat, P8.3) and the cinema's own M-Pesa
    # (/app/:slug/settings/payments, P15.3), as tabs.
    tabs = [
        ("", "Branding"),
        ("home-page", "Home page"),
        ("website", "Website information"),
        ("policies", "Policies"),
        ("documents", "Documents"),
        ("payments", "Payments"),
        ("ai-chat", "AI chat")
    ];
    return
        <div className="flex flex-col gap-6">
            <nav aria-label="Settings" className="flex gap-2 overflow-x-auto border-b">
                {[
                    <AppLink
                        key={key or "branding"}
                        to={section_path(slug, "settings") + (f"/{key}" if key else "")}
                        testid={f"settings-tab-{key or 'branding'}"}
                        current={key == tab}
                        className={"-mb-px inline-flex min-h-11 shrink-0 items-center whitespace-nowrap border-b-2 px-3 text-sm font-medium "
                            + (
                                "border-primary text-foreground"
                                    if key == tab
                                    else "border-transparent text-muted-foreground hover:text-foreground"
                            )}
                    >
                        {label}
                    </AppLink> for (key, label) in tabs
                ]}
            </nav>
            {tab == "home-page"
                and <div className="flex flex-col gap-6">
                    <h2 className="text-xl font-semibold">Home page</h2>
                    <HomePageSection slug={slug}/>
                </div>}
            {tab == "ai-chat" and <ConnectSection slug={slug} cinema={cinema}/>}
            {tab == "website"
                and <div className="flex flex-col gap-6">
                    <h2 className="text-xl font-semibold">Website information</h2>
                    <SiteInfoSection slug={slug}/>
                </div>}
            {tab == "policies"
                and <div className="flex flex-col gap-6">
                    <h2 className="text-xl font-semibold">Policies</h2>
                    <PoliciesSection slug={slug}/>
                </div>}
            {tab == "documents"
                and <div className="flex flex-col gap-6">
                    <h2 className="text-xl font-semibold">Documents</h2>
                    <DocumentsSection slug={slug}/>
                </div>}
            {tab == "payments"
                and <div className="flex flex-col gap-6">
                    <h2 className="text-xl font-semibold">Payments</h2>
                    <PaymentsSection slug={slug}/>
                </div>}
            {tab
                not in [
                    "home-page",
                    "ai-chat",
                    "website",
                    "policies",
                    "documents",
                    "payments"
                ]
                and branding}
        </div>;
}

def:pub BackOffice -> JsxElement {
    params = useParams();
    slug: str = params["slug"] or "";
    section: str = params["section"] or "";
    # One item of a section: a screen's seat layout (/app/:slug/screens/:item) or a
    # movie (/app/:slug/movies/:item, "new" to add one).
    item: str = params["item"] or "";
    auditorium_id: str = item if section == "screens" else "";
    movie_id: str = item if section == "movies" else "";
    [access, set_access] = useState(None);
    [missing, set_missing] = useState(False);
    [failed, set_failed] = useState(False);
    [shift_open, set_shift_open] = useState(False);
    [starting, set_starting] = useState(False);
    [start_failed, set_start_failed] = useState(False);
    [logo, set_logo] = useState("");

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await my_access(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("my_access failed", e);
            set_failed(True);
            return;
        }
        if not answer["ok"] {
            set_missing(True);
            return;
        }
        set_access(answer);
        set_shift_open(answer["shift_open"]);
        # The cinema's published logo for the header (P3.8b); the look stays the platform's.
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_branding(slug);
        } except Exception as e {
            console.warn("public_branding failed", e);
        }
        if shown and shown["ok"] {
            set_logo(shown["branding"]["logo"]);
        }
    }

    async def begin_shift {
        answer: any = None;  # jac:ignore[W1037]
        set_starting(True);
        set_start_failed(False);
        try {
            answer = await start_shift(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("start_shift failed", e);
        }
        set_starting(False);
        if answer and answer["ok"] {
            set_shift_open(True);
        } else {
            set_start_failed(True);
        }
    }

    useEffect(
        lambda {
            set_access(None);
            set_missing(False);
            set_failed(False);
            load();
        },
        [slug]
    );
    # Help's count: requests AfriCinemas has answered (P13.5a), for those who ask.
    seen: dict[str, any] = access or {};  # jac:ignore[W1037]
    held: list[str] = seen["permissions"] or [];
    may_ask: bool = shift_open and "support.request" in held;
    answered = use_waiting_for_cinema(slug, may_ask);
    # Reconciliation's count: what's open, for those who resolve it (P15.6).
    unresolved = use_open_exceptions(slug, "financial_reports.read" in held);

    if missing or failed {
        return
            <PlainLayout
                title={"Cinema not found" if missing else "Something went wrong"}
                account={<AccountActions slugs={[]}/>}
            >
                <p className="text-muted-foreground" data-testid="cinema-not-found">
                    {"This cinema doesn't exist, or you're not on its staff."
                        if missing
                        else "We couldn't load this cinema. Refresh the page to try again."}
                </p>
                <Button
                    asChild={True}
                    variant="outline"
                    className="min-h-11 self-start"
                >
                    <AppLink to="/app">Your cinemas</AppLink>
                </Button>
            </PlainLayout>;
    }
    if access is None {
        return
            <ThemeProvider surface="backoffice">
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
    me: dict[str, any] = access;  # jac:ignore[W1037]
    permissions: list[str] = me["permissions"];
    nav = nav_for(slug, permissions);
    counts: dict[str, int] = {"help": answered, "reconciliation": unresolved};
    nav = [
        {** item, "count": str(counts[item["key"]])}
            if counts.get(item["key"], 0)
            else item for item in nav
    ];
    allowed = section in [item["key"] for item in nav];
    title = section_label(section) or "Overview";
    if auditorium_id {
        title = "Seat layout";
    } elif movie_id {
        title = "New movie" if movie_id == "new" else "Movie";
    } elif section == "snacks" and item {
        title = "Snack categories"
            if item == "categories"
            else (
                "3D glasses"
                    if item == "glasses"
                    else ("New product" if item == "new" else "Snack product")
            );
    }
    content: any = None;  # jac:ignore[W1037]
    if not allowed {
        content = <NoAccess slug={slug}/>;
    } elif section == "" {
        content = <StaffHome
            slug={slug}
            shift_open={shift_open}
            permissions={permissions}
            roles={[role_label(k) for k in role_keys(me["assignments"])]}
        />;
    } elif auditorium_id {
        # key: a different screen gets a fresh designer, never the last one's grid.
        content = <SeatDesigner
            key={auditorium_id}
            slug={slug}
            auditorium_id={auditorium_id}
            permissions={permissions}
        />;
    } elif section == "venues" {
        content = <VenuesSection slug={slug}/>;
    } elif section == "screens" {
        content = <ScreensSection slug={slug} permissions={permissions}/>;
    } elif movie_id {
        # key: another movie gets a fresh form, never the last one's fields.
        content = <MovieEditor key={movie_id} slug={slug} movie_id={movie_id}/>;
    } elif section == "movies" {
        content = <MoviesSection slug={slug} permissions={permissions}/>;
    } elif section == "screenings" {
        content = <ScreeningsSection slug={slug}/>;
    } elif section == "box-office" {
        content = <BoxOfficeSection slug={slug} shift_open={shift_open}/>;
    } elif section == "scanner" {
        content = <ScannerSection
            slug={slug}
            shift_open={shift_open}
            permissions={permissions}
        />;
    } elif section == "snack-counter" {
        content = <SnackCounterSection slug={slug} shift_open={shift_open}/>;
    } elif section == "snacks" and item == "import" {
        content = <SnackImportPage slug={slug} permissions={permissions}/>;
    } elif section == "snacks" and item == "stock" {
        content = <SnackStockPage slug={slug} permissions={permissions}/>;
    } elif section == "snacks" and item == "glasses" {
        content = <SnackGlassesPage slug={slug} permissions={permissions}/>;
    } elif section == "snacks" and item == "extras" {
        content = <SnackExtrasPage slug={slug} permissions={permissions}/>;
    } elif section == "snacks" and item == "categories" {
        content = <SnackCategoriesPage slug={slug} permissions={permissions}/>;
    } elif section == "snacks" and item {
        # key: another product gets a fresh editor, never the last one's fields.
        content = <SnackProductEditor
            key={item}
            slug={slug}
            product_id={item}
            permissions={permissions}
        />;
    } elif section == "snacks" {
        content = <SnackProductsPage slug={slug} permissions={permissions}/>;
    } elif section == "prices" {
        content = <PricesSection slug={slug}/>;
    } elif section == "staff" {
        content = <StaffSection slug={slug} permissions={permissions}/>;
    } elif section == "reports" {
        content = <ReportsSection slug={slug} shift_open={shift_open}/>;
    } elif section == "audit" {
        content = <AuditSection slug={slug} shift_open={shift_open}/>;
    } elif section == "verification" {
        content = <VerificationSection slug={slug}/>;
    } elif section == "help" {
        content = <HelpSection slug={slug} shift_open={shift_open} item={item}/>;
    } elif section == "profile" {
        content = <ProfileSection slug={slug}/>;
    } elif section == "reconciliation" {
        content = <ReconciliationSection slug={slug}/>;
    } elif section == "billing" {
        content = <BillingSection slug={slug}/>;
    } elif section == "agreement" {
        content = <AgreementSection slug={slug} cinema={me["name"]}/>;
    } elif section == "settings" {
        content = <SettingsPage
            slug={slug}
            tab={item}
            cinema={me["name"]}
            branding={<BrandingSection slug={slug} cinema={me["name"]}/>}
        />;
    } else {
        content = <SectionPreview section={section} slug={slug}/>;
    }
    return
        <ThemeProvider surface="backoffice">
            <AppShell
                title={title}
                nav={nav}
                brand={me["name"]}
                logo={logo}
                verified={me["verified_at"] or ""}
                home={section_path(slug, "")}
                account={<AccountActions slugs={[slug]} switch_to="/app"/>}
                title_hidden={section == "" and allowed}
            >
                {section != ""
                    and <p className="-mt-3 text-sm text-muted-foreground">
                        {web_address(slug)}
                    </p>}
                {allowed and <AgreementNotice slug={slug} section={section}/>}
                <BillingNotice slug={slug} section={section}/>
                {not shift_open
                    and allowed
                    and <ShiftBanner
                        busy={starting}
                        failed={start_failed}
                        on_start={begin_shift}
                    />}
                {shift_open
                    and allowed
                    and "venues.configure" in permissions
                    and <SetupGuide
                        slug={slug}
                        section={section}
                        page={f"{section}/{item}"}
                    />}
                <EmailCheckBanner/>
                {content}
            </AppShell>
        </ThemeProvider>;
}
