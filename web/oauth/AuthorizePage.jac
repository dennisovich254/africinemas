"""/oauth/authorize: the consent page an MCP client (Claude) sends the customer to (P8.6a).

The app connects to one cinema (its `resource` is that cinema's connector,
/c/<slug>/mcp), so only that cinema's customer accounts can allow it (P8.6c): signed
out, or signed in with any other account, the page asks the customer to sign in with
their account at that cinema (its own sign-in page) and comes back here. Then it
asks the server who's asking (oauth_consent_info: a registered app, one of its exact
redirect addresses, one of our MCP routes) and shows the app's name, what it may do and
the address the customer will go back to (MCP's spec asks for the redirect's host to be
shown). Allow gets a single-use code (oauth_approve) and Don't allow a refusal
(oauth_deny); either way the server builds the address, so the page only ever sends
the customer to a redirect the app registered. A request the server refuses shows why,
and goes nowhere.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { jacIsLoggedIn }
import from ...components.ui.button { Button }
import from ..auth.AuthLayout { AuthLayout, FormError }
import from ..shell.AppLink { AppLink }
import from ..storefront.AccountLinks { use_customer }
import from core.oauth.provider {
    oauth_consent_info,  # jac:ignore[W2037]
    oauth_approve,  # jac:ignore[W2037]
    oauth_deny  # jac:ignore[W2037]
}

glob SLUG_CHARS: str = "abcdefghijklmnopqrstuvwxyz0123456789-",
     MAY: list[str] = [
         "See what's on at the cinema and show you movies",
         "Hold seats and send the M-Pesa prompt to your phone when you book",
         "See your own bookings at the cinema"
     ];

def _asked(name: str) -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    params_class: any = win.URLSearchParams;  # jac:ignore[W1037]
    query: any = new(params_class, win.location.search);  # jac:ignore[W1037]
    return query.get(name) or "";
}

def _cinema_of(resource: str) -> str {
    # The cinema a connector address names: ".../c/<slug>/mcp" -> "<slug>", else "".
    parts = resource.split("/");
    if len(parts) < 4 or parts[-1] != "mcp" or parts[-3] != "c" {
        return "";
    }
    slug = parts[-2];
    ok = len(slug) > 0 and all([ch in SLUG_CHARS for ch in slug]);
    return slug if ok else "";
}

def _go(address: str) {
    win: any = window;  # jac:ignore[W1037,W2001]
    win.location.href = address;
}

def:pub AuthorizePage -> JsxElement {
    resource = _asked("resource");
    slug = _cinema_of(resource);
    account = use_customer(slug);
    signed_in = account == "customer";
    [info, set_info] = useState(None);
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);
    client_id = _asked("client_id");
    redirect_uri = _asked("redirect_uri");
    state = _asked("state");

    async def load {
        if not signed_in {
            return;
        }
        if _asked("response_type") != "code" {
            set_problem("This sign-in link isn't complete. Start again from the app.");
            return;
        }
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await oauth_consent_info(client_id, redirect_uri, resource);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("consent info failed", e);
            set_problem("We couldn't check this request. Try again.");
            return;
        }
        if not got["ok"] {
            set_problem(got["error"]["message"]);
            return;
        }
        set_info(got);
    }

    def start {
        load();
    }
    useEffect(start, [signed_in]);

    async def allow {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await oauth_approve(  # jac:ignore[W2037]
                client_id,
                redirect_uri,
                _asked("code_challenge"),
                _asked("code_challenge_method"),
                resource,
                _asked("scope"),
                state
            );
        } except Exception as e {
            console.warn("approve failed", e);
        }
        if not got or not got["ok"] {
            set_busy(False);
            set_problem(
                got["error"]["message"] if got else "That didn't work. Try again."
            );
            return;
        }
        _go(got["redirect"]);
    }

    async def deny {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await oauth_deny(client_id, redirect_uri, resource, state);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("deny failed", e);
        }
        if got and got["ok"] {
            _go(got["redirect"]);
            return;
        }
        set_busy(False);
        set_problem("You haven't allowed anything. You can close this page.");
    }

    if not slug {
        return
            <AuthLayout title="This request can't go ahead" description="">
                <FormError
                    message="This sign-in link isn't for a cinema. Start again from the app."
                />
            </AuthLayout>;
    }
    if account == "" {
        return
            <AuthLayout title="Checking the request…" description="">
                <p className="text-sm text-muted-foreground" role="status">
                    One moment.
                </p>
            </AuthLayout>;
    }
    if not signed_in {
        win: any = window;  # jac:ignore[W1037,W2001]
        here = win.encodeURIComponent(win.location.pathname + win.location.search);
        return
            <AuthLayout
                title="Sign in to continue"
                description={"An app wants to book for you at this cinema. Sign in with your account at the cinema first, then you can allow or refuse it."
                    if not jacIsLoggedIn()
                    else "You're signed in with an account that isn't this cinema's. Sign in with your account at the cinema, then you can allow or refuse the app."}
            >
                <div className="flex flex-col gap-2">
                    <Button asChild={True} className="min-h-11 w-full">
                        <AppLink
                            to={f"/c/{slug}/sign-in?next={here}"}
                            testid="consent-sign-in"
                        >
                            Sign in
                        </AppLink>
                    </Button>
                    <Button
                        asChild={True}
                        variant="outline"
                        className="min-h-11 w-full"
                    >
                        <AppLink
                            to={f"/c/{slug}/sign-up?next={here}"}
                            testid="consent-sign-up"
                        >
                            Create an account
                        </AppLink>
                    </Button>
                </div>
            </AuthLayout>;
    }
    if problem {
        return
            <AuthLayout title="This request can't go ahead" description="">
                <FormError message={problem}/>
            </AuthLayout>;
    }
    if info is None {
        return
            <AuthLayout title="Checking the request…" description="">
                <p className="text-sm text-muted-foreground" role="status">
                    One moment.
                </p>
            </AuthLayout>;
    }
    shown: dict[str, str] = info;
    return
        <AuthLayout
            title={f"Allow {shown['client_name']} to book at {shown['cinema']}?"}
            description={f"{shown['client_name']} wants to use your {shown[
                'cinema'
            ]} account."}
        >
            <div data-testid="consent" className="flex flex-col gap-4">
                <div className="flex flex-col gap-2">
                    <p className="text-sm font-medium">It will be able to:</p>
                    <ul className="flex list-disc flex-col gap-1 pl-5 text-sm">
                        {[<li key={m}>{m}</li> for m in MAY]}
                    </ul>
                    <p className="text-sm text-muted-foreground">
                        It can't pay without you: you confirm each payment with your M-Pesa PIN, on your phone. It can't see your payment details or change your account. To stop it, disconnect the cinema in the app.
                    </p>
                </div>
                <p
                    className="rounded-md border bg-muted px-3 py-2 text-sm"
                    data-testid="consent-redirect"
                >
                    {"You'll go back to "}
                    <strong>{shown["redirect_host"]}</strong>
                </p>
                <div className="flex flex-col gap-2 sm:flex-row-reverse">
                    <Button
                        type="button"
                        data-testid="consent-allow"
                        disabled={busy}
                        className="min-h-11 flex-1"
                        onClick={allow}
                    >
                        Allow
                    </Button>
                    <Button
                        type="button"
                        variant="outline"
                        data-testid="consent-deny"
                        disabled={busy}
                        className="min-h-11 flex-1"
                        onClick={deny}
                    >
                        {"Don't allow"}
                    </Button>
                </div>
            </div>
        </AuthLayout>;
}
