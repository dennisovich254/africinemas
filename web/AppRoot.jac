"""Root UI component shared by the web app and the desktop app.

Both entry points (main.jac and desktop/main.jac) render <AppRoot />, so every
screen is written once (docs/adr/0001-desktop-reuses-web-ui.md). It owns the only
router: manual routing, no `pages/` directory (docs/adr/0002-manual-routing-in-shared-approot.md).
The back-office (`/app...`) sits under one AuthGuard: signed-out visitors go to /login.
The AfriCinemas platform console is a site of its own, on its own address
(`admin.<domain>`, P13.1b; web/site.jac) with its own sign-in and accounts (P13.1b.a):
that address offers only the console's pages, and the main one none of them.
A cinema's public storefront is `/c/:slug`, with its movies at `/c/:slug/m/:movie` and
showtimes at `/c/:slug/s/:screening` (P4.1).
"""

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
import from .auth.InvitePage { InvitePage }
import from .platform.PlatformConsole { PlatformConsole }
import from .platform.PlatformAuthPages { PlatformSignInPage, PlatformJoinPage }
import from .auth.token_slots { install_token_slots }
import from .site { current_site }

# The back office and each cinema's storefront keep their own sign-in (improvements #25),
# set up when this module loads, before any page asks the server anything.
glob TOKEN_SLOTS: bool = install_token_slots();

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
                </Route>
                <Route path="*" element={<NotFoundPage/>}/>
            </Routes>
        </Router>;
}

def:pub AppRoot -> JsxElement {
    if current_site() == "platform" {
        return <PlatformSite/>;
    }
    return
        <Router>
            <Routes>
                <Route path="/" element={<LandingPage/>}/>
                <Route path="/design-system" element={<DesignSystemPage/>}/>
                <Route path="/design-system/:section" element={<DesignSystemPage/>}/>
                <Route path="/login" element={<LoginPage/>}/>
                <Route path="/signup" element={<SignupPage/>}/>
                <Route path="/c/:slug" element={<StorefrontPage/>}/>
                <Route path="/c/:slug/movies" element={<MoviesPage/>}/>
                <Route path="/c/:slug/cinemas" element={<CinemasPage/>}/>
                <Route path="/c/:slug/m/:movie" element={<MoviePage/>}/>
                <Route path="/c/:slug/s/:screening" element={<ScreeningPage/>}/>
                <Route path="/c/:slug/tickets/:token" element={<TicketsPage/>}/>
                <Route path="/c/:slug/my-tickets" element={<MyTicketsPage/>}/>
                <Route path="/c/:slug/sign-in" element={<CustomerSignInPage/>}/>
                <Route path="/c/:slug/sign-up" element={<CustomerSignUpPage/>}/>
                <Route path="/c/:slug/account" element={<AccountPage/>}/>
                <Route path="/oauth/authorize" element={<AuthorizePage/>}/>
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
