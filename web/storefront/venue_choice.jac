"""Small storefront helpers (P4.1d): the visitor's chosen venue, page titles, and
scrolling to a section named in the address (/c/nova#showtimes).

The chosen venue ("" for all venues) is remembered on this device, per cinema, and
every component that asks for it (use_venue) hears when it changes, through a window
event, so the header's picker and the page stay in step. Storage can be unavailable
(private windows, blocked site data): then the choice lasts for the visit only.
"""

import from react { useState, useEffect }

glob VENUE_EVENT: str = "africinemas-venue";

def _key(slug: str) -> str {
    return f"africinemas:venue:{slug}";
}

def:pub stored_venue(slug: str) -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    try {
        return win.localStorage.getItem(_key(slug)) or "";
    } except Exception {
        return "";
    }
}

def:pub choose_venue(slug: str, name: str) {
    # Remembers `name` ("" for all venues) and tells every use_venue about it.
    win: any = window;  # jac:ignore[W1037,W2001]
    try {
        if name {
            win.localStorage.setItem(_key(slug), name);
        } else {
            win.localStorage.removeItem(_key(slug));
        }
    } except Exception {
        console.warn("the venue choice can't be remembered here");
    }
    event_class: any = win.CustomEvent;  # jac:ignore[W1037]
    win.dispatchEvent(
        new(event_class, VENUE_EVENT, {"detail": {"slug": slug, "name": name}})
    );
}

def:pub use_venue(slug: str) -> str {
    # The visitor's chosen venue at this cinema, kept in step with every picker.
    [venue, set_venue] = useState(stored_venue(slug));

    def listen -> any {  # jac:ignore[W1037]
        win: any = window;  # jac:ignore[W1037,W2001]
        def changed(e: any) {  # jac:ignore[W1037]
            if e.detail.slug == slug {
                set_venue(e.detail.name);
            }
        }
        win.addEventListener(VENUE_EVENT, changed);
        set_venue(stored_venue(slug));
        return lambda { win.removeEventListener(VENUE_EVENT, changed); };
    }
    useEffect(listen, [slug]);
    return venue;
}

def:pub use_title(title: str) {
    # Sets the browser tab's title for this page.
    def apply {
        doc: any = document;  # jac:ignore[W1037,W2001]
        if title {
            doc.title = title;
        }
    }
    useEffect(apply, [title]);
}

def:pub scroll_to_hash(ready: bool) {
    # Once the page has drawn (`ready`), scrolls to the section the address names, as
    # the browser would have if the section had existed when the page loaded.
    def go {
        win: any = window;  # jac:ignore[W1037,W2001]
        doc: any = document;  # jac:ignore[W1037,W2001]
        if not ready or not win.location.hash {
            return;
        }
        name: str = win.location.hash;
        target: any = doc.getElementById(name[1:]);  # jac:ignore[W1037]
        if target {
            target.scrollIntoView();
        }
    }
    useEffect(go, [ready]);
}
