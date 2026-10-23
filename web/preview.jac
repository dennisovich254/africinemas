"""A cinema's team previewing its storefront before it goes live (P14.1, ADR-0064).

Only an active cinema is public. The back office's "View storefront" links of a cinema
that isn't live yet end in #preview=<pass> (storefront_preview, a short-lived pass for
that one cinema). install_preview, run once when the app loads, keeps the pass for the
tab (sessionStorage, which each address has to itself), takes it out of the address,
and sends it with every request the page makes to its own server, in the
x-africinemas-preview header, which open_cinema checks. previewing() says whether this
tab has one, for the banner. The pass never goes to another site.
"""

glob PREVIEW_KEY: str = "africinemas_preview",
     PREVIEW_HEADER: str = "x-africinemas-preview",
     PREFIX: str = "#preview=";

def _kept -> str {
    try {
        found: any = sessionStorage.getItem(PREVIEW_KEY);  # jac:ignore[W1037,W2001]
        return found or "";
    } except Exception as e {
        console.warn("couldn't read the preview pass", e);
    }
    return "";
}

def:pub previewing -> bool {
    return _kept() != "";
}

def:pub install_preview -> bool {
    # Once per tab, before any page asks the server anything.
    win: any = window;  # jac:ignore[W1037,W2001]
    if win.__africinemasPreview {
        return True;
    }
    found: str = win.location.hash;
    if found.startswith(PREFIX) {
        try {
            sessionStorage.setItem(PREVIEW_KEY, found[len(PREFIX):]);  # jac:ignore[W2001]
        } except Exception as e {
            console.warn("couldn't keep the preview pass", e);
        }
        win.history.replaceState(None, "", win.location.pathname + win.location.search);
    }
    original: any = win.fetch.bind(win);  # jac:ignore[W1037,W6001] client-only, the one fetch wrapper
    def with_pass(resource: any, init: any = None) -> any {  # jac:ignore[W1037]
        token = _kept();
        target: str = resource
            if isinstance(resource, str)
            else str(resource.url or resource);
        url: any = new(win.URL, target, win.location.href);  # jac:ignore[W1037]
        if not token or url.origin != win.location.origin {
            return original(resource, init);
        }
        options: any = init or {};  # jac:ignore[W1037]
        headers: any = new(win.Headers, options.headers or {});  # jac:ignore[W1037]
        headers.set(PREVIEW_HEADER, token);
        return original(resource, {** options, "headers": headers});
    }
    win.fetch = with_pass;
    win.__africinemasPreview = True;
    return True;
}
