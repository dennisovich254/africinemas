"""The legal documents' text, from the small Markdown they're written in (P15.0b).

legal_blocks turns the text into blocks (headings, paragraphs, lists, tables, rules),
and spans turns a line into plain text, bold, code and links. Everything is drawn as
React text, never as HTML. A link is kept only to another legal page (/legal/...) or
an https address; any other becomes plain text.
"""

glob DIGITS: str = "0123456789";

def _find(text: str, part: str, start: int) -> int {
    # Where `part` next occurs in `text` from `start`, or -1.
    size = len(part);
    i = start;
    while i + size <= len(text) {
        if text[i:i + size] == part {
            return i;
        }
        i += 1;
    }
    return -1;
}

def:pub safe_href(href: str) -> str {
    # The link's address if it's one we keep, else "".
    if href.startswith("/legal/") or href.startswith("https://") {
        return href;
    }
    return "";
}

def:pub spans(text: str) -> list[dict[str, str]] {
    # A line's pieces: {"kind": "text" | "bold" | "code" | "link", "text", "href"}.
    out: list[dict[str, str]] = [];
    plain = "";
    i = 0;
    while i < len(text) {
        piece: dict[str, str] | None = None;
        after = i;
        if text[i:i + 2] == "**" {
            end = _find(text, "**", i + 2);
            if end > i + 2 {
                piece = {"kind": "bold", "text": text[i + 2:end], "href": ""};
                after = end + 2;
            }
        } elif text[i] == "`" {
            end = _find(text, "`", i + 1);
            if end > i + 1 {
                piece = {"kind": "code", "text": text[i + 1:end], "href": ""};
                after = end + 1;
            }
        } elif text[i] == "[" {
            middle = _find(text, "](", i + 1);
            end = _find(text, ")", middle + 2) if middle > i else -1;
            if middle > i and end > middle {
                href = safe_href(text[middle + 2:end]);
                piece = {
                    "kind": "link" if href else "text",
                    "text": text[i + 1:middle],
                    "href": href
                };
                after = end + 1;
            }
        }
        if piece is None {
            plain += text[i];
            i += 1;
            continue;
        }
        if len(plain) > 0 {
            out.append({"kind": "text", "text": plain, "href": ""});
            plain = "";
        }
        out.append(piece);
        i = after;
    }
    if len(plain) > 0 {
        out.append({"kind": "text", "text": plain, "href": ""});
    }
    return out;
}

def _numbered(line: str) -> int {
    # Where a numbered item's text starts ("3. text" -> 3), or 0 if it isn't one.
    j = 0;
    while j < len(line) and line[j] in DIGITS {
        j += 1;
    }
    return j + 2 if j > 0 and line[j:j + 2] == ". " else 0;
}

def _cells(line: str) -> list[str] {
    inner = line.strip();
    if inner.startswith("|") {
        inner = inner[1:];
    }
    if inner.endswith("|") {
        inner = inner[:len(inner) - 1];
    }
    return [c.strip() for c in inner.split("|")];
}

def _is_rule(cells: list[str]) -> bool {
    # A table's |---|---| line.
    for c in cells {
        if len(c.replace("-", "").replace(":", "").strip()) > 0 {
            return False;
        }
    }
    return True;
}

def:pub legal_blocks(text: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # {"kind": "h1" | "h2" | "h3" | "p" | "ul" | "ol" | "table" | "hr", "text",
    # "items", "rows"}.
    blocks: list[dict[str, any]] = [];  # jac:ignore[W1037]
    para: list[str] = [];
    lines = (text or "").split("\n");
    i = 0;
    while i < len(lines) {
        raw = lines[i];
        line = raw.strip();
        starts_block = len(line) == 0
            or line.startswith("#")
            or line == "---"
            or line.startswith("|")
            or line.startswith("- ")
            or _numbered(line) > 0;
        if starts_block and len(para) > 0 {
            blocks.append({"kind": "p", "text": " ".join(para)});
            para = [];
        }
        if len(line) == 0 {
            i += 1;
        } elif line.startswith("#") {
            level = 0;
            while level < len(line) and line[level] == "#" {
                level += 1;
            }
            kind = "h1" if level == 1 else ("h2" if level == 2 else "h3");
            blocks.append({"kind": kind, "text": line[level:].strip()});
            i += 1;
        } elif line == "---" {
            blocks.append({"kind": "hr"});
            i += 1;
        } elif line.startswith("|") {
            rows: list[list[str]] = [];
            while i < len(lines) and lines[i].strip().startswith("|") {
                cells = _cells(lines[i]);
                if not _is_rule(cells) {
                    rows.append(cells);
                }
                i += 1;
            }
            blocks.append({"kind": "table", "rows": rows});
        } elif line.startswith("- ") or _numbered(line) > 0 {
            ordered = not line.startswith("- ");
            items: list[str] = [];
            while i < len(lines) {
                here = lines[i].strip();
                start = _numbered(here);
                if not ordered and here.startswith("- ") {
                    items.append(here[2:]);
                } elif ordered and start > 0 {
                    items.append(here[start:]);
                } elif len(here) > 0 and lines[i].startswith("  ") and len(items) > 0 {
                    items[len(items) - 1] = items[len(items) - 1] + " " + here;
                } else {
                    break;
                }
                i += 1;
            }
            blocks.append({"kind": "ol" if ordered else "ul", "items": items});
        } else {
            para.append(line);
            i += 1;
        }
    }
    if len(para) > 0 {
        blocks.append({"kind": "p", "text": " ".join(para)});
    }
    return blocks;
}
