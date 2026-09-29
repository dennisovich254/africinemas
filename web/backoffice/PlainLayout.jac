"""Back-office frames that come before a cinema is chosen (the picker, the new-cinema
wizard), and the account actions every back-office screen shares."""

import from react { useState }
import from "@jac/runtime" { Link, useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Logout01Icon, Building03Icon }
import from ...components.ui.button { Button }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..auth.session { sign_out }

# Signing out ends the shift at each cinema in `slugs` first (ADR-0006).
def:pub AccountActions(slugs: list[str], switch_to: str = "") -> JsxElement {
    nav = useNavigate();
    [busy, set_busy] = useState(False);
    async def leave {
        set_busy(True);
        await sign_out(slugs);
        nav("/login", {"replace": True});
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
