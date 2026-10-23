"""Which of AfriCinemas' sites a page is on, from its address (plan 13.1b; ADR-0057).

The server decides (core/site.jac, site_for_host), once per tab: the answer is kept in
sessionStorage, which each address has to itself. The sites:
- "platform": admin.<domain>, the AfriCinemas console;
- "storefront": <slug>.<domain>, one cinema's storefront, its pages at "/", "/movies"...;
- "main": the domain itself, the cinemas' back office; a storefront address in the old
  form (/c/<slug>/...) goes on to the cinema's own address;
- "none": an address under the domain that's no cinema's;
- "any": every other address (a tunnel, 127.0.0.1, the desktop app): the back office
  and every storefront under /c/<slug>, as before the split.

The app's links and the server's answers still name storefront pages /c/<slug>/...;
local_path turns them into the page's own path on that cinema's address, and AppLink
applies it, so a link works on every site.
"""

import from core.site { site_for_host }

glob SITE_KEY: str = "africinemas_site",
     PLATFORM_PREFIX: str = "admin.",
     SITE: dict[str, str] = {"site": "", "slug": "", "domain": "", "scheme": ""};

def _remember(found: dict[str, str]) {
    for key in ["site", "slug", "domain", "scheme"] {
        SITE[key] = found[key] or "";
    }
}

def:pub known_site -> bool {
    # The site from this tab's earlier answer, if there was one.
    if SITE["site"] {
        return True;
    }
    try {
        kept: any = sessionStorage.getItem(SITE_KEY);  # jac:ignore[W1037,W2001]
        if kept {
            parsed: any = JSON.parse(kept);  # jac:ignore[W1037,W2001]
            _remember(parsed);
            return True;
        }
    } except Exception as e {
        console.warn("couldn't read the site", e);
    }
    return False;
}

async def:pub load_site -> bool {
    # Asks the server which site this address is. Without an answer, the address alone:
    # "admin." is the platform, and anything else every page, as before the split.
    win: any = window;  # jac:ignore[W1037,W2001]
    found: any = None;  # jac:ignore[W1037]
    try {
        found = await site_for_host(win.location.host);
    } except Exception as e {
        console.warn("site_for_host failed", e);
    }
    if not found or not found["site"] {
        fallback = "platform"
            if win.location.hostname.startswith(PLATFORM_PREFIX)
            else "any";
        _remember({"site": fallback, "slug": "", "domain": "", "scheme": ""});
        return True;
    }
    _remember(found);
    try {
        sessionStorage.setItem(SITE_KEY, JSON.stringify(SITE));  # jac:ignore[W2001]
    } except Exception as e {
        console.warn("couldn't keep the site", e);
    }
    return True;
}

def:pub current_site -> str {
    return SITE["site"];
}

def:pub site_slug -> str {
    return SITE["slug"];
}

def:pub local_path(path: str) -> str {
    # A storefront page's path (/c/<slug>/...) as this page's own: on that cinema's
    # address, without the /c/<slug>; anywhere else, unchanged.
    slug = SITE["slug"];
    if SITE["site"] != "storefront" or not isinstance(path, str) {
        return path;
    }
    prefix = f"/c/{slug}";
    if path == prefix {
        return "/";
    }
    for mark in ["/", "?", "#"] {
        if path.startswith(prefix + mark) {
            rest = path[len(prefix):];
            return rest if mark == "/" else "/" + rest;
        }
    }
    return path;
}

def:pub storefront_address(slug: str, path: str = "") -> str {
    # A cinema's storefront page from another site (the back office's "View
    # storefront"): its own address under the domain, else /c/<slug> as before.
    if SITE["site"] == "main" and SITE["domain"] {
        return f"{SITE['scheme']}://{slug}.{SITE['domain']}{path or '/'}";
    }
    return f"/c/{slug}{path}";
}

def:pub main_origin -> str {
    # The main site's address (where the server's connectors are named), from any site
    # under the domain; elsewhere this page's own.
    win: any = window;  # jac:ignore[W1037,W2001]
    if SITE["site"] in ["main", "storefront", "platform"] and SITE["domain"] {
        return f"{SITE['scheme']}://{SITE['domain']}";
    }
    return win.location.origin;
}

def:pub with_site_slug(params: any) -> any {  # jac:ignore[W1037]
    # A storefront page's route parameters, with the cinema's slug on its own address,
    # where the path doesn't carry it.
    if SITE["site"] != "storefront" {
        return params;
    }
    return {** params, "slug": SITE["slug"]};
}
