"""`/app`: the cinemas the signed-in person works at, or a way to create their first."""

import from react { useState, useEffect }
import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Add01Icon, ArrowRight01Icon, Film01Icon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.empty {
    Empty,
    EmptyHeader,
    EmptyMedia,
    EmptyTitle,
    EmptyDescription,
    EmptyContent
}
import from ...components.ui.spinner { Spinner }
import from core.tenancy.signup { my_cinemas }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from .nav { web_address, role_label }
import from .PlainLayout { PlainLayout, AccountActions }

def CinemaLink(cinema: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    return
        <Link
            to={f"/app/{cinema['slug']}"}
            className="flex min-h-16 items-center gap-4 rounded-lg border bg-card p-4 transition-colors hover:bg-muted"
        >
            <span className="flex min-w-0 flex-1 flex-col gap-1">
                <span className="truncate font-medium">{cinema["name"]}</span>
                <span className="truncate text-sm text-muted-foreground">
                    {web_address(cinema["slug"])}
                </span>
                <span className="flex flex-wrap gap-1">
                    {[
                        <Badge key={r} variant="secondary">{role_label(r)}</Badge>
                        for r in cinema["roles"]
                    ]}
                </span>
            </span>
            <HugeiconsIcon
                icon={ArrowRight01Icon}
                strokeWidth={2}
                aria-hidden="true"
                className="shrink-0 text-muted-foreground"
            />
        </Link>;
}

def NoCinemas -> JsxElement {
    return
        <Empty className="border" data-testid="no-cinemas">
            <EmptyHeader>
                <EmptyMedia variant="icon">
                    <HugeiconsIcon
                        icon={Film01Icon}
                        strokeWidth={2}
                        aria-hidden="true"
                    />
                </EmptyMedia>
                <EmptyTitle>
                    <h2 className="text-base font-semibold">No cinemas yet</h2>
                </EmptyTitle>
                <EmptyDescription>
                    Create your cinema to start selling tickets. Working for a cinema? Ask your manager for an invitation link.
                </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
                <Button asChild={True} className="min-h-11 px-5">
                    <Link to="/app/new">Create a cinema</Link>
                </Button>
            </EmptyContent>
        </Empty>;
}

def:pub CinemaPicker -> JsxElement {
    [cinemas, set_cinemas] = useState(None);
    [failed, set_failed] = useState(False);
    async def load {
        found: any = None;  # jac:ignore[W1037]
        try {
            found = await my_cinemas();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("my_cinemas failed", e);
            set_failed(True);
            return;
        }
        set_cinemas(found);
    }
    # A named function, not `lambda { load(); }`: that compiles to `() => load()`, and
    # React would call the returned promise as the effect's cleanup (JI-028).
    def start_loading {
        load();
    }
    useEffect(start_loading, []);
    slugs = [c["slug"] for c in cinemas] if cinemas else [];
    body: any = None;  # jac:ignore[W1037]
    if failed {
        body = <Alert variant="destructive">
            <AlertDescription>
                We couldn't load your cinemas. Refresh the page to try again.
            </AlertDescription>
        </Alert>;
    } elif cinemas is None {
        body = <p
            role="status"
            className="flex items-center gap-2 text-muted-foreground"
        >
            <Spinner aria-hidden="true"/>
            Loading your cinemas…
        </p>;
    } elif len(cinemas) == 0 {
        body = <NoCinemas/>;
    } else {
        body = <div className="flex flex-col gap-4">
            <ul className="flex flex-col gap-3" data-testid="cinema-list">
                {[
                    <li key={c["slug"]}>
                        <CinemaLink cinema={c}/>
                    </li> for c in cinemas
                ]}
            </ul>
            <Button asChild={True} variant="outline" className="min-h-11 self-start">
                <Link to="/app/new">
                    <HugeiconsIcon icon={Add01Icon} strokeWidth={2} aria-hidden="true"/>
                    New cinema
                </Link>
            </Button>
        </div>;
    }
    return
        <PlainLayout title="Your cinemas" account={<AccountActions slugs={slugs}/>}>
            {body}
        </PlainLayout>;
}
