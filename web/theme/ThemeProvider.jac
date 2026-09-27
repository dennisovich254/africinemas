"""Applies a theme surface and follows the device's light/dark setting (P0.8b).

`surface` selects the token scope in styles/brand.css ("storefront" or "backoffice").
The `.dark` class on <html> tracks prefers-color-scheme, including changes while the
page is open, which is what shadcn's dark variant and our `.dark [data-surface]` read.

No flash: the class is set in `useLayoutEffect`, which runs before the browser paints, and
transitions are suppressed while it flips (as next-themes' disableTransitionOnChange does),
so a dark device never sees a light frame or a light-to-dark animation
(e2e "no flash of the light theme on a dark device").
"""

import from "react" { useLayoutEffect }

glob NO_TRANSITIONS: str = "*,*::before,*::after{transition:none!important}";

def _set_dark(dark: bool) {
    # Browser objects have partial or no type stubs in `jac check` (see jac-cl-js-interop),
    # so they are bound to `any` once here.
    html_el: any = document.documentElement;  # jac:ignore[W2001,W1037]
    if html_el.classList.contains("dark") == dark {
        return;
    }
    head: any = document.head;  # jac:ignore[W2001,W1037]
    win: any = window;  # jac:ignore[W2001,W1037]
    style: any = document.createElement("style");  # jac:ignore[W2001,W1037]
    style.appendChild(document.createTextNode(NO_TRANSITIONS));  # jac:ignore[W2001]
    head.appendChild(style);
    html_el.classList.toggle("dark", dark);
    # Force the new styles to apply while transitions are off, then re-enable them.
    win.getComputedStyle(html_el).getPropertyValue("color");
    win.setTimeout(lambda { head.removeChild(style); }, 1);  # jac:ignore[W6001] client-only code
}

# `children: any` is the documented idiom for pass-through children (jac-cl-organization).
def:pub ThemeProvider(surface: str, children: any = None) -> JsxElement {  # jac:ignore[W1037]
    useLayoutEffect(
        lambda {
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
