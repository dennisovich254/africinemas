"""The Verified pill beside a storefront's logo (P14.5, ADR-0071), so a visitor sees it
without scrolling to the footer.

Drawn in our own header, and after the logo in a header the AI wrote (AiPart's
`after_logo`). It takes the header's own colours (currentColor), whatever the design, a
thin outline its only shape, so it fits any theme. Like the footer's badge, it links to
the check on AfriCinemas' own site. Nothing shows for a cinema that isn't verified.
"""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { CheckmarkBadge01Icon }
import from ..site { main_origin }

# The header's colour, whatever an AI design's `a` rules say.
glob PLAIN: dict[str, str] = {"color": "inherit", "textDecoration": "none"};

def:pub VerifiedPill(slug: str, verified: str) -> JsxElement {
    if not verified {
        return <span className="hidden"/>;
    }
    return
        <a
            href={f"{main_origin()}/verified/{slug}"}
            target="_blank"
            rel="noreferrer"
            style={PLAIN}
            title={f"Verified by AfriCinemas on {verified[:10]}"}
            aria-label="Verified cinema: check it on AfriCinemas"
            data-testid="verified-pill"
            className="inline-flex min-h-11 shrink-0 items-center"
        >
            <span
                className="inline-flex items-center gap-1 rounded-full border border-current/40 px-2 py-0.5 font-sans text-xs font-medium leading-none normal-case tracking-normal"
            >
                <HugeiconsIcon
                    icon={CheckmarkBadge01Icon}
                    size={14}
                    strokeWidth={2}
                    aria-hidden="true"
                />
                <span className="hidden sm:inline">Verified</span>
            </span>
        </a>;
}
