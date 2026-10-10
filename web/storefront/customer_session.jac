"""Signing in and up on a storefront (P8.6c): a customer account belongs to one cinema.

The account's sign-in name is "<slug>:<email>" (core/tenancy/storefront_accounts.jac),
so it never matches a back-office (staff) account or another cinema's customer, even
with the same email. Signing up goes through the server (customer_sign_up), which
records the account's cinema; then the browser signs in with Jac's own login.

After signing in, a customer goes back where they came from, but only to this
cinema's own pages or to an app's sign-in consent (/oauth/authorize): never the back
office, another cinema or another site.
"""

import from "@jac/runtime" { jacLogin }
import from core.tenancy.storefront_accounts { customer_sign_up }
import from ..auth.session { safe_next, remember_email }

def:pub customer_identity(slug: str, email: str) -> dict[str, str] {
    return {"type": "username", "value": f"{slug}:{email.strip().lower()}"};
}

def:pub back_to(slug: str, wanted: str) -> str {
    # Where to go after signing in: `wanted` when it's this cinema's page or an app's
    # consent page, else the customer's tickets here.
    checked = safe_next(wanted);
    path = checked.split("?")[0];
    if path == f"/c/{slug}"
        or path.startswith(f"/c/{slug}/")
        or path.startswith("/oauth/authorize") {
        return checked;
    }
    return f"/c/{slug}/my-tickets";
}

def:pub asked_next -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    params_class: any = win.URLSearchParams;  # jac:ignore[W1037]
    query: any = new(params_class, win.location.search);  # jac:ignore[W1037]
    return query.get("next") or "";
}

# "ok", "rejected" (wrong email or password) or "offline" (the server couldn't be reached).
async def:pub customer_sign_in(slug: str, email: str, password: str) -> str {
    ok: bool = False;
    try {
        ok = await jacLogin(customer_identity(slug, email), password);
    } except Exception as e {
        console.warn("sign-in failed", e);
        return "offline";
    }
    if not ok {
        return "rejected";
    }
    # A staff email remembered in this browser isn't this account's (session.jac).
    remember_email("");
    return "ok";
}

# "" when the account was made and is signed in, else what to tell the customer.
async def:pub create_customer_account(
    slug: str, email: str, password: str, name: str
) -> str {
    made: any = None;  # jac:ignore[W1037]
    try {
        made = await customer_sign_up(slug, email, password, name.strip());
    } except Exception as e {
        console.warn("sign-up failed", e);
        return "We couldn't reach the cinema. Check your connection and try again.";
    }
    if not made["ok"] {
        return made["error"]["message"];
    }
    if await customer_sign_in(slug, email, password) != "ok" {
        return "Your account was made, but signing in failed. Sign in to continue.";
    }
    return "";
}
