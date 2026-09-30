"""Root UI component shared by the web app and the desktop app.

Both entry points (main.jac and desktop/main.jac) render <AppRoot />, so every
screen is written once (docs/adr/0001-desktop-reuses-web-ui.md). It owns the only
router: manual routing, no `pages/` directory (docs/adr/0002-manual-routing-in-shared-approot.md).
The back-office (`/app...`) sits under one AuthGuard: signed-out visitors go to /login.
A cinema's public storefront is `/c/:slug` (P3.8b; Phase 4 fills it in).
"""

import from "@jac/runtime" { Router, Routes, Route, AuthGuard }
import from .routes.WelcomePage { WelcomePage }
import from .auth.LoginPage { LoginPage }
import from .auth.SignupPage { SignupPage }
import from .backoffice.CinemaPicker { CinemaPicker }
import from .backoffice.NewCinemaWizard { NewCinemaWizard }
import from .backoffice.BackOffice { BackOffice }
import from .routes.DesignSystemPage { DesignSystemPage }
import from .routes.NotFoundPage { NotFoundPage }
import from .storefront.StorefrontPage { StorefrontPage }

def:pub AppRoot -> JsxElement {
    return
        <Router>
            <Routes>
                <Route path="/" element={<WelcomePage/>}/>
                <Route path="/design-system" element={<DesignSystemPage/>}/>
                <Route path="/design-system/:section" element={<DesignSystemPage/>}/>
                <Route path="/login" element={<LoginPage/>}/>
                <Route path="/signup" element={<SignupPage/>}/>
                <Route path="/c/:slug" element={<StorefrontPage/>}/>
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
