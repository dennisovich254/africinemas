"""Back-office frames that come before a cinema is chosen (the picker, the new-cinema
wizard), and the account actions every back-office screen shares."""

import from react { useState }
import from "@jac/runtime" { Link, useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Logout01Icon, Building03Icon }
import from ...components.ui.button { Button }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..auth.session { sign_out }
import from core.payments.reconcile_api { cash_status }  # jac:ignore[W2037] authenticated endpoint

# Signing out ends the shift at each cinema in `slugs` first (ADR-0006). Box office
# staff with cash they haven't counted count it first (P15.6b): Count now opens Count
# cash, which signs them out once it's saved. There's no signing out without it.
def:pub AccountActions(slugs: list[str], switch_to: str = "") -> JsxElement {
    nav = useNavigate();
    [busy, set_busy] = useState(False);
    [uncounted, set_uncounted] = useState("");
    async def go {
        set_busy(True);
        await sign_out(slugs);
        nav("/login", {"replace": True});
    }
    async def leave {
        set_busy(True);
        for slug in slugs {
            got: any = None;  # jac:ignore[W1037]
            try {
                got = await cash_status(slug);  # jac:ignore[W2037]
            } except Exception as e {
                console.warn("cash_status failed", e);
            }
            if got is not None and got["ok"] and got["uncounted"] {
                set_busy(False);
                set_uncounted(slug);
                return;
            }
        }
        await go();
    }
    def count_now {
        where: str = uncounted;
        set_uncounted("");
        nav(f"/app/{where}/box-office/sign-out");
    }
    return
        <div className="flex flex-col gap-1">
            {switch_to
                and <Button
                    asChild={True}
                    variant="ghost"
                    className="min-h-11 justify-start"
                >
                    <Link to={switch_to}>
                        <HugeiconsIcon
                            icon={Building03Icon}
                            strokeWidth={2}
                            aria-hidden="true"
                        />
                        Switch cinema
                    </Link>
                </Button>}
            <Button
                variant="ghost"
                className="min-h-11 justify-start"
                disabled={busy}
                onClick={leave}
            >
                <HugeiconsIcon icon={Logout01Icon} strokeWidth={2} aria-hidden="true"/>
                {"Signing out…" if busy else "Sign out"}
            </Button>
            {uncounted
                and <div
                    className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-4 sm:items-center"
                >
                    <div
                        role="alertdialog"
                        aria-modal="true"
                        aria-labelledby="uncounted-title"
                        aria-describedby="uncounted-text"
                        data-testid="uncounted-cash"
                        className="flex w-full max-w-sm flex-col gap-3 rounded-lg border bg-card p-4 shadow-lg"
                    >
                        <h2 id="uncounted-title" className="text-lg font-semibold">
                            You haven't counted your cash
                        </h2>
                        <p
                            id="uncounted-text"
                            className="text-sm text-muted-foreground"
                        >
                            Count the cash you took this shift before you go. If you sign out without counting, your manager will see that it wasn't counted.
                        </p>
                        <div
                            className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"
                        >
                            <Button
                                variant="outline"
                                className="min-h-11"
                                disabled={busy}
                                onClick={go}
                            >
                                Sign out anyway
                            </Button>
                            <Button className="min-h-11" onClick={count_now}>
                                Count now
                            </Button>
                        </div>
                    </div>
                </div>}
        </div>;
}

# `children` and `account` are pass-through JSX (jac-cl-organization idiom).
def:pub PlainLayout(
    title: str,
    children: any = None,  # jac:ignore[W1037]
    account: any = None  # jac:ignore[W1037]
) -> JsxElement {
    return
        <ThemeProvider surface="backoffice">
            <header
                className="sticky top-0 z-30 flex h-14 items-center justify-between gap-2 border-b bg-card px-4"
            >
                <Link
                    to="/app"
                    className="font-display inline-flex min-h-11 items-center text-2xl leading-none"
                >
                    AfriCinemas
                </Link>
                {account}
            </header>
            <main id="content" className="px-4 py-6 lg:py-10">
                <div className="mx-auto flex w-full max-w-2xl flex-col gap-6">
                    <h1
                        className="font-display text-4xl leading-none lg:text-5xl"
                        data-testid="page-title"
                    >
                        {title}
                    </h1>
                    {children}
                </div>
            </main>
        </ThemeProvider>;
}
