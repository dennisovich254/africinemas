"""Root UI component shared by the web app and the desktop app.

Both entry points (main.jac and desktop/main.jac) render <AppRoot />, so every
screen is written once (docs/adr/0001-desktop-reuses-web-ui.md). It owns the only
router: manual routing, no `pages/` directory (docs/adr/0002-manual-routing-in-shared-approot.md).
"""

import from "@jac/runtime" { Router, Routes, Route }
import from .routes.WelcomePage { WelcomePage }
import from .routes.DesignSystemPage { DesignSystemPage }
import from .routes.NotFoundPage { NotFoundPage }

def:pub AppRoot -> JsxElement {
    return
        <Router>
            <Routes>
                <Route path="/" element={<WelcomePage/>}/>
                <Route path="/design-system" element={<DesignSystemPage/>}/>
                <Route path="/design-system/:section" element={<DesignSystemPage/>}/>
                <Route path="*" element={<NotFoundPage/>}/>
            </Routes>
        </Router>;
}
