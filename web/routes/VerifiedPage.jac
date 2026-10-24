"""`/verified/:slug` on AfriCinemas' own site: the check behind a cinema's Verified badge
(P14.5, ADR-0071).

Every storefront's badge links here, on the main address, which no cinema controls.
For a cinema AfriCinemas verified, it says so, with the date and the cinema's one true
address, so a copy of the badge on a look-alike site, or the words typed into a page,
leads to a page that says it can't be confirmed. Anything else (unknown, private, not
verified) gets that same answer, naming nothing.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { CheckmarkBadge01Icon, Alert02Icon }
import from ...components.ui.spinner { Spinner }
import from core.tenancy.verification { verified_cinema }
import from ..theme.ThemeProvider { ThemeProvider }

def:pub VerifiedPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    [found, set_found] = useState(None);
    [failed, set_failed] = useState(False);
    async def load {
        try {
            answer: any = await verified_cinema(slug);  # jac:ignore[W1037]
            set_found(answer);
        } except Exception as e {
            console.warn("verified_cinema failed", e);
            set_failed(True);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);
    shown: dict[str, any] | None = found;  # jac:ignore[W1037]
    body: any = None;  # jac:ignore[W1037]
    if failed {
        body = <p>We couldn't check right now. Refresh the page to try again.</p>;
    } elif shown is None {
        body = <p
            role="status"
            className="flex items-center gap-2 text-muted-foreground"
        >
            <Spinner aria-hidden="true"/>
            Checking…
        </p>;
    } elif shown["verified"] {
        body = <div className="flex flex-col gap-3" data-testid="verified-yes">
            <p className="flex items-center gap-2 text-lg font-semibold">
                <HugeiconsIcon
                    icon={CheckmarkBadge01Icon}
                    size={28}
                    strokeWidth={2}
                    aria-hidden="true"
                    className="text-primary"
                />
                {f"{shown['name']} is a verified cinema"}
            </p>
            <p>
                {f"AfriCinemas checked who owns it and its business documents on {shown[
                    'verified_at'
                ][:10]}."}
            </p>
            <p>
                Its storefront is only ever at
                <a
                    href={shown["address"]}
                    className="ml-1 break-all font-medium underline underline-offset-4"
                    data-testid="verified-address"
                >
                    {shown["address"]}
                </a>
                . Book there, and nowhere else claiming to be it.
            </p>
        </div>;
    } else {
        body = <div className="flex flex-col gap-3" data-testid="verified-no">
            <p className="flex items-center gap-2 text-lg font-semibold">
                <HugeiconsIcon
                    icon={Alert02Icon}
                    size={28}
                    strokeWidth={2}
                    aria-hidden="true"
                    className="text-destructive"
                />
                We can't confirm this cinema
            </p>
            <p>
                AfriCinemas hasn't verified a cinema at this link. If a page showed you a Verified badge that brought you here, don't pay on it.
            </p>
        </div>;
    }
    return
        <ThemeProvider surface="storefront">
            <main
                className="mx-auto flex min-h-svh max-w-xl flex-col justify-center gap-6 px-4 py-8"
                data-testid="verified-page"
            >
                <header className="flex flex-col gap-1">
                    <p className="text-sm font-medium text-muted-foreground">
                        AfriCinemas
                    </p>
                    <h1 className="font-display text-3xl leading-none">
                        Is this cinema verified?
                    </h1>
                </header>
                {body}
            </main>
        </ThemeProvider>;
}
