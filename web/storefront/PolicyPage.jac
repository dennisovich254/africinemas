"""`/c/:slug/policies/:kind` (`/policies/:kind` on the cinema's own address): one of the
cinema's published policies (P14.3b, ADR-0067), linked from every page's footer.

The text is drawn as React text, never as HTML, from its small plain format
(core/catalog/policies.jac): a blank line between paragraphs, "## " starts a heading
and "- " a list item. An unpublished or unknown policy isn't found.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from core.catalog.policies { public_policy }
import from .StorefrontShell { StorefrontShell, HomeSkeleton, LoadError }
import from .venue_choice { use_title }
import from ..site { with_site_slug }

def:pub policy_blocks(text: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The text's blocks: {"kind": "heading" | "list" | "paragraph", "lines": [...]}.
    blocks: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for chunk in (text or "").split("\n\n") {
        lines = [
            l.strip()
            for l in chunk.split("\n")
            if l.strip()
        ];
        if len(lines) == 0 {
            continue;
        }
        if lines[0].startswith("## ") {
            blocks.append({"kind": "heading", "lines": [lines[0][3:].strip()]});
            lines = lines[1:];
        }
        items = [
            l
            for l in lines
            if l.startswith("- ")
        ];
        if len(lines) > 0 and len(items) == len(lines) {
            blocks.append({"kind": "list", "lines": [l[2:].strip() for l in lines]});
        } elif len(lines) > 0 {
            blocks.append({"kind": "paragraph", "lines": lines});
        }
    }
    return blocks;
}

def:pub PolicyText(text: str) -> JsxElement {
    # A policy's text, drawn from its plain format.
    return
        <div className="flex max-w-prose flex-col gap-4 leading-relaxed">
            {[
                (
                    <h3 key={f"{n}"} className="pt-2 text-lg font-semibold">
                        {b["lines"][0]}
                    </h3>
                        if b["kind"] == "heading"
                        else (
                            <ul
                                key={f"{n}"}
                                className="flex list-disc flex-col gap-1 pl-5"
                            >
                                {[
                                    <li key={f"{i}"}>{line}</li>
                                    for (i, line) in enumerate(b["lines"])
                                ]}
                            </ul>
                                if b["kind"] == "list"
                                else <p key={f"{n}"}>
                                    {[
                                        <span key={f"{i}"}>
                                            {i > 0 and <br/>}{line}
                                        </span> for (i, line) in enumerate(b["lines"])
                                    ]}
                                </p>
                        )
                ) for (n, b) in enumerate(policy_blocks(text))
            ]}
        </div>;
}

def:pub PolicyPage -> JsxElement {
    params: any = with_site_slug(useParams());  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    kind: str = params["kind"] or "";
    [shown, set_shown] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        set_failed(False);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await public_policy(slug, kind);
        } except Exception as e {
            console.warn("policy load failed", e);
            set_failed(True);
            return;
        }
        set_shown(answer);
    }
    def start {
        load();
    }
    useEffect(start, [slug, kind]);
    def retry {
        load();
    }

    found: dict[str, any] | None = shown;  # jac:ignore[W1037]
    ready: bool = found is not None and found["ok"];
    use_title(found["title"] if ready else "");
    if failed {
        return
            <StorefrontShell slug={slug}>
                <LoadError on_retry={retry}/>
            </StorefrontShell>;
    }
    if found is None {
        return
            <StorefrontShell slug={slug}>
                <HomeSkeleton/>
            </StorefrontShell>;
    }
    if not ready {
        return
            <StorefrontShell slug={slug}>
                <div data-testid="policy-missing" className="flex flex-col gap-2">
                    <h2 className="font-display text-3xl leading-none">
                        Page not found
                    </h2>
                    <p className="text-muted-foreground">This page isn't available.</p>
                </div>
            </StorefrontShell>;
    }
    updated: str = (found["updated_at"] or "")[:10];
    return
        <StorefrontShell slug={slug}>
            <article data-testid="policy-page" className="flex flex-col gap-6">
                <header className="flex flex-col gap-2">
                    <h2 className="font-display text-4xl leading-none">
                        {found["title"]}
                    </h2>
                    {updated
                        and <p className="text-sm text-muted-foreground">
                            Last updated{" "}
                            <time dateTime={updated}>{updated}</time>
                        </p>}
                </header>
                <PolicyText text={found["text"]}/>
            </article>
        </StorefrontShell>;
}
