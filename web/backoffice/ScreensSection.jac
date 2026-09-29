"""`/app/:slug/screens`: each venue's screens, and a way into their seat layouts (P3.3).

Adding venues and screens comes with the rest of the setup screens (plan 3.7); until then
they're created through the API.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowRight01Icon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.empty { Empty, EmptyHeader, EmptyTitle, EmptyDescription }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)

def:pub screen_path(slug: str, auditorium_id: str) -> str {
    return f"/app/{slug}/screens/{auditorium_id}";
}

def screens_of(venue: dict[str, any]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return venue["auditoriums"];
}

def layout_status(screen: dict[str, any]) -> str {  # jac:ignore[W1037]
    # This screen's own seat layout, e.g. "Published · version 1 · 62 seats".
    info: dict[str, any] = screen["layout"];  # jac:ignore[W1037]
    count = info["seat_count"];
    seats = "1 seat" if count == 1 else f"{count} seats";
    if info["draft_version"] {
        text = f"Draft · version {info['draft_version']} · {seats}";
        if info["published_version"] {
            text += f" · version {info['published_version']} published";
        }
        return text;
    }
    if info["published_version"] {
        return f"Published · version {info['published_version']} · {seats}";
    }
    return "No layout yet";
}

def ScreenLink(slug: str, screen: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    return
        <Link
            to={screen_path(slug, screen["auditorium_id"])}
            className="flex min-h-14 items-center gap-3 rounded-lg border bg-card px-4 py-3 transition-colors hover:bg-muted"
        >
            <span className="flex min-w-0 flex-1 flex-col">
                <span className="truncate font-medium" data-testid="screen-name">
                    {screen["name"]}
                </span>
                <span
                    className="text-sm text-muted-foreground"
                    data-testid="screen-status"
                >
                    {layout_status(screen)}
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

def:pub ScreensSection(slug: str) -> JsxElement {
    [venues, set_venues] = useState(None);
    [failed, set_failed] = useState("");
    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_venues(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_venues failed", e);
            set_failed("We couldn't load your venues. Refresh the page to try again.");
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_venues(answer["venues"]);
    }
    # A named function, not a one-statement lambda (JI-028).
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);
    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if venues is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading screens…
            </p>;
    }
    listed: list[dict[str, any]] = venues;  # jac:ignore[W1037]
    if len(listed) == 0 {
        return
            <Empty className="border">
                <EmptyHeader>
                    <EmptyTitle>
                        <h2 className="text-base font-semibold">No venues yet</h2>
                    </EmptyTitle>
                    <EmptyDescription>
                        Once your venues and screens are set up, you'll design each screen's seat layout here.
                    </EmptyDescription>
                </EmptyHeader>
            </Empty>;
    }
    return
        <div className="flex flex-col gap-8" data-testid="screens-list">
            {[
                <section
                    key={v["venue_id"]}
                    aria-labelledby={f"venue-{v['venue_id']}"}
                    className="flex flex-col gap-3"
                >
                    <h2 id={f"venue-{v['venue_id']}"} className="text-lg font-semibold">
                        {v["name"]}{v["city"]
                            and <span className="font-normal text-muted-foreground">
                                {" · "}{v["city"]}
                            </span>}
                    </h2>
                    {len(screens_of(v)) == 0
                        and <p className="text-sm text-muted-foreground">
                            No screens at this venue yet.
                        </p>}
                    <ul className="grid gap-3 sm:grid-cols-2">
                        {[
                            <li key={a["auditorium_id"]}>
                                <ScreenLink slug={slug} screen={a}/>
                            </li> for a in screens_of(v)
                        ]}
                    </ul>
                </section> for v in listed
            ]}
        </div>;
}
