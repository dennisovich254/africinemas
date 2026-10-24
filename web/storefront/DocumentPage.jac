"""A cinema's PDFs on its storefront (P14.3d, ADR-0069): a public document's page
(`/documents/:id` on the cinema's own address, `/c/:slug/documents/:id` elsewhere), and
the button that opens a PDF, also used by a policy published as a PDF (PolicyPage).

The PDF comes from the server as base64 and is opened from a local blob URL: in a new
tab when the visitor presses Open (a link, so no popup blocker stops it), or saved with
Download. Phones open it in their own PDF viewer.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from core.catalog.documents { public_document }
import from .StorefrontShell { StorefrontShell, HomeSkeleton, LoadError }
import from .venue_choice { use_title }
import from ..site { with_site_slug }

glob BUTTON: str = "inline-flex min-h-11 items-center justify-center rounded-md px-5 font-medium";

def:pub use_pdf_url(pdf: str) -> str {
    # A blob URL for the base64 PDF, revoked when it changes or the page goes.
    [url, set_url] = useState("");
    def make -> any {  # jac:ignore[W1037]
        if not pdf {
            set_url("");
            return lambda {};
        }
        win: any = window;  # jac:ignore[W1037,W2001]
        raw: str = win.atob(pdf);
        bytes: any = new(win.Uint8Array, len(raw));  # jac:ignore[W1037]
        for i in range(len(raw)) {
            bytes[i] = ord(raw[i]);
        }
        blob: any = new(win.Blob, [bytes], {"type": "application/pdf"});  # jac:ignore[W1037]
        made: str = win.URL.createObjectURL(blob);
        set_url(made);
        return lambda { win.URL.revokeObjectURL(made); };
    }
    useEffect(make, [pdf]);
    return url;
}

def:pub OpenPdf(pdf: str, title: str) -> JsxElement {
    # Open (a new tab) and Download, for a PDF as base64.
    url = use_pdf_url(pdf);
    if not url {
        return <span className="hidden"/>;
    }
    return
        <div className="flex flex-wrap gap-2" data-testid="open-pdf">
            <a
                href={url}
                target="_blank"
                rel="noreferrer"
                className={BUTTON
                    + " bg-primary text-primary-foreground hover:bg-primary/90"}
                data-testid="open-pdf-link"
                aria-label={f"Open {title} (PDF, in a new tab)"}
            >
                Open the PDF
            </a>
            <a
                href={url}
                download="document.pdf"
                className={BUTTON + " border hover:bg-muted"}
            >
                Download
            </a>
        </div>;
}

def:pub DocumentPage -> JsxElement {
    params: any = with_site_slug(useParams());  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    doc_id: str = params["document"] or "";
    [shown, set_shown] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        set_failed(False);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await public_document(slug, doc_id);
        } except Exception as e {
            console.warn("document load failed", e);
            set_failed(True);
            return;
        }
        set_shown(answer);
    }
    def start {
        load();
    }
    useEffect(start, [slug, doc_id]);
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
                <div data-testid="document-missing" className="flex flex-col gap-2">
                    <h2 className="font-display text-3xl leading-none">
                        Page not found
                    </h2>
                    <p className="text-muted-foreground">This page isn't available.</p>
                </div>
            </StorefrontShell>;
    }
    return
        <StorefrontShell slug={slug}>
            <article data-testid="document-page" className="flex flex-col gap-4">
                <h2 className="font-display text-4xl leading-none">{found["title"]}</h2>
                <p className="text-muted-foreground">A PDF shared by this cinema.</p>
                <OpenPdf pdf={found["pdf"]} title={found["title"]}/>
            </article>
        </StorefrontShell>;
}
