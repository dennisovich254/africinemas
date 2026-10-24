"""P14.3d: uploaded PDFs are checked, then rebuilt from their pages alone."""

import io;
import warnings;
import base64;
import from pypdf { PdfReader, PdfWriter }
import from pypdf.annotations { Link }
import from core.catalog.documents { process_pdf, decode_pdf, PdfRejected, MAX_PAGES }

def _pdf(
    pages: int = 1,
    script: bool = False,
    attachment: bool = False,
    link: bool = False,
    password: str = ""
) -> bytes {
    writer = PdfWriter();
    for _ in range(pages) {
        writer.add_blank_page(width=200, height=200);
    }
    if script {
        # A document-level script; pypdf deprecates making one, not reading one.
        with warnings.catch_warnings() {
            warnings.simplefilter("ignore", DeprecationWarning);
            writer.add_js("app.alert('hi');");
        }
    }
    if attachment {
        writer.add_attachment("evil.exe", b"MZ...");
    }
    if link {
        writer.add_annotation(
            page_number=0,
            annotation=Link(rect=(10, 10, 50, 50), url="https://evil.example")
        );
    }
    if password {
        writer.encrypt(password);
    }
    out = io.BytesIO();
    writer.write(out);
    return out.getvalue();
}

def _code(data: bytes) -> str {
    try {
        process_pdf(data);
    } except PdfRejected as e {
        return e.code;
    }
    return "";
}

test "a PDF is rebuilt from its pages, without scripts, attachments or links" {
    clean = process_pdf(_pdf(pages=2, script=True, attachment=True, link=True));
    assert clean.startswith(b"%PDF-");
    rebuilt = PdfReader(io.BytesIO(clean));
    assert len(rebuilt.pages) == 2;
    catalog: any = rebuilt.trailer["/Root"];  # jac:ignore[W1037]
    for gone in ["/Names", "/OpenAction", "/AcroForm", "/AA"] {
        assert gone not in catalog , gone;
    }
    for page in rebuilt.pages {
        assert "/Annots" not in page and "/AA" not in page;
    }
    assert b"app.alert" not in clean and b"evil" not in clean;
}

test "anything that isn't a readable, open PDF of a few pages is refused" {
    assert _code(b"hello") == "invalid_pdf";
    assert _code(b"%PDF-1.7 not really") == "invalid_pdf";
    assert _code(b"\x89PNG\r\n\x1a\n") == "invalid_pdf";
    assert _code(_pdf(password="secret")) == "pdf_protected";
    assert _code(_pdf(pages=MAX_PAGES + 1)) == "too_many_pages";
    assert _code(_pdf(pages=MAX_PAGES)) == "";
}

test "the upload's size is checked before it's decoded" {
    for (sent, code) in [
        ("", "invalid_pdf"),
        ("not base64!", "invalid_pdf"),
        ("A" * (15 * 1024 * 1024), "too_large")
    ] {
        try {
            decode_pdf(sent);
            assert False , sent[:20];
        } except PdfRejected as e {
            assert e.code == code , e.code;
        }
    }
    assert decode_pdf(base64.b64encode(b"%PDF-").decode()) == b"%PDF-";
}
