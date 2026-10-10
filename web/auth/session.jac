"""Staff sign-in, sign-up and sign-out for the back-office (P2.7b).

People sign in with their email address (a Jac `email` identity). Signing out also ends
the shift at the cinemas passed in (ADR-0006): a Jac token can't be revoked, so without
this a copied token would keep working until the shift expired.

The signed-in email is remembered in this browser (P3.7c) so it can be offered to the
server when creating a cinema or accepting an invitation; the server keeps it only after
checking it is the caller's own (core/tenancy/identity.jac). `next_path` is where to go
after signing in: an invitation link, or a page of a cinema's storefront (P6.3b: back to
the tickets, to save them), never an outside address.
"""

import from "@jac/runtime" {
    jacLogin,
    jacSignup,
    jacLogout,
    jacIsLoggedIn,
    SignupResult
}
import from react { useState, useEffect }
import from core.tenancy.storefront_accounts { my_storefront_account }
import from core.tenancy.tenant_api { end_shift }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)

glob EMAIL_KEY: str = "africinemas_email",
     # The OAuth consent page (P8.6a) carries the app's redirect address in its query.
     NEXT_PREFIXES: list[str] = ["/invite/", "/c/", "/oauth/authorize"];

def:pub email_identity(email: str) -> dict[str, str] {
    return {"type": "email", "value": email.strip().lower()};
}

def remember_email(email: str) {
    store: any = None;  # jac:ignore[W1037]
    try {
        store = localStorage;  # jac:ignore[W2001]
        if email {
            store.setItem(EMAIL_KEY, email.strip().lower());
        } else {
            store.removeItem(EMAIL_KEY);
        }
    } except Exception as e {
        # Storage can be blocked (private windows); the email is only a convenience.
        console.warn("couldn't remember the email", e);
    }
}

def:pub signed_in_email -> str {
    # The email this browser signed in with, or "" if unknown.
    found: any = None;  # jac:ignore[W1037]
    try {
        store: any = localStorage;  # jac:ignore[W1037,W2001]
        found = store.getItem(EMAIL_KEY);
    } except Exception as e {
        console.warn("couldn't read the email", e);
    }
    return found or "";
}

def:pub safe_next(wanted: str) -> str {
    path = wanted.split("?")[0];
    if "//" in path or "\\" in path {
        return "";
    }
    for prefix in NEXT_PREFIXES {
        if path.startswith(prefix) {
            return wanted;
        }
    }
    return "";
}

def:pub next_path -> str {
    # The ?next= page to return to after signing in: an invitation link, a storefront
    # page or the OAuth consent page, never another site. Only its path is checked for
    # "//" and "\\": the query can't change the site the browser goes to.
    win: any = window;  # jac:ignore[W1037,W2001]
    params_class: any = win.URLSearchParams;  # jac:ignore[W1037]
    query: any = new(params_class, win.location.search);  # jac:ignore[W1037]
    return safe_next(query.get("next") or "");
}

# "ok", "rejected" (wrong email or password) or "offline" (the server couldn't be
# reached). jacLogin returns False for any refusal and throws when the request fails.
async def:pub sign_in(email: str, password: str) -> str {
    ok: bool = False;
    try {
        ok = await jacLogin(email_identity(email), password);
    } except Exception as e {
        console.warn("sign-in request failed", e);
        return "offline";
    }
    if ok {
        remember_email(email);
    }
    return "ok" if ok else "rejected";
}

# Returns "" on success, otherwise a message to show next to the form.
async def:pub sign_up(email: str, password: str) -> str {
    result: SignupResult | None = None;
    signed_in: str = "";
    result = await jacSignup([email_identity(email)], password);
    if not result.success {
        if "already registered" in (result.error or "") {
            return "An account with this email already exists. Sign in instead.";
        }
        return result.error or "We couldn't create your account. Try again.";
    }
    signed_in = await sign_in(email, password);
    if signed_in != "ok" {
        return "Your account was created, but signing in failed. Sign in to continue.";
    }
    return "";
}

async def:pub sign_out(slugs: list[str]) {
    for slug in slugs {
        try {
            await end_shift(slug);  # jac:ignore[W2037]
        } except Exception as e {
            # Still sign out: the shift expires on its own (ADR-0006).
            console.warn("end_shift failed", slug, e);
        }
    }
    remember_email("");
    jacLogout();
}

def:pub use_staff_session -> str {
    # "staff" when signed in with a back-office account, "customer" when signed in
    # with a cinema's customer account (P8.6c: never the back office's), "out" when
    # signed out, "" while that's being checked.
    [kind, set_kind] = useState("" if jacIsLoggedIn() else "out");

    async def load {
        if not jacIsLoggedIn() {
            return;
        }
        seen: any = None;  # jac:ignore[W1037]
        try {
            seen = await my_storefront_account("");
        } except Exception as e {
            console.warn("account check failed", e);
            set_kind("staff");
            return;
        }
        set_kind("customer" if seen["account_cinema"] else "staff");
    }

    def start {
        load();
    }
    useEffect(start, []);
    return kind;
}
