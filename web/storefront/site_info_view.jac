"""A cinema's public information on its storefront pages (P14.3a).

use_site_info loads it (public_site_info) for pages that show part of it: the Cinemas
page's directions and parking, and a showtime's booking notes (GoodToKnow). The strip
under every page gets it with the storefront's branding instead (PublicStrip).
"""

import from react { useState, useEffect }
import from core.catalog.site_info { public_site_info }

def:pub use_site_info(slug: str) -> any {  # jac:ignore[W1037]
    # The cinema's public information, or None until it's loaded (or if it fails).
    [info, set_info] = useState(None);
    async def load {
        try {
            answer: any = await public_site_info(slug);  # jac:ignore[W1037]
            if answer["ok"] {
                set_info(answer["info"]);
            }
        } except Exception as e {
            console.warn("public_site_info failed", e);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);
    return info;
}

def:pub GettingHere(info: any) -> JsxElement {  # jac:ignore[W1037]
    # Directions and parking, when the cinema has written them.
    shown: dict[str, any] = info or {};  # jac:ignore[W1037]
    if not shown or (not shown["directions"] and not shown["parking"]) {
        return <></>;
    }
    return
        <section
            aria-labelledby="getting-here-heading"
            data-testid="getting-here"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h2
                id="getting-here-heading"
                className="font-display text-2xl leading-none"
            >
                Getting here
            </h2>
            {shown["directions"]
                and <p className="whitespace-pre-wrap">{shown["directions"]}</p>}
            {shown["parking"]
                and <p>
                    <span className="font-medium">Parking: </span>
                    {shown["parking"]}
                </p>}
        </section>;
}

def:pub GoodToKnow(info: any) -> JsxElement {  # jac:ignore[W1037]
    # What the cinema's ticket types mean, and how to pay, before choosing tickets.
    shown: dict[str, any] = info or {};  # jac:ignore[W1037]
    notes: list[dict[str, str]] = shown["ticket_notes"] or [] if shown else [];
    payment: str = shown["payment_note"] or "" if shown else "";
    if not notes and not payment {
        return <></>;
    }
    return
        <section
            aria-label="Good to know"
            data-testid="good-to-know"
            className="flex flex-col gap-2 rounded-lg border bg-card p-4 text-sm"
        >
            <h3 className="font-semibold">Good to know</h3>
            {len(notes) > 0
                and <dl className="flex flex-col gap-1">
                    {[
                        <div key={n["name"]} className="flex flex-wrap gap-x-2">
                            <dt className="font-medium">{n["name"]}:</dt>
                            <dd>{n["note"]}</dd>
                        </div> for n in notes
                    ]}
                </dl>}
            {payment and <p>{payment}</p>}
        </section>;
}
