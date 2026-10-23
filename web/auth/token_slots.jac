"""One sign-in for the back office and one per cinema's storefront, in the same browser
(improvements #25).

Jac's client keeps the sign-in token under one localStorage key, "jac_token", and reads
it on every request, so signing in as a cinema's customer on its storefront used to sign
the owner out of the back office (they share the site). An owner can be a customer at
their own cinema, and staff, customer and platform accounts are separate (P8.6c,
P13.1b.a), so each part of the site keeps its own: install_token_slots makes "jac_token" in localStorage mean the
slot for the page the tab is on (token_slot). Jac's sign-in, sign-out, "signed in?" and
requests all read and write "jac_token", so they all use the right slot without knowing.

Each tab decides from its own address, so a storefront tab and a back-office tab can be
open side by side. sessionStorage and every other key are untouched. A token stored under
the old shared key moves to the slot of the first page that loads, once.
"""

glob TOKEN_KEY: str = "jac_token",
     SLOT_PREFIX: str = "africinemas_token:",
     SLUG_CHARS: str = "abcdefghijklmnopqrstuvwxyz0123456789-";

def:pub cinema_of_resource(resource: str) -> str {
    # The cinema a connector address names: ".../mcp/c/<slug>" -> "<slug>", else "".
    parts = resource.split("/");
    if len(parts) < 4 or parts[-3] != "mcp" or parts[-2] != "c" {
        return "";
    }
    slug = parts[-1];
    ok = len(slug) > 0 and all([ch in SLUG_CHARS for ch in slug]);
    return slug if ok else "";
}

def:pub token_slot(path: str, resource: str) -> str {
    # Where the sign-in token lives for a page: a cinema's storefront (/c/<slug>/...) and
    # the consent page for its connector (`resource`, P8.6a) use that cinema's customer
    # slot; everything else (the back office, staff sign-in, invitations) the staff one.
    # The platform console is on an address of its own (P13.1b.b), whose storage no
    # other page shares.
    if path.startswith("/c/") {
        slug = path[3:].split("/")[0];
        if slug {
            return f"{SLOT_PREFIX}customer:{slug}";
        }
    }
    if path.startswith("/oauth/authorize") {
        slug = cinema_of_resource(resource);
        if slug {
            return f"{SLOT_PREFIX}customer:{slug}";
        }
    }
    return f"{SLOT_PREFIX}staff";
}

def:pub install_token_slots -> bool {
    # Makes localStorage's "jac_token" the current page's slot; once per tab.
    win: any = window;  # jac:ignore[W1037,W2001]
    proto: any = win.Storage.prototype;  # jac:ignore[W1037,W6004] browser-only by design
    if proto.__africinemasSlots {
        return True;
    }
    original_get: any = proto.getItem;  # jac:ignore[W1037]
    original_set: any = proto.setItem;  # jac:ignore[W1037]
    original_remove: any = proto.removeItem;  # jac:ignore[W1037]

    def slot_for(store: any, key: any) -> any {  # jac:ignore[W1037]
        # The key to really use: the page's slot for localStorage's "jac_token".
        if key != TOKEN_KEY or store != win.localStorage {
            return key;
        }
        params: any = new(win.URLSearchParams, win.location.search);  # jac:ignore[W1037]
        return token_slot(win.location.pathname, params.get("resource") or "");
    }

    def get_item(key: any) -> any {  # jac:ignore[W1037]
        store: any = this;  # jac:ignore[W1037,W1051,W2001] the Storage the method was called on
        return original_get.call(store, slot_for(store, key));
    }

    def set_item(key: any, value: any) -> any {  # jac:ignore[W1037]
        store: any = this;  # jac:ignore[W1037,W1051,W2001] the Storage the method was called on
        return original_set.call(store, slot_for(store, key), value);
    }

    def remove_item(key: any) -> any {  # jac:ignore[W1037]
        store: any = this;  # jac:ignore[W1037,W1051,W2001] the Storage the method was called on
        return original_remove.call(store, slot_for(store, key));
    }

    # A token from before the slots goes to this page's slot, if that's empty.
    try {
        shared: any = original_get.call(win.localStorage, TOKEN_KEY);  # jac:ignore[W1037]
        if shared {
            mine: any = slot_for(win.localStorage, TOKEN_KEY);  # jac:ignore[W1037]
            if not original_get.call(win.localStorage, mine) {
                original_set.call(win.localStorage, mine, shared);
            }
            original_remove.call(win.localStorage, TOKEN_KEY);
        }
    } except Exception as e {
        # Storage can be blocked (private windows); the slots still apply.
        console.warn("couldn't move the old sign-in", e);
    }
    proto.getItem = get_item;
    proto.setItem = set_item;
    proto.removeItem = remove_item;
    proto.__africinemasSlots = True;
    return True;
}
