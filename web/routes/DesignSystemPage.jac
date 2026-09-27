"""`/design-system[/:section]`: the living style guide (P0.8c, ADR-0002).

Hosts the shell components with demo data so browser tests and UI reviews exercise them
in the production bundle. `?surface=storefront` previews the tenant storefront theme
instead of the back-office one. Demo data only, never tenant data.
"""

import from "@jac/runtime" { Link, useParams, useLocation }
import from ...components.ui.button { Button }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..shell.AppShell { AppShell }
import from ..shell.BottomActionBar { BottomActionBar }
import from ..shell.ResponsiveTable { ResponsiveTable }
import from .NotFoundPage { NotFoundPage }

glob SECTIONS: dict[str, str] = {
         "overview": "Overview",
         "screenings": "Screenings",
         "staff": "Staff"
     },
     NAV: list[dict[str, str]] = [
         {"label": "Overview", "to": "/design-system"},
         {"label": "Screenings", "to": "/design-system/screenings"},
         {"label": "Staff", "to": "/design-system/staff"}
     ],
     COLUMNS: list[dict[str, str]] = [
         {"key": "movie", "label": "Movie"},
         {"key": "screen", "label": "Screen"},
         {"key": "starts", "label": "Starts"},
         {"key": "sold", "label": "Seats sold"},
         {"key": "status", "label": "Status"}
     ],
     ROWS: list[dict[str, str]] = [
         {
             "id": "1",
             "movie": "Rafiki",
             "screen": "Screen 1",
             "starts": "10:30",
             "sold": "84 / 120",
             "status": "On sale"
         },
         {
             "id": "2",
             "movie": "Nairobi Half Life",
             "screen": "Screen 2",
             "starts": "11:15",
             "sold": "40 / 90",
             "status": "On sale"
         },
         {
             "id": "3",
             "movie": "Supa Modo",
             "screen": "Screen 3",
             "starts": "12:00",
             "sold": "90 / 90",
             "status": "Sold out"
         },
         {
             "id": "4",
             "movie": "Atlantics",
             "screen": "Screen 1",
             "starts": "13:45",
             "sold": "12 / 120",
             "status": "On sale"
         },
         {
             "id": "5",
             "movie": "The Boy Who Harnessed the Wind",
             "screen": "IMAX",
             "starts": "14:30",
             "sold": "201 / 240",
             "status": "Filling fast"
         },
         {
             "id": "6",
             "movie": "Lionheart",
             "screen": "Screen 2",
             "starts": "15:10",
             "sold": "0 / 90",
             "status": "On sale"
         },
         {
             "id": "7",
             "movie": "Tsotsi",
             "screen": "Screen 3",
             "starts": "16:40",
             "sold": "66 / 90",
             "status": "On sale"
         },
         {
             "id": "8",
             "movie": "Timbuktu",
             "screen": "Screen 1",
             "starts": "18:00",
             "sold": "118 / 120",
             "status": "Filling fast"
         },
         {
             "id": "9",
             "movie": "Queen of Katwe",
             "screen": "IMAX",
             "starts": "19:30",
             "sold": "240 / 240",
             "status": "Sold out"
         },
         {
             "id": "10",
             "movie": "Mami Wata",
             "screen": "Screen 2",
             "starts": "21:15",
             "sold": "31 / 90",
             "status": "On sale"
         }
     ];

def:pub DesignSystemPage -> JsxElement {
    params = useParams();
    location = useLocation();
    section = params["section"] or "overview";
    title = SECTIONS[section];
    if not title {
        return <NotFoundPage/>;
    }
    # Browser globals have no stubs under `jac check`; correct at runtime (jac-cl-js-interop).
    query: any = new(URLSearchParams, location.search);  # jac:ignore[E1053,W2001,W1037]
    storefront = query.get("surface") == "storefront";
    surface = "storefront" if storefront else "backoffice";
    current = "storefront" if storefront else "back-office";
    other = "back-office" if storefront else "storefront";
    toggle_to = location.pathname
        if storefront
        else f"{location.pathname}?surface=storefront";
    return
        <ThemeProvider surface={surface}>
            <AppShell
                title={title}
                nav={NAV}
                actions={<BottomActionBar label="Booking summary">
                    <p className="min-w-0 text-sm">
                        <span className="font-semibold">2 seats</span>
                        <span className="text-muted-foreground"> · KES 1,200</span>
                    </p>
                    <Button className="ml-auto min-h-11 px-6">Continue</Button>
                </BottomActionBar>}
            >
                <p className="text-muted-foreground max-w-prose">
                    The living style guide: the responsive shell, table and action bar with demo data, in the {current} theme. Resize the window or switch your device to dark mode to see them adapt.
                </p>
                <div className="flex flex-wrap gap-3">
                    <Button asChild={True} variant="outline" className="min-h-11">
                        <Link to={toggle_to}>Preview the {other} theme</Link>
                    </Button>
                    <Button variant="secondary" className="min-h-11">Secondary</Button>
                    <Button variant="ghost" className="min-h-11">Ghost</Button>
                </div>
                <section
                    className="flex flex-col gap-3"
                    aria-labelledby="screenings-heading"
                >
                    <h2 id="screenings-heading" className="text-lg font-semibold">
                        Today's screenings
                    </h2>
                    <ResponsiveTable
                        columns={COLUMNS}
                        rows={ROWS}
                        caption="Today's screenings"
                    />
                </section>
                <p className="text-muted-foreground text-sm" data-testid="guide-end">
                    End of the style guide.
                </p>
            </AppShell>
        </ThemeProvider>;
}
