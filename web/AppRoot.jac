"""Root UI component shared by the web app and the desktop app.

Both entry points (main.jac and desktop/main.jac) render <AppRoot />, so every
screen is written once (docs/adr/0001-desktop-reuses-web-ui.md). It owns the only
router: manual routing, no `pages/` directory (docs/adr/0002-manual-routing-in-shared-approot.md).
The back-office (`/app...`) sits under one AuthGuard: signed-out visitors go to /login.
The AfriCinemas platform console is a site of its own, on its own address
(`admin.<domain>`, P13.1b; web/site.jac) with its own sign-in and accounts (P13.1b.a):
that address offers only the console's pages, and the main one none of them.
A cinema's public storefront is on its own address too (`<slug>.<domain>`, P13.1b.c),
with its movies at `/m/:movie` and showtimes at `/s/:screening` (P4.1); the old form,
`/c/:slug/...`, goes there from the main address, and is the storefront on any address
outside the domain (a tunnel, 127.0.0.1, the desktop app), as before. The server says
which site an address is (web/site.jac); until it has, the page waits.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { Router, Routes, Route, AuthGuard }
import from .routes.LandingPage { LandingPage }
import from .auth.LoginPage { LoginPage }
import from .auth.SignupPage { SignupPage }
import from .backoffice.CinemaPicker { CinemaPicker }
import from .backoffice.NewCinemaWizard { NewCinemaWizard }
import from .backoffice.BackOffice { BackOffice }
import from .routes.DesignSystemPage { DesignSystemPage }
import from .routes.NotFoundPage { NotFoundPage }
import from .storefront.StorefrontPage { StorefrontPage }
import from .storefront.MoviePage { MoviePage }
import from .storefront.ScreeningPage { ScreeningPage }
import from .storefront.TicketsPage { TicketsPage }
import from .storefront.MyTicketsPage { MyTicketsPage }
import from .storefront.CustomerAuthPages { CustomerSignInPage, CustomerSignUpPage }
import from .storefront.AccountPage { AccountPage }
import from .oauth.AuthorizePage { AuthorizePage }
import from .storefront.MoviesPage { MoviesPage }
import from .storefront.CinemasPage { CinemasPage }
import from .storefront.PolicyPage { PolicyPage }
import from .storefront.DocumentPage { DocumentPage }
import from .auth.InvitePage { InvitePage }
import from .auth.EmailCheck { VerifyEmailPage }
import from .platform.PlatformConsole { PlatformConsole }
import from .platform.PlatformAuthPages { PlatformSignInPage, PlatformJoinPage }
import from .auth.token_slots { install_token_slots }
import from .theme.ThemeProvider { ThemeProvider }
import from .preview { install_preview, previewing }
import from .site { known_site, load_site, current_site, storefront_address }

# The back office and each cinema's storefront keep their own sign-in (improvements #25),
# set up when this module loads, before any page asks the server anything.
glob TOKEN_SLOTS: bool = install_token_slots(),
     # A cinema's team previewing its storefront before it goes live (P14.1).
     PREVIEW: bool = install_preview();

def PlatformSite -> JsxElement {
    # The platform's address: the console, its sign-in and the page a join link opens.
    return
        <Router>
            <Routes>
                <Route path="/sign-in" element={<PlatformSignInPage/>}/>
                <Route path="/join" element={<PlatformJoinPage/>}/>
                <Route element={<AuthGuard redirect="/sign-in"/>}>
                    <Route path="/" element={<PlatformConsole/>}/>
                    <Route path="/:section" element={<PlatformConsole/>}/>
                    <Route path="/:section/:item" element={<PlatformConsole/>}/>
                </Route>
                <Route path="*" element={<NotFoundPage/>}/>
            </Routes>
        </Router>;
}

def Waiting -> JsxElement {
    # The frame while the server says which site this is, or a page moves to its own
    # address: themed, so a dark device never sees a light frame.
    return
        <ThemeProvider surface="backoffice">
            <main aria-busy="true" className="min-h-svh bg-background"/>
        </ThemeProvider>;
}

def PreviewBanner -> JsxElement {
    # Over a storefront seen with a preview pass: who can see it, and when it goes public.
    return
        <div
            role="status"
            data-testid="preview-banner"
            className="sticky top-0 z-50 bg-foreground px-4 py-2 text-center text-sm text-background"
        >
            Only your team can see this. It goes public once AfriCinemas has verified your cinema.
        </div>;
}

def StorefrontSite -> JsxElement {
    # A cinema's own address: its storefront alone, the cinema named by the address.
    return
        <Router>
            <Routes>
                <Route path="/" element={<StorefrontPage/>}/>
                <Route path="/movies" element={<MoviesPage/>}/>
                <Route path="/cinemas" element={<CinemasPage/>}/>
                <Route path="/policies/:kind" element={<PolicyPage/>}/>
                <Route path="/documents/:document" element={<DocumentPage/>}/>
                <Route path="/m/:movie" element={<MoviePage/>}/>
                <Route path="/s/:screening" element={<ScreeningPage/>}/>
                <Route path="/tickets/:token" element={<TicketsPage/>}/>
                <Route path="/my-tickets" element={<MyTicketsPage/>}/>
                <Route path="/sign-in" element={<CustomerSignInPage/>}/>
                <Route path="/sign-up" element={<CustomerSignUpPage/>}/>
                <Route path="/account" element={<AccountPage/>}/>
                <Route path="/oauth/authorize" element={<AuthorizePage/>}/>
                <Route path="*" element={<NotFoundPage/>}/>
            </Routes>
        </Router>;
}

def _go_to(address: str) {
    win: any = window;  # jac:ignore[W1037,W2001]
    win.location.replace(address);
}

def OnOwnAddress -> JsxElement {
    # /c/<slug>/... on the main address: the same page on the cinema's own address.
    win: any = window;  # jac:ignore[W1037,W2001]
    parts: list[str] = win.location.pathname.split("/");
    rest = "/" + "/".join(parts[3:]) if len(parts) > 3 else "";
    def start {
        _go_to(
            storefront_address(parts[2], rest + win.location.search + win.location.hash)
        );
    }
    useEffect(start, []);
    return <Waiting/>;
}

def ConsentOnOwnAddress -> JsxElement {
    # Claude's consent page for a cinema's connector (/mcp/c/<slug>) is on that
    # cinema's address, where its customers are signed in; anything else is answered
    # here, as before.
    win: any = window;  # jac:ignore[W1037,W2001]
    params: any = new(win.URLSearchParams, win.location.search);  # jac:ignore[W1037]
    resource: str = params.get("resource") or "";
    parts: list[str] = resource.split("/");
    slug: str = parts[len(parts) - 1]
        if len(parts) >= 3
            and parts[len(parts) - 3] == "mcp"
            and parts[len(parts) - 2] == "c"
        else "";
    def start {
        if slug {
            _go_to(storefront_address(slug, "/oauth/authorize" + win.location.search));
        }
    }
    useEffect(start, []);
    if slug {
        return <Waiting/>;
    }
    return <AuthorizePage/>;
}

def NoSite -> JsxElement {
    # An address under the domain that's no cinema's: nothing to go back to.
    return
        <Router>
            <Routes>
                <Route path="*" element={<NotFoundPage home={False}/>}/>
            </Routes>
        </Router>;
}

def MainSite(own_addresses: bool) -> JsxElement {
    # The back office, and the storefronts under /c/<slug>: on the main address they
    # go on to each cinema's own (`own_addresses`), anywhere else they're served here.
    return
        <Router>
            <Routes>
                <Route path="/" element={<LandingPage/>}/>
                <Route path="/design-system" element={<DesignSystemPage/>}/>
                <Route path="/design-system/:section" element={<DesignSystemPage/>}/>
                <Route path="/login" element={<LoginPage/>}/>
                <Route path="/signup" element={<SignupPage/>}/>
                <Route path="/verify-email" element={<VerifyEmailPage/>}/>
                {own_addresses and <Route path="/c/:slug/*" element={<OnOwnAddress/>}/>}
                {own_addresses and <Route path="/c/:slug" element={<OnOwnAddress/>}/>}
                {own_addresses
                    and <Route
                        path="/oauth/authorize"
                        element={<ConsentOnOwnAddress/>}
                    />}
                {not own_addresses
                    and <Route path="/c/:slug" element={<StorefrontPage/>}/>}
                {not own_addresses
                    and <Route path="/c/:slug/movies" element={<MoviesPage/>}/>}
                {not own_addresses
                    and <Route path="/c/:slug/cinemas" element={<CinemasPage/>}/>}
                {not own_addresses
                    and <Route path="/c/:slug/policies/:kind" element={<PolicyPage/>}/>}
                {not own_addresses
                    and <Route
                        path="/c/:slug/documents/:document"
                        element={<DocumentPage/>}
                    />}
                {not own_addresses
                    and <Route path="/c/:slug/m/:movie" element={<MoviePage/>}/>}
                {not own_addresses
                    and <Route
                        path="/c/:slug/s/:screening"
                        element={<ScreeningPage/>}
                    />}
                {not own_addresses
                    and <Route
                        path="/c/:slug/tickets/:token"
                        element={<TicketsPage/>}
                    />}
                {not own_addresses
                    and <Route path="/c/:slug/my-tickets" element={<MyTicketsPage/>}/>}
                {not own_addresses
                    and <Route
                        path="/c/:slug/sign-in"
                        element={<CustomerSignInPage/>}
                    />}
                {not own_addresses
                    and <Route
                        path="/c/:slug/sign-up"
                        element={<CustomerSignUpPage/>}
                    />}
                {not own_addresses
                    and <Route path="/c/:slug/account" element={<AccountPage/>}/>}
                {not own_addresses
                    and <Route path="/oauth/authorize" element={<AuthorizePage/>}/>}
                <Route path="/invite/:token" element={<InvitePage/>}/>
                <Route element={<AuthGuard redirect="/login"/>}>
                    <Route path="/app" element={<CinemaPicker/>}/>
                    <Route path="/app/new" element={<NewCinemaWizard/>}/>
                    <Route path="/app/:slug" element={<BackOffice/>}/>
                    <Route path="/app/:slug/:section" element={<BackOffice/>}/>
                    <Route path="/app/:slug/:section/:item" element={<BackOffice/>}/>
                </Route>
                <Route path="*" element={<NotFoundPage/>}/>
            </Routes>
        </Router>;
}

def:pub AppRoot -> JsxElement {
    [ready, set_ready] = useState(known_site());
    async def ask {
        if not ready {
            set_ready(await load_site());
        }
    }
    def start {
        ask();
    }
    useEffect(start, []);
    if not ready {
        return <Waiting/>;
    }
    site = current_site();
    if site == "platform" {
        return <PlatformSite/>;
    }
    if site == "storefront" {
        return
            <>
                {previewing() and <PreviewBanner/>}
                <StorefrontSite/>
            </>;
    }
    if site == "none" {
        return <NoSite/>;
    }
    win: any = window;  # jac:ignore[W1037,W2001]
    on_storefront: bool = win.location.pathname.startswith("/c/");
    return
        <>
            {previewing() and on_storefront and <PreviewBanner/>}
            <MainSite own_addresses={site == "main"}/>
        </>;
}
