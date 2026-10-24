"""`/verified` and `/verified/:slug` on AfriCinemas' own site: the check behind a
cinema's Verified badge (P14.5, ADR-0071).

Every storefront's badge links here, on the main address, which no cinema controls.
For a cinema AfriCinemas verified, it says so, with the date and the cinema's own
address (always under our domain, never the server's tunnel). Anything else (unknown,
private, not verified) gets one answer, naming nothing.

A page can be copied, so the page doesn't ask to be trusted for what it says. It says
where it really lives, `<our domain>/verified/…`, and asks the visitor to check the
browser's address bar. At `/verified`, a visitor types a cinema's address or name
themself instead of following a badge's link.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams, useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    CheckmarkBadge01Icon,
    Alert02Icon,
    Search01Icon
}
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.tenancy.verification { verified_cinema }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..site { main_origin }
import from ..backoffice.form_parts { submit_with }

def host_of(origin: str) -> str {
    # "https://africinemas.co.ke" -> "africinemas.co.ke".
    return origin.split("://")[-1];
}

def slug_of(typed: str) -> str {
    # What a visitor types (anga, anga.africinemas.co.ke, https://anga...) as a slug.
    text = typed.strip().lower();
    text = text.split("://")[-1];
    text = text.split("/")[0];
    return text.split(".")[0];
}

def WhereThisIs(ours: str) -> JsxElement {
    # The one thing a copy can't fake: the browser's address bar.
    return
        <p
            className="rounded-lg border bg-card p-4 text-sm"
            data-testid="verified-where"
        >
            This check is real only at
            <strong className="mx-1 break-all">{f"{ours}/verified"}</strong>
            . Look at your browser's address bar: if it shows anything else, this page is a copy, so don't trust it or pay there.
        </p>;
}

def Lookup -> JsxElement {
    # Check a cinema by typing its address, not by following a link.
    nav: any = useNavigate();  # jac:ignore[W1037,W1051]
    [typed, set_typed] = useState("");
    def go {
        wanted = slug_of(typed);
        if wanted {
            nav(f"/verified/{wanted}");  # jac:ignore[W1051]
        }
    }
    return
        <form
            className="flex flex-col gap-2"
            onSubmit={submit_with(lambda { go(); })}
            data-testid="verified-lookup"
        >
            <Label htmlFor="verified-cinema">A cinema's web address</Label>
            <div className="flex flex-wrap gap-2">
                <Input
                    id="verified-cinema"
                    value={typed}
                    placeholder="anga.africinemas.co.ke"
                    autoComplete="off"
                    className="min-h-11 flex-1"
                    onChange={lambda (e: any) { set_typed(e.target.value); }}  # jac:ignore[W1037]
                />
                <Button type="submit" className="min-h-11 gap-2 px-4">
                    <HugeiconsIcon icon={Search01Icon} size={18} aria-hidden="true"/>
                    Check
                </Button>
            </div>
        </form>;
}

def:pub VerifiedPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    [found, set_found] = useState(None);
    [failed, set_failed] = useState(False);
    async def load {
        if not slug {
            return;
        }
        set_found(None);
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
    ours = host_of(main_origin());
    shown: dict[str, any] | None = found;  # jac:ignore[W1037]
    body: any = None;  # jac:ignore[W1037]
    if not slug {
        body = <p>
            Type the address of the cinema's storefront, and we'll tell you whether AfriCinemas has verified it.
        </p>;
    } elif failed {
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
        when: str = shown["verified_at"][:10];
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
                {f"AfriCinemas checked who owns it and its business documents on {when}."}
            </p>
            <p>
                Its storefront is only ever at
                <a
                    href={shown["address"]}
                    className="mx-1 break-all font-medium underline underline-offset-4"
                    data-testid="verified-address"
                >
                    {shown["host"]}
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
                AfriCinemas hasn't verified a cinema at this address. If a page showed you a Verified badge that brought you here, don't pay on it.
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
                <WhereThisIs ours={ours}/>
                <Lookup/>
            </main>
        </ThemeProvider>;
}
