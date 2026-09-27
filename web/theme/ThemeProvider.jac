"""Applies a theme surface and follows the device's light/dark setting (P0.8b).

`surface` selects the token scope in styles/brand.css ("storefront" or "backoffice").
The `.dark` class on <html> tracks prefers-color-scheme, including changes while the
page is open, which is what shadcn's dark variant and our `.dark [data-surface]` read.
"""

import from "react" { useEffect }

def _set_dark(dark: bool) {
    document.documentElement.classList.toggle("dark", dark);  # jac:ignore[W2001]
}

# `children: any` is the documented idiom for pass-through children (jac-cl-organization).
def:pub ThemeProvider(surface: str, children: any = None) -> JsxElement {  # jac:ignore[W1037]
    useEffect(
        lambda {
            # Browser object with no type stubs in `jac check` (see jac-cl-js-interop).
            query: any = window.matchMedia("(prefers-color-scheme: dark)");  # jac:ignore[W2001,W1037]
            _set_dark(query.matches);
            handler = lambda (e: any) { _set_dark(e.matches); };  # jac:ignore[W1037]
            query.addEventListener("change", handler);
            return lambda { query.removeEventListener("change", handler); };
        },
        []
    );
    return <div data-surface={surface} className="min-h-svh">{children}</div>;
}
