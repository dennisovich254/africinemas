"""A cinema's home page as data (P4.1b, architecture §41, §55), as pure logic.

Structure is code, content is data. A page is a template name and an ordered list of
sections, each of one of a fixed set of types, shown or hidden, with typed,
length-limited, plain-text fields. Tenants never supply HTML, CSS or JS: text with
markup characters is refused and links must be https. Templates are named section
orders and layouts (the storefront draws each one).

parse_page reports every problem at once, each with the dotted path of the field it's
about ("sections.2.fields.map_url"), so the editor can show it beside that field.
Movies are named by id here; the storefront only ever sees their public keys.
"""

import re;

obj Field {
    # A field's kind ("text", "url", "email", "id", "ids" or "list") and its LIMITS
    # key: a length for text, a count for "ids" and "list". A list's items are small
    # records of text fields, each with its own limit ("url" items must be https).
    has kind: str,
        limit: str,
        item_fields: dict[str, str] = {};
}

glob SECTION_TYPES: list[str] = [
         "hero",
         "today",
         "now_showing",
         "coming_soon",
         "about",
         "location",
         "contact",
         "faq"
     ],
     # Each template's section order. Marquee is poster-led, Schedule puts today's
     # showtimes first, and Compact is one scrolling list for small cinemas.
     TEMPLATES: dict[str, list[str]] = {
         "marquee": [
             "hero",
             "now_showing",
             "coming_soon",
             "today",
             "about",
             "location",
             "contact",
             "faq"
         ],
         "schedule": [
             "today",
             "now_showing",
             "coming_soon",
             "hero",
             "location",
             "about",
             "contact",
             "faq"
         ],
         "compact": [
             "now_showing",
             "today",
             "coming_soon",
             "location",
             "contact",
             "about",
             "faq",
             "hero"
         ]
     },
     # Sections a template starts with hidden.
     HIDDEN_AT_FIRST: dict[str, list[str]] = {
         "marquee": [],
         "schedule": ["hero"],
         "compact": ["hero"]
     },
     DEFAULT_TEMPLATE: str = "marquee",
     LIMITS: dict[str, int] = {
         "title": 60,
         "headline": 80,
         "lead": 160,
         "text": 1500,
         "address": 200,
         "url": 500,
         "phone": 30,
         "email": 120,
         "id": 64,
         "movie_ids": 8,
         "hours": 7,
         "days": 40,
         "times": 40,
         "links": 6,
         "label": 40,
         "faq_items": 12,
         "question": 160,
         "answer": 800
     },
     FIELDS: dict[str, dict[str, Field]] = {
         "hero": {
             "headline": Field(kind="text", limit="headline"),
             "text": Field(kind="text", limit="lead"),
             "movie_id": Field(kind="id", limit="id")
         },
         "today": {"title": Field(kind="text", limit="title")},
         "now_showing": {"title": Field(kind="text", limit="title")},
         "coming_soon": {
             "title": Field(kind="text", limit="title"),
             "movie_ids": Field(kind="ids", limit="movie_ids")
         },
         "about": {
             "title": Field(kind="text", limit="title"),
             "text": Field(kind="text", limit="text")
         },
         "location": {
             "title": Field(kind="text", limit="title"),
             "address": Field(kind="text", limit="address"),
             "map_url": Field(kind="url", limit="url"),
             "hours": Field(
                 kind="list",
                 limit="hours",
                 item_fields={"days": "days", "times": "times"}
             )
         },
         "contact": {
             "title": Field(kind="text", limit="title"),
             "phone": Field(kind="text", limit="phone"),
             "email": Field(kind="email", limit="email"),
             "links": Field(
                 kind="list",
                 limit="links",
                 item_fields={"label": "label", "url": "url"}
             )
         },
         "faq": {
             "title": Field(kind="text", limit="title"),
             "items": Field(
                 kind="list",
                 limit="faq_items",
                 item_fields={"question": "question", "answer": "answer"}
             )
         }
     },
     URL_PATTERN: str = "https://[^\\s/?#]+\\.[^\\s/?#]+[^\\s]*",
     EMAIL_PATTERN: str = "[^@\\s]+@[^@\\s]+\\.[^@\\s]+",
     MARKUP: list[str] = ["<", ">"];

obj PageProblem {
    has path: str,
        code: str,
        message: str;
}

def _empty(kind: str) -> any {  # jac:ignore[W1037]
    return [] if kind in ["ids", "list"] else "";
}

def _section(kind: str, visible: bool) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "type": kind,
        "visible": visible,
        "fields": {name: _empty(spec.kind) for (name, spec) in FIELDS[kind].items()}
    };
}

def default_page(template: str = DEFAULT_TEMPLATE) -> dict[str, any] {  # jac:ignore[W1037]
    # The template's sections in its order, with nothing filled in.
    return {
        "template": template,
        "sections": [
            _section(kind, kind not in HIDDEN_AT_FIRST[template])
            for kind in TEMPLATES[template]
        ]
    };
}

obj _Checker {
    has problems: list[PageProblem] = [];

    def problem(path: str, code: str, message: str) {
        self.problems.append(PageProblem(path=path, code=code, message=message));
    }

    def text(path: str, value: any, limit: str) -> str {  # jac:ignore[W1037]
        if not isinstance(value, str) {
            self.problem(path, "bad_value", "Enter text here.");
            return "";
        }
        cleaned = value.strip();
        if any(c in cleaned for c in MARKUP) {
            self.problem(path, "markup", "Leave out < and >: this is plain text.");
        } elif len(cleaned) > LIMITS[limit] {
            self.problem(
                path, "too_long", f"Keep this to {LIMITS[limit]} characters or fewer."
            );
        }
        return cleaned;
    }

    def url(path: str, value: any) -> str {  # jac:ignore[W1037]
        cleaned = self.text(path, value, "url");
        if cleaned and not re.fullmatch(URL_PATTERN, cleaned) {
            self.problem(
                path, "bad_url", "Enter a full web address starting with https://."
            );
        }
        return cleaned;
    }

    def email(path: str, value: any) -> str {  # jac:ignore[W1037]
        cleaned = self.text(path, value, "email");
        if cleaned and not re.fullmatch(EMAIL_PATTERN, cleaned) {
            self.problem(
                path, "bad_value", "Enter an email address, like name@example.com."
            );
        }
        return cleaned;
    }

    def ids(path: str, value: any, limit: str) -> list[str] {  # jac:ignore[W1037]
        if not isinstance(value, list) {
            self.problem(path, "bad_value", "Choose from the list.");
            return [];
        }
        if len(value) > LIMITS[limit] {
            self.problem(path, "too_many", f"Choose up to {LIMITS[limit]}.");
            return [];
        }
        chosen: list[str] = [];
        for (i, item) in enumerate(value) {
            one = self.text(f"{path}.{i}", item, "id");
            if one and one not in chosen {
                chosen.append(one);
            }
        }
        return chosen;
    }

    def items(
        path: str,
        value: any,  # jac:ignore[W1037]
        limit: str,
        item_fields: dict[str, str]
    ) -> list[dict[str, str]] {
        if not isinstance(value, list) {
            self.problem(path, "bad_value", "This should be a list.");
            return [];
        }
        if len(value) > LIMITS[limit] {
            self.problem(path, "too_many", f"Add up to {LIMITS[limit]}.");
            return [];
        }
        cleaned: list[dict[str, str]] = [];
        for (i, item) in enumerate(value) {
            if not isinstance(item, dict) {
                self.problem(f"{path}.{i}", "bad_value", "This entry isn't readable.");
                continue;
            }
            one: dict[str, str] = {};
            for key in item.keys() {
                if key not in item_fields {
                    self.problem(
                        f"{path}.{i}.{key}", "unknown_field", "This isn't a field here."
                    );
                }
            }
            for (key, item_limit) in item_fields.items() {
                raw = item.get(key, "");
                one[key] = self.url(f"{path}.{i}.{key}", raw)
                    if key == "url"
                    else self.text(f"{path}.{i}.{key}", raw, item_limit);
            }
            cleaned.append(one);
        }
        return cleaned;
    }

    def fields(path: str, kind: str, value: any) -> dict[str, any] {  # jac:ignore[W1037]
        spec = FIELDS[kind];
        if not isinstance(value, dict) {
            self.problem(path, "bad_value", "This section's fields aren't readable.");
            value = {};
        }
        for key in value.keys() {
            if key not in spec {
                self.problem(
                    f"{path}.{key}",
                    "unknown_field",
                    "This isn't a field of this section."
                );
            }
        }
        cleaned: dict[str, any] = {};  # jac:ignore[W1037]
        for (name, field) in spec.items() {
            raw = value.get(name, _empty(field.kind));
            where = f"{path}.{name}";
            if field.kind == "text" {
                cleaned[name] = self.text(where, raw, field.limit);
            } elif field.kind == "url" {
                cleaned[name] = self.url(where, raw);
            } elif field.kind == "email" {
                cleaned[name] = self.email(where, raw);
            } elif field.kind == "id" {
                cleaned[name] = self.text(where, raw, field.limit);
            } elif field.kind == "ids" {
                cleaned[name] = self.ids(where, raw, field.limit);
            } else {
                cleaned[name] = self.items(where, raw, field.limit, field.item_fields);
            }
        }
        return cleaned;
    }
}

def parse_page(data: any) -> tuple[dict[str, any] | None, list[PageProblem]] {  # jac:ignore[W1037]
    # The page in its stored shape, or None and every problem with it.
    check = _Checker();
    if not isinstance(data, dict) {
        check.problem("", "not_a_page", "This isn't a home page.");
        return (None, check.problems);
    }
    template = data.get("template", DEFAULT_TEMPLATE);
    if template not in TEMPLATES {
        check.problem("template", "unknown_template", "Choose one of the templates.");
        template = DEFAULT_TEMPLATE;
    }
    raw_sections = data.get("sections", []);
    if not isinstance(raw_sections, list) {
        check.problem("sections", "bad_value", "The sections aren't readable.");
        raw_sections = [];
    }
    sections: list[dict[str, any]] = [];  # jac:ignore[W1037]
    seen: list[str] = [];
    for (i, raw) in enumerate(raw_sections) {
        path = f"sections.{i}";
        if not isinstance(raw, dict) {
            check.problem(path, "bad_value", "This section isn't readable.");
            continue;
        }
        kind = str(raw.get("type", ""));
        if kind not in SECTION_TYPES {
            check.problem(
                f"{path}.type", "unknown_section", "This isn't a kind of section."
            );
            continue;
        }
        if kind in seen {
            check.problem(
                f"{path}.type",
                "duplicate_section",
                "This section is already on the page."
            );
            continue;
        }
        seen.append(kind);
        visible = raw.get("visible", True);
        if not isinstance(visible, bool) {
            check.problem(f"{path}.visible", "bad_value", "Choose shown or hidden.");
            visible = True;
        }
        sections.append(
            {
                "type": kind,
                "visible": visible,
                "fields": check.fields(f"{path}.fields", kind, raw.get("fields", {}))
            }
        );
    }
    # Sections the page leaves out keep their place in the template, hidden.
    for kind in TEMPLATES[template] {
        if kind not in seen {
            sections.append(_section(kind, False));
        }
    }
    if check.problems {
        return (None, check.problems);
    }
    return ({"template": template, "sections": sections}, []);
}

def page_movie_ids(page: dict[str, any]) -> list[str] {  # jac:ignore[W1037]
    # The movies the page names, featured first.
    found: list[str] = [];
    for s in page["sections"] {
        if s["type"] == "hero" and s["fields"]["movie_id"] {
            found.append(s["fields"]["movie_id"]);
        } elif s["type"] == "coming_soon" {
            found.extend(s["fields"]["movie_ids"]);
        }
    }
    ordered: list[str] = [];
    for m in found {
        if m not in ordered {
            ordered.append(m);
        }
    }
    return ordered;
}
