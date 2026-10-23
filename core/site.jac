"""AfriCinemas' three sites and their addresses (plan 13.1b; ADR-0057).

The sites live under one domain, AFRICINEMAS_SITE_DOMAIN ("africinemas.co.ke", or
"localhost:8000" in development; by default the host of AFRICINEMAS_PUBLIC_URL):
- the main site (cinemas' back office) on the domain itself;
- the platform on "admin.<domain>";
- each cinema's storefront on "<slug>.<domain>".

Any other address (a tunnel, 127.0.0.1, the desktop app) is "any": the main site with
every storefront under /c/<slug>, as before the split, so a tunnel that serves one
address only still reaches everything. Links the server sends out (ticket emails,
Claude's answers) use the cinema's own address when AFRICINEMAS_PUBLIC_URL is on the
domain, and the /c/<slug> form on AFRICINEMAS_PUBLIC_URL when it's a tunnel.

site_for_host is how the app learns which site its address is: one place, on the
server, ready for cinemas' own domains later.
"""

import os;
import from urllib.parse { urlsplit }
import from core.tenancy.open_cinema { open_cinema }

glob SITE_DOMAIN_ENV: str = "AFRICINEMAS_SITE_DOMAIN",
     PUBLIC_URL_ENV: str = "AFRICINEMAS_PUBLIC_URL",
     DEFAULT_PUBLIC_URL: str = "http://localhost:8000",
     PLATFORM_LABEL: str = "admin";

def public_url -> str {
    # Our public address (the tunnel's in development, or production's).
    return os.environ.get(PUBLIC_URL_ENV, "").strip().rstrip("/") or DEFAULT_PUBLIC_URL;
}

def _host_of(url: str) -> str {
    return urlsplit(url).netloc.lower().removeprefix("www.");
}

def site_domain -> str {
    chosen = os.environ.get(SITE_DOMAIN_ENV, "").strip().lower().rstrip("/");
    return chosen.removeprefix("https://").removeprefix("http://")
        or _host_of(public_url());
}

def site_scheme -> str {
    # http for this machine's addresses, https everywhere else.
    name = site_domain().split(":")[0];
    return "http" if name == "localhost" or name.endswith(".localhost") else "https";
}

def main_address -> str {
    return f"{site_scheme()}://{site_domain()}";
}

def platform_address -> str {
    return f"{site_scheme()}://{PLATFORM_LABEL}.{site_domain()}";
}

def storefront_address(slug: str, path: str = "") -> str {
    # A cinema's storefront page, as a full address for a link sent out: on its own
    # address, unless our public address is a tunnel, which serves only itself.
    if _host_of(public_url()) == site_domain() {
        return f"{site_scheme()}://{slug}.{site_domain()}{path or '/'}";
    }
    return f"{public_url()}/c/{slug}{path}";
}

def site_of_host(host: str) -> dict[str, str] {
    # {"site": "main" | "platform" | "storefront" | "none" | "any", "slug"}; "none" is
    # an address under the domain that's no cinema's.
    name = host.strip().lower().rstrip(".") if isinstance(host, str) else "";
    domain = site_domain();
    if name == domain or name == f"www.{domain}" {
        return {"site": "main", "slug": ""};
    }
    if name == f"{PLATFORM_LABEL}.{domain}" {
        return {"site": "platform", "slug": ""};
    }
    if name.endswith(f".{domain}") {
        label = name[:-len(domain) - 1];
        cinema = open_cinema(label) if "." not in label else None;
        if cinema is not None {
            return {"site": "storefront", "slug": cinema.slug};
        }
        return {"site": "none", "slug": ""};
    }
    return {"site": "any", "slug": ""};
}

def:pub site_for_host(host: str) -> dict[str, str] {
    # Which site the app is on, and how to reach the others. Public: the page asks
    # before anyone signs in, and it names no more than the address already does.
    found = site_of_host(host);
    found["domain"] = site_domain();
    found["scheme"] = site_scheme();
    return found;
}
