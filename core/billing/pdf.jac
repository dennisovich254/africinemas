"""A small PDF writer for statements and invoices (P15.4, ADR-0083).

Text only, on A4, in the three fonts every PDF reader has (Helvetica, Helvetica-Bold
and Courier), so nothing is embedded and nothing new is installed. Each line has its
text at the left margin, more text at given x positions, and amounts right-aligned in
Courier (whose letters are all 0.6 of the size wide, so they line up exactly). A line
that wouldn't fit starts a new page. Text is Windows-1252 (WinAnsiEncoding): anything
else becomes "?".
"""

glob WIDTH: int = 595,
     HEIGHT: int = 842,
     MARGIN: int = 50,
     BOTTOM: int = 60,
     COURIER_WIDTH: float = 0.6;

obj PdfLine {
    # cols: (text, x) in Helvetica; nums: (text, right edge x) in Courier.
    has text: str = "",
        size: int = 10,
        bold: bool = False,
        cols: list[tuple[str, float]] = [],
        nums: list[tuple[str, float]] = [],
        # Extra space above the line, in points.
        gap: int = 0;
}

def _clean(text: str) -> str {
    # Windows-1252 only.
    return str(text).encode("cp1252", "replace").decode("cp1252");
}

def _plain(text: str) -> str {
    # With PDF's string escapes.
    kept = _clean(text);
    return kept.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)");
}

def _show(font: str, size: int, x: float, y: float, text: str) -> str {
    return f"BT /{font} {size} Tf {x:.1f} {y:.1f} Td ({_plain(text)}) Tj ET\n";
}

def _pages(lines: list[PdfLine]) -> list[str] {
    # Each page's content stream.
    pages: list[str] = [];
    now = "";
    y = float(HEIGHT - MARGIN);
    for line in lines {
        step = line.size * 1.5 + line.gap;
        if y - step < BOTTOM and now {
            pages.append(now);
            now = "";
            y = float(HEIGHT - MARGIN);
        }
        y -= step;
        font = "F2" if line.bold else "F1";
        if line.text {
            now += _show(font, line.size, MARGIN, y, line.text);
        }
        for (text, x) in line.cols {
            now += _show(font, line.size, x, y, text);
        }
        for (text, right) in line.nums {
            width = len(_clean(text)) * line.size * COURIER_WIDTH;
            now += _show("F3", line.size, right - width, y, text);
        }
    }
    pages.append(now);
    return pages;
}

def pdf_bytes(lines: list[PdfLine], title: str) -> bytes {
    # The whole document.
    objects: list[str] = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
        f"<< /Title ({_plain(title)}) /Producer (AfriCinemas) >>"
    ];
    kids: list[str] = [];
    for content in _pages(lines) {
        objects.append(f"<< /Length {len(content)} >>\nstream\n{content}endstream");
        stream_ref = len(objects);
        objects.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {WIDTH} {HEIGHT}] "
                + "/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> "
                + f"/Contents {stream_ref} 0 R >>"
        );
        kids.append(f"{len(objects)} 0 R");
    }
    objects[1] = f"<< /Type /Pages /Kids [{' '.join(kids)}] /Count {len(kids)} >>";
    out = "%PDF-1.4\n";
    offsets: list[int] = [];
    for (n, body) in enumerate(objects) {
        offsets.append(len(out));
        out += f"{n + 1} 0 obj\n{body}\nendobj\n";
    }
    xref = len(out);
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n";
    for at in offsets {
        out += f"{at:010d} 00000 n \n";
    }
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R /Info 6 0 R >>\n";
    out += f"startxref\n{xref}\n%%EOF\n";
    # Every character is one byte in Windows-1252, so the offsets above are bytes.
    return out.encode("cp1252");
}
