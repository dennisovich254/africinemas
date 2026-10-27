"""AfriCinemas' own legal documents, published at /legal/<name> (P15.0b, ADR-0078).

The terms of use, the privacy policy, the cookie and storage notice and the cinema
agreement, as published copies in core/legal/published/ (built from the drafts in
docs/legal/ by scripts/publish_legal.py). Each has a version and the date it applies
from. Version 0.1 was published before the advocate's review (owner, 2026-10-26), so
every page says it's being reviewed.

legal_document(name) answers anyone for the public ones. The cinema agreement is
confidential (owner, 2026-10-27): it isn't a public page; only the cinema's own team
reads it (core/legal/agreement_api.jac, cinema_agreement_text), for the owner to accept
(P15.1).
"""

import os;
import from core.tenancy.responses { NOT_FOUND }

glob VERSION: str = "0.1",
     APPLIES_FROM: str = "2026-10-26",
     REVIEW_NOTE: str = "Version 0.1. This version is being reviewed by our lawyers and may change.",
     # name: (title, file). The order is the footer's.
     DOCUMENTS: dict[str, tuple[str, str]] = {
         "terms": ("Terms of use", "terms.md"),
         "privacy": ("Privacy policy", "privacy.md"),
         "cookies": ("Cookies and storage", "cookies.md"),
         "cinema-agreement": ("Cinema agreement", "cinema-agreement.md")
     },
     # The documents anyone may read.
     PUBLIC: list[str] = ["terms", "privacy", "cookies"],
     PUBLISHED_DIR: str = os.path.join(
         os.path.dirname(os.path.abspath(__file__)), "published"
     );

def document_text(name: str) -> str {
    # The published text of `name`, or "" when there's no such document.
    found = DOCUMENTS.get(name);
    if found is None {
        return "";
    }
    with open(os.path.join(PUBLISHED_DIR, found[1]), encoding="utf-8") as f {
        return f.read();
    }
}

def _document(name: str) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "name": name,
        "title": DOCUMENTS[name][0],
        "version": VERSION,
        "applies_from": APPLIES_FROM,
        "note": REVIEW_NOTE,
        "text": document_text(name)
    };
}

def:pub legal_document(name: str) -> dict[str, any] {  # jac:ignore[W1037]
    if not isinstance(name, str) or name not in PUBLIC {
        return NOT_FOUND;
    }
    return _document(name);
}
