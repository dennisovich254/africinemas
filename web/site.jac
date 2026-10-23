"""Which of AfriCinemas' sites a page is on, from its address (plan 13.1b).

The platform (AfriCinemas staff) is on its own address, "admin." in front of the main
one: admin.africinemas.co.ke, or admin.localhost:8000 in development, where browsers
send any *.localhost address to this machine. Everything else is the main site (the
back office and, until 13.1b.c, the storefronts). The app offers each site only its
own pages, and browsers keep each address's storage, sign-ins included, apart.
"""

glob PLATFORM_PREFIX: str = "admin.";

def:pub site_of(hostname: str) -> str {
    # "platform" or "main".
    return "platform" if hostname.startswith(PLATFORM_PREFIX) else "main";
}

def:pub current_site -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    return site_of(win.location.hostname);
}
