"""The storefront header's account links (P8.6c): this cinema's customer account only.

Signed in with this cinema's customer account: My tickets and Sign out. Otherwise
(signed out, or signed in with any other account: staff, or another cinema's
customer): Sign in, which comes back to this page. The answer comes from the server
(my_storefront_account), never from what the browser holds.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { jacIsLoggedIn, jacLogout, useLocation }
import from ..shell.AppLink { AppLink }
import from core.tenancy.storefront_accounts { my_storefront_account }

def:pub use_customer(slug: str) -> str {
    # "customer" when the visitor is signed in with this cinema's customer account,
    # "other" when not (signed out, or another account), "" while that's being checked.
    [mine, set_mine] = useState("");

    async def load {
        if not jacIsLoggedIn() {
            set_mine("other");
            return;
        }
        seen: any = None;  # jac:ignore[W1037]
        try {
            seen = await my_storefront_account(slug);
        } except Exception as e {
            console.warn("account check failed", e);
            set_mine("other");
            return;
        }
        set_mine("customer" if seen["customer"] else "other");
    }

    def start {
        load();
    }
    useEffect(start, [slug]);
    return mine;
}

def:pub AccountLinks(slug: str, link_class: str, block: bool = False) -> JsxElement {
    mine = use_customer(slug);
    where: any = useLocation();  # jac:ignore[W1037,W1051]
    here: str = where.pathname + where.search;
    item = link_class + (" w-full" if block else "");

    win: any = window;  # jac:ignore[W1037,W2001]

    def sign_out {
        jacLogout();
        win.location.href = f"/c/{slug}";
    }

    if mine == "" {
        return <span className="sr-only">Checking your account</span>;
    }
    if mine != "customer" {
        return
            <AppLink
                to={f"/c/{slug}/sign-in?next={win.encodeURIComponent(here)}"}
                testid="account-sign-in"
                className={item}
            >
                Sign in
            </AppLink>;
    }
    return
        <div className={"flex flex-col gap-1" if block else "flex items-center gap-1"}>
            <AppLink
                to={f"/c/{slug}/my-tickets"}
                testid="account-my-tickets"
                className={item}
            >
                My tickets
            </AppLink>
            <button
                type="button"
                data-testid="account-sign-out"
                onClick={sign_out}
                className={item + " text-left"}
            >
                Sign out
            </button>
        </div>;
}
