"""A cinema's public documents, and PDFs in general (P14.3d, ADR-0069).

Public documents are the ones a cinema chooses to show visitors, linked from every
storefront footer: its KFCB film exhibition licence, county business permit, the snack
counter's food and health certificate, or any other, each a PDF with a title. A policy
may also be a PDF (core/catalog/policies.jac uses process_pdf and the media store).

An upload arrives as base64, capped in size before it's decoded. It must be a real PDF:
it starts with "%PDF-", pypdf can read it, it isn't password-protected, and it has at
most MAX_PAGES pages. It's then rebuilt from its pages alone, with their annotations
removed, into a new file, the way photos are re-encoded: nothing at the document level
survives (scripts, open actions, attached files, forms, metadata), and no link or
script on a page either. The new file is stored under a random name in the cinema's
media folder; the name never comes from the client.
"""

import io;
import base64;
import binascii;
import from uuid { uuid4 }
import from pypdf { PdfReader, PdfWriter }
import from core.clock { now }
import from core.authz.context { scoped }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.catalog.answers { Refused, answer }
import from core.catalog.poster { media_store, read_media }
import from core.audit.log { audited }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.responses { NOT_FOUND }

glob CONFIGURE: str = "tenant.settings.update",
     MAX_PDF_BYTES: int = 10 * 1024 * 1024,
     MAX_PAGES: int = 50,
     DOCUMENTS_MAX: int = 10,
     TITLE_MAX: int = 80,
     # Suggested titles in the back office; any other is fine.
     SUGGESTED: list[str] = [
         "KFCB film exhibition licence",
         "County business permit",
         "Food and health certificate"
     ];

class PdfRejected(ValueError) {
    # An upload we won't store, with a code and a message the UI can show.
    def init(self: PdfRejected, code: str, message: str) {
        super.init(message);
        self.code = code;
        self.message = message;
    }
}

def decode_pdf(data_base64: str) -> bytes {
    # The uploaded bytes; the size is checked before anything is decoded.
    too_big = "Choose a PDF of up to 10 MB.";
    if not isinstance(data_base64, str) or not data_base64 {
        raise PdfRejected("invalid_pdf", "That file couldn't be read as a PDF.");
    }
    if len(data_base64) > int(MAX_PDF_BYTES * 4 / 3) + 4 {
        raise PdfRejected("too_large", too_big);
    }
    try {
        data = base64.b64decode(data_base64, validate=True);
    } except (binascii.Error, ValueError) {
        raise PdfRejected("invalid_pdf", "That file couldn't be read as a PDF.");
    }
    if len(data) > MAX_PDF_BYTES {
        raise PdfRejected("too_large", too_big);
    }
    return data;
}

def process_pdf(data: bytes) -> bytes {
    # A new PDF rebuilt from the upload's pages alone, or PdfRejected.
    unreadable = "That file couldn't be read as a PDF. Save it as a PDF again and retry.";
    if not data.startswith(b"%PDF-") {
        raise PdfRejected("invalid_pdf", unreadable);
    }
    try {
        reader = PdfReader(io.BytesIO(data), strict=False);
        if reader.is_encrypted {
            raise PdfRejected(
                "pdf_protected",
                "This PDF has a password. Save a copy without one, then upload it."
            );
        }
        count = len(reader.pages);
        if count == 0 {
            raise PdfRejected("invalid_pdf", unreadable);
        }
        if count > MAX_PAGES {
            raise PdfRejected(
                "too_many_pages", f"Choose a PDF of up to {MAX_PAGES} pages."
            );
        }
        writer = PdfWriter();
        for page in reader.pages {
            writer.add_page(page);
        }
        # No links, form fields or page scripts: annotations go, and so do the pages'
        # own actions.
        writer.remove_annotations(subtypes=None);
        for page in writer.pages {
            for name in ["/AA", "/Annots"] {
                if name in page {
                    del page[name];
                }
            }
        }
        out = io.BytesIO();
        writer.write(out);
        return out.getvalue();
    } except PdfRejected as e {
        raise e;
    } except Exception {
        raise PdfRejected("invalid_pdf", unreadable);
    }
}

def pdf_key(tenant_id: str) -> str {
    # Where a cinema's PDF is stored: a random name, never a path from the client.
    return f"tenant/{tenant_id}/documents/{uuid4()}.pdf";
}

def store_pdf(tenant_id: str, data_base64: str) -> str {
    # Checks, rebuilds and stores an uploaded PDF; its key, or Refused.
    try {
        clean = process_pdf(decode_pdf(data_base64));
    } except PdfRejected as e {
        raise Refused(e.code, e.message);
    }
    key = pdf_key(tenant_id);
    media_store().upload(io.BytesIO(clean), key);
    return key;
}

def pdf_answer(key: str, title: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A stored PDF for the storefront: its title and the file as base64.
    data = read_media(key);
    if not data {
        return NOT_FOUND;
    }
    return {"ok": True, "title": title, "pdf": base64.b64encode(data).decode()};
}

node PublicDocuments {
    # The cinema's public documents, in the order shown: [{id, title, key,
    # uploaded_at}]. Owned by its principal.
    has tenant_id: str,
        items: list[dict[str, str]] = [];
}

def _kept(cinema: Tenant) -> PublicDocuments | None {
    if not cinema.documents_id {
        return None;
    }
    try {
        found: any = jobj(cinema.documents_id);  # jac:ignore[W1037]
    } except Exception {
        return None;
    }
    return found if isinstance(found, PublicDocuments) else None;
}

def documents_of(cinema: Tenant) -> list[dict[str, str]] {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = _kept(cinema);
        return [dict(d) for d in found.items] if found else [];
    } finally {
        restore(me);
    }
}

def public_list(cinema: Tenant) -> list[dict[str, str]] {
    # What the storefront's footer links to: each document's id and title.
    return [{"id": d["id"], "title": d["title"]} for d in documents_of(cinema)];
}

def _listing(cinema: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "documents": [
            {"id": d["id"], "title": d["title"], "uploaded_at": d["uploaded_at"]}
            for d in documents_of(cinema)
        ],
        "suggested": SUGGESTED
    };
}

def _write(cinema: Tenant, tenant_id: str, items: list[dict[str, str]]) {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = _kept(cinema);
        if found is None {
            made = PublicDocuments(tenant_id=tenant_id);
            cinema ++> made;
            attach_to_tenant(made, cinema);
            cinema.documents_id = node_id(made);
            found = made;
        }
        kept: PublicDocuments = found;
        kept.items = items;
        flush_now();
    } finally {
        restore(me);
    }
}

def _upload(tenant: str, title: str, data_base64: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    name = " ".join((title or "").split()) if isinstance(title, str) else "";
    if not name or len(name) > TITLE_MAX or "<" in name or ">" in name {
        raise Refused(
            "invalid_title",
            f"Give the document a title of up to {TITLE_MAX} characters, in plain text."
        );
    }
    items = documents_of(scope.tenant);
    if len(items) >= DOCUMENTS_MAX {
        raise Refused(
            "too_many_documents",
            f"You can show up to {DOCUMENTS_MAX} documents. Remove one first."
        );
    }
    key = store_pdf(scope.ctx.tenant_id, data_base64);
    try {
        _write(
            scope.tenant,
            scope.ctx.tenant_id,
            items
                + [
                    {
                        "id": uuid4().hex,
                        "title": name,
                        "key": key,
                        "uploaded_at": now().isoformat()
                    }
                ]
        );
    } except Exception as e {
        media_store().delete(key);
        raise e;
    }
    return _listing(scope.tenant);
}

def _remove(tenant: str, document_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    items = documents_of(scope.tenant);
    gone = [
        d
        for d in items
        if d["id"] == document_id
    ];
    if not gone {
        raise Refused("unknown_document", "That document isn't there any more.");
    }
    _write(
        scope.tenant,
        scope.ctx.tenant_id,
        [
            d
            for d in items
            if d["id"] != document_id
        ]
    );
    key = gone[0]["key"];
    on_commit(lambda { media_store().delete(key); });
    return _listing(scope.tenant);
}

def:protect public_documents_admin(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The cinema's public documents, for Settings -> Documents.
    return answer(
        lambda -> any { return _listing(scoped(tenant, CONFIGURE).tenant); }  # jac:ignore[W1037]
    );
}

def:protect upload_public_document(
    tenant: str, title: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "document.uploaded",
        "document",
        "",
        lambda -> any { return _upload(tenant, title, data_base64); }  # jac:ignore[W1037]
    );
}

def:protect remove_public_document(tenant: str, document_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "document.removed",
        "document",
        document_id,
        lambda -> any { return _remove(tenant, document_id); }  # jac:ignore[W1037]
    );
}

def:pub public_document(slug: str, document_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # One of a public cinema's documents, as base64, for its page on the storefront.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    for d in documents_of(cinema) {
        if d["id"] == document_id {
            return pdf_answer(d["key"], d["title"]);
        }
    }
    return NOT_FOUND;
}
