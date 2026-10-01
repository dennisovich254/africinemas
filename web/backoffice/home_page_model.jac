"""The home-page editor's logic (P4.1b), kept apart from its layout (HomePageSection).

Pages have the shape core/homepage/page.jac stores: {"template", "sections": [{"type",
"visible", "fields"}]}. Every change returns a new page, so React sees it. The server
checks everything again on save; these only shape the edits.
"""

glob:pub SECTION_LABELS: dict[str, str] = {
         "hero": "Featured movie",
         "today": "Showtimes by day",
         "now_showing": "Now showing",
         "coming_soon": "Coming soon",
         "about": "About",
         "location": "Location and opening hours",
         "contact": "Contact and social links",
         "faq": "Questions"
     },
     TEMPLATE_INFO: list[dict[str, str]] = [
         {
             "name": "marquee",
             "label": "Marquee",
             "text": "Leads with a large featured movie and its poster."
         },
         {
             "name": "schedule",
             "label": "Schedule",
             "text": "Leads with today's showtimes, for cinemas people visit on the day."
         },
         {
             "name": "compact",
             "label": "Compact",
             "text": "One narrow scrolling list, for small cinemas."
         }
     ],
     # The empty row each list field adds.
     NEW_ROWS: dict[str, dict[str, str]] = {
         "hours": {"days": "", "times": ""},
         "links": {"label": "", "url": ""},
         "items": {"question": "", "answer": ""}
     };

def _copy(page: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    win: any = window;  # jac:ignore[W1037,W2001]
    return win.JSON.parse(win.JSON.stringify(page));  # jac:ignore[W6001,W6002] client-only deep copy
}

def:pub same_page(a: dict[str, any], b: dict[str, any]) -> bool {  # jac:ignore[W1037]
    # Pages from the server keep their keys' order, and edits never reorder keys.
    win: any = window;  # jac:ignore[W1037,W2001]
    return win.JSON.stringify(a) == win.JSON.stringify(b);  # jac:ignore[W6001,W6002] client-only
}

def:pub with_template(page: dict[str, any], template: str) -> dict[str, any] {  # jac:ignore[W1037]
    changed = _copy(page);
    changed["template"] = template;
    return changed;
}

def:pub moved(page: dict[str, any], index: int, step: int) -> dict[str, any] {  # jac:ignore[W1037]
    # The page with section `index` moved up (step -1) or down (step 1).
    changed = _copy(page);
    sections: list[any] = changed["sections"];  # jac:ignore[W1037]
    target = index + step;
    if target < 0 or target >= len(sections) {
        return changed;
    }
    item = sections[index];
    sections[index] = sections[target];
    sections[target] = item;
    return changed;
}

def:pub with_visible(
    page: dict[str, any],  # jac:ignore[W1037]
    index: int,
    visible: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    changed = _copy(page);
    changed["sections"][index]["visible"] = visible;
    return changed;
}

def:pub with_field(
    page: dict[str, any],  # jac:ignore[W1037]
    index: int,
    name: str,
    value: any  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    changed = _copy(page);
    changed["sections"][index]["fields"][name] = value;
    return changed;
}

def:pub with_row_field(  # jac:ignore[W3030] a list row's field: page, section, list, row, field, value
    page: dict[str, any],  # jac:ignore[W1037]
    index: int,
    name: str,
    row: int,
    key: str,
    value: str
) -> dict[str, any] {  # jac:ignore[W1037]
    changed = _copy(page);
    changed["sections"][index]["fields"][name][row][key] = value;
    return changed;
}

def:pub with_row_added(page: dict[str, any], index: int, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    changed = _copy(page);
    rows: list[any] = changed["sections"][index]["fields"][name];  # jac:ignore[W1037]
    rows.append(_copy(NEW_ROWS[name]));
    return changed;
}

def:pub with_row_removed(
    page: dict[str, any],  # jac:ignore[W1037]
    index: int,
    name: str,
    row: int
) -> dict[str, any] {  # jac:ignore[W1037]
    changed = _copy(page);
    rows: list[any] = changed["sections"][index]["fields"][name];  # jac:ignore[W1037]
    changed["sections"][index]["fields"][name] = [
        r
        for (i, r) in enumerate(rows)
        if i != row
    ];
    return changed;
}

def:pub toggled(chosen: list[str], item: str, limit: int) -> list[str] {
    # `chosen` with `item` added (up to `limit`) or taken out.
    if item in chosen {
        return [
            c
            for c in chosen
            if c != item
        ];
    }
    if len(chosen) >= limit {
        return chosen;
    }
    return chosen + [item];
}

def:pub problems_by_path(problems: list[dict[str, str]]) -> dict[str, str] {
    # The first problem for each field path, so each shows under its field.
    found: dict[str, str] = {};
    for p in problems {
        if p["path"] not in found {
            found[p["path"]] = p["message"];
        }
    }
    return found;
}

def:pub version_text(v: dict[str, any]) -> str {  # jac:ignore[W1037]
    # "Version 3 · Schedule".
    label = v["template"];
    for t in TEMPLATE_INFO {
        if t["name"] == v["template"] {
            label = t["label"];
        }
    }
    return f"Version {v['version']} · {label}";
}
