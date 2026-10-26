"""`/c/:slug/account`: a customer's account at this cinema (P8.6d).

The email they signed up with, their name and password (P12.15), the apps they've let book for them here (Claude, through
the cinema's connector) with when each was connected, and Sign out. Disconnecting an
app asks first, in its row ("Disconnect Claude?"), then ends its access at once
(disconnect_app). With no apps, the page says how to connect Claude: the cinema's
connector address, to copy. Anyone but this cinema's customer is asked to sign in here.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams, jacLogout }
import from ...components.ui.button { Button }
import from core.tenancy.storefront_accounts { my_storefront_account }
import from core.oauth.connections {
    my_connected_apps,  # jac:ignore[W2037] authenticated endpoint
    disconnect_app  # jac:ignore[W2037] authenticated endpoint
}
import from .StorefrontShell { StorefrontShell, Loading }
import from ..auth.ProfileForms { NameForm, PasswordForm }
import from .venue_choice { use_title }
import from ..shell.AppLink { AppLink }
import from ..site { with_site_slug, local_path, main_origin }
import from core.notify.offer_consent {
    my_offers,  # jac:ignore[W2037]
    set_my_offers  # jac:ignore[W2037]
}

def _day(iso: str) -> str {
    # "10 Oct 2026", in the visitor's own locale.
    win: any = window;  # jac:ignore[W1037,W2001]
    when: any = new(win.Date, iso);  # jac:ignore[W1037]
    # [] is the visitor's own locale; None would reach the browser as null, which
    # toLocaleDateString refuses.
    return when.toLocaleDateString(
        [], {"day": "numeric", "month": "short", "year": "numeric"}
    );
}

def AppRow(
    slug: str,
    item: dict[str, str],
    on_gone: any  # jac:ignore[W1037]
) -> JsxElement {
    [asking, set_asking] = useState(False);
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    name: str = item["name"];

    async def disconnect {
        set_busy(True);
        set_problem("");
        done: any = None;  # jac:ignore[W1037]
        try {
            done = await disconnect_app(slug, item["app_id"]);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("disconnect failed", e);
        }
        set_busy(False);
        if done is not None and (done["ok"] or done["error"]["code"] == "not_found") {
            on_gone(item["app_id"], name);
            return;
        }
        set_problem("We couldn't disconnect it. Try again.");
    }

    return
        <li
            data-testid="connected-app"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex flex-col gap-0.5">
                    <p className="font-semibold">{name}</p>
                    <p className="text-sm text-muted-foreground">
                        {f"Connected {_day(item['connected_at'])}"}
                    </p>
                </div>
                {not asking
                    and <Button
                        variant="outline"
                        data-testid="disconnect-app"
                        className="min-h-11"
                        onClick={lambda { set_asking(True); }}
                    >
                        Disconnect
                    </Button>}
            </div>
            {asking
                and <div
                    role="group"
                    aria-label={f"Disconnect {name}?"}
                    className="flex flex-col gap-3 border-t pt-3"
                >
                    <p className="text-sm">
                        {f"Disconnect {name}? It won't be able to book for you or see your tickets here until you connect it again."}
                    </p>
                    {problem
                        and <p role="alert" className="text-sm text-destructive">
                            {problem}
                        </p>}
                    <div className="flex flex-wrap gap-2">
                        <Button
                            variant="destructive"
                            data-testid="confirm-disconnect"
                            disabled={busy}
                            className="min-h-11"
                            onClick={disconnect}
                        >
                            {"Disconnecting…" if busy else "Disconnect"}
                        </Button>
                        <Button
                            variant="outline"
                            disabled={busy}
                            className="min-h-11"
                            onClick={lambda { set_asking(False); }}
                        >
                            Keep it
                        </Button>
                    </div>
                </div>}
        </li>;
}

def ConnectHint(slug: str) -> JsxElement {
    # How to let Claude book here: the cinema's own connector address.
    win: any = window;  # jac:ignore[W1037,W2001]
    address: str = f"{main_origin()}/mcp/c/{slug}";
    [copied, set_copied] = useState(False);

    async def copy {
        try {
            await win.navigator.clipboard.writeText(address);
            set_copied(True);
        } except Exception as e {
            console.warn("copy failed", e);
        }
    }

    return
        <div data-testid="no-connected-apps" className="flex flex-col gap-3">
            <p className="text-muted-foreground">
                No apps can book for you here. To book from Claude, add this address as a custom connector in Claude, then sign in with this account.
            </p>
            <div className="flex flex-wrap items-center gap-2">
                <code
                    data-testid="connector-address"
                    className="rounded-md border bg-muted px-3 py-2 text-sm break-all"
                >
                    {address}
                </code>
                <Button variant="outline" className="min-h-11" onClick={copy}>
                    {"Copied" if copied else "Copy"}
                </Button>
            </div>
            <p role="status" className="sr-only">
                {"Address copied" if copied else ""}
            </p>
        </div>;
}

def OffersSetting(slug: str) -> JsxElement {
    # The customer's choice of the cinema's offers (P14.3c): shown when the cinema sends
    # them, or while they still get them.
    [mine, set_mine] = useState(None);
    [busy, set_busy] = useState(False);
    [note, set_note] = useState("");
    async def load {
        try {
            got: any = await my_offers(slug);  # jac:ignore[W1037,W2037]
            if got["ok"] {
                set_mine(got);
            }
        } except Exception as e {
            console.warn("my_offers failed", e);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);
    async def change(want: bool) {
        set_busy(True);
        set_note("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await set_my_offers(slug, want, "");  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("set_my_offers failed", e);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_note(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't reach the cinema. Try again."
            );
            return;
        }
        set_mine(got);
        set_note(
            "You'll get our offers by email."
                if want
                else "You won't get offers from us."
        );
    }
    found: dict[str, any] | None = mine;  # jac:ignore[W1037]
    if found is None or (not found["sends_offers"] and not found["subscribed"]) {
        return <span className="hidden"/>;
    }
    on: bool = found["subscribed"];
    return
        <div className="flex flex-col gap-2" data-testid="offers-setting">
            <h2 className="text-lg font-semibold">Offers</h2>
            <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm">
                <input
                    type="checkbox"
                    id="account-offers"
                    className="size-5"
                    checked={on}
                    disabled={busy}
                    onChange={lambda { change(not on); }}
                />
                Email me this cinema's offers and news.
            </label>
            <p role="status" aria-live="polite" className="text-sm empty:hidden">
                {note}
            </p>
        </div>;
}

def:pub AccountPage -> JsxElement {
    params: any = with_site_slug(useParams());  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    [account, set_account] = useState(None);
    [apps, set_apps] = useState(None);
    [note, set_note] = useState("");

    async def load {
        seen: any = None;  # jac:ignore[W1037]
        listed: any = None;  # jac:ignore[W1037]
        try {
            seen = await my_storefront_account(slug);
            if seen["customer"] {
                listed = await my_connected_apps(slug);  # jac:ignore[W2037]
            }
        } except Exception as e {
            console.warn("account load failed", e);
            seen = {"ok": False, "customer": False};
        }
        set_account(seen);
        set_apps(listed["apps"] if listed is not None and listed["ok"] else []);
    }

    def start {
        load();
    }
    useEffect(start, [slug]);

    def gone(app_id: str, name: str) {
        shown: list[dict[str, str]] = apps or [];
        set_apps(
            [
                a
                for a in shown
                if a["app_id"] != app_id
            ]
        );
        set_note(f"{name} is disconnected.");
    }

    def sign_out {
        jacLogout();
        win: any = window;  # jac:ignore[W1037,W2001]
        win.location.href = local_path(f"/c/{slug}");
    }

    use_title("Your account");
    seen: dict[str, any] | None = account;  # jac:ignore[W1037]
    if seen is None {
        return
            <StorefrontShell slug={slug}>
                <Loading/>
            </StorefrontShell>;
    }
    if not seen["customer"] {
        back: str = f"?next=/c/{slug}/account";
        return
            <StorefrontShell slug={slug}>
                <section
                    data-testid="account-signed-out"
                    className="flex flex-col items-start gap-3 rounded-lg border bg-card p-6"
                >
                    <h1 className="font-display text-4xl leading-none">Your account</h1>
                    <p className="text-muted-foreground">
                        Sign in with your account at this cinema to see it.
                    </p>
                    <AppLink
                        to={f"/c/{slug}/sign-in{back}"}
                        testid="sign-in-for-account"
                        className="inline-flex min-h-11 items-center rounded-md bg-primary px-4 font-medium text-primary-foreground"
                    >
                        Sign in
                    </AppLink>
                </section>
            </StorefrontShell>;
    }
    shown: list[dict[str, str]] = apps or [];
    return
        <StorefrontShell slug={slug}>
            <section data-testid="account" className="flex max-w-2xl flex-col gap-8">
                <div className="flex flex-col gap-2">
                    <h1 className="font-display text-4xl leading-none">Your account</h1>
                    <p className="text-muted-foreground" data-testid="account-email">
                        {f"Signed in as {seen['email']}"}
                    </p>
                    <div className="flex flex-wrap gap-2 pt-2">
                        <AppLink
                            to={f"/c/{slug}/my-tickets"}
                            className="inline-flex min-h-11 items-center rounded-md border px-4 font-medium hover:bg-muted"
                        >
                            My tickets
                        </AppLink>
                        <Button
                            variant="outline"
                            data-testid="account-sign-out"
                            className="min-h-11"
                            onClick={sign_out}
                        >
                            Sign out
                        </Button>
                    </div>
                </div>
                <div className="flex flex-col gap-3">
                    <h2 className="text-lg font-semibold">Your name</h2>
                    <NameForm name={seen["name"] or ""}/>
                </div>
                <div className="flex flex-col gap-3">
                    <h2 className="text-lg font-semibold">Your password</h2>
                    <p className="text-sm text-muted-foreground">
                        Changing it doesn't sign you out on your other devices. Sign out on them yourself.
                    </p>
                    <PasswordForm sign_in=""/>
                </div>
                <OffersSetting slug={slug}/>
                <div className="flex flex-col gap-3">
                    <h2 className="text-lg font-semibold">
                        Apps that can book for you
                    </h2>
                    <p role="status" className="text-sm" data-testid="account-note">
                        {note}
                    </p>
                    {len(shown) == 0 and <ConnectHint slug={slug}/>}
                    {len(shown) > 0
                        and <ul className="flex flex-col gap-3">
                            {[
                                <AppRow
                                    key={a["app_id"]}
                                    slug={slug}
                                    item={a}
                                    on_gone={gone}
                                /> for a in shown
                            ]}
                        </ul>}
                </div>
            </section>
        </StorefrontShell>;
}
