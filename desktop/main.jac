"""Desktop entry point: the web app's UI in an OS webview.

Renders the same <AppRoot /> as the web app (ADR-0001). Business logic stays on
the shared server; see [desktop] backend in jac.toml.
"""

import "..styles.global.css";
import "..styles.fonts.css";
import "..styles.brand.css";
import "..styles.landing.css";
import from ..web.AppRoot { AppRoot }

def:pub app -> JsxElement {
    return <AppRoot/>;
}
