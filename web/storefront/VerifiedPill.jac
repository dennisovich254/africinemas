"""The Verified pill beside a storefront's logo (P14.5, ADR-0071), so a visitor sees it
without scrolling to the footer.

Drawn in our own header, and after the logo in a header the AI wrote (AiPart's
`after_logo`). It takes the header's own colours (currentColor), whatever the design, a
thin outline its only shape, so it fits any theme. Plain text, like the footer's badge:
a link proves nothing, since a fake site can link to a copy of any page (ADR-0071).
Nothing shows for a cinema that isn't verified.
"""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { CheckmarkBadge01Icon }

def:pub VerifiedPill(verified: str) -> JsxElement {
    if not verified {
        return <span className="hidden"/>;
    }
    return
        <span
            title={f"Verified by AfriCinemas on {verified[:10]}"}
            data-testid="verified-pill"
            className="inline-flex shrink-0 items-center gap-1 rounded-full border border-current/40 px-2 py-0.5 font-sans text-xs font-medium leading-none normal-case tracking-normal"
        >
            <HugeiconsIcon
                icon={CheckmarkBadge01Icon}
                size={14}
                strokeWidth={2}
                aria-hidden="true"
            />
            <span className="sr-only sm:not-sr-only">Verified</span>
        </span>;
}
