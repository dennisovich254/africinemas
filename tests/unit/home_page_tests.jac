"""P4.1b: a cinema's home page as data (core/homepage/page.jac).

A page is a template name and an ordered list of typed sections, each from a fixed set,
with typed, length-limited, plain-text fields: tenants never supply HTML, CSS or JS
(architecture §55). parse_page reports every problem at once, each with the path of the
field it's about, so the editor can show it next to that field.
"""

import from core.homepage.page {
    TEMPLATES,
    SECTION_TYPES,
    LIMITS,
    default_page,
    parse_page,
    page_movie_ids
}

def _codes(data: any) -> list[tuple[str, str]] {  # jac:ignore[W1037]
    (page, problems) = parse_page(data);
    assert page is None or not problems;
    return [(p.path, p.code) for p in problems];
}

def _page(sections: list[dict[str, any]], template: str = "marquee") -> dict[str, any] {  # jac:ignore[W1037]
    return {"template": template, "sections": sections};
}

def _section(
    kind: str,
    fields: dict[str, any] | None = None,  # jac:ignore[W1037]
    visible: bool = True
) -> dict[str, any] {  # jac:ignore[W1037]
    return {"type": kind, "visible": visible, "fields": fields or {}};
}

test "there are three templates, each ordering every section type once" {
    assert sorted(TEMPLATES.keys()) == ["compact", "marquee", "schedule"];
    for (name, order) in TEMPLATES.items() {
        assert sorted(order) == sorted(SECTION_TYPES) , name;
    }
    assert TEMPLATES["marquee"][0] == "hero";
    assert TEMPLATES["schedule"][0] == "today";
}

test "every template's default page is valid and keeps its order" {
    for name in TEMPLATES.keys() {
        page = default_page(name);
        assert page["template"] == name;
        assert [s["type"] for s in page["sections"]] == TEMPLATES[name];
        (parsed, problems) = parse_page(page);
        assert problems == [] , (name, problems);
        assert parsed == page , name;
    }
}

test "a full page with every kind of field is accepted and comes back cleaned" {
    data = _page(
        [
            _section(
                "hero",
                {
                    "headline": "  Nairobi's home of film ",
                    "text": "Since 1998.",
                    "movie_id": "m-1"
                }
            ),
            _section("today", {"title": "Today"}),
            _section("now_showing", {"title": "Now showing"}),
            _section(
                "coming_soon", {"title": "Coming soon", "movie_ids": ["m-2", "m-3"]}
            ),
            _section("about", {"title": "About us", "text": "Two screens.\nOne café."}),
            _section(
                "location",
                {
                    "title": "Find us",
                    "address": "Mwanzi Road, Westlands",
                    "map_url": "https://maps.example.com/nova",
                    "hours": [{"days": "Mon–Fri", "times": "12:00–23:00"}]
                }
            ),
            _section(
                "contact",
                {
                    "title": "Contact",
                    "phone": "+254 700 000 000",
                    "email": "hello@nova.example",
                    "links": [
                        {"label": "Instagram", "url": "https://instagram.com/nova"}
                    ]
                }
            ),
            _section(
                "faq",
                {
                    "title": "Questions",
                    "items": [{"question": "Parking?", "answer": "Free for 3 hours."}]
                },
                visible=False
            )
        ],
        template="schedule"
    );
    (page, problems) = parse_page(data);
    assert problems == [] and page is not None , problems;
    assert page["template"] == "schedule";
    hero = page["sections"][0];
    assert hero["fields"]["headline"] == "Nairobi's home of film";
    assert page["sections"][7]["visible"] is False;
    assert page["sections"][4]["fields"]["text"] == "Two screens.\nOne café.";
    assert page_movie_ids(page) == ["m-1", "m-2", "m-3"];
}

test "missing fields take their defaults, and sections left out are added hidden" {
    (page, problems) = parse_page(_page([_section("about", {"text": "Hello."})]));
    assert problems == [] , problems;
    assert [s["type"] for s in page["sections"]][0] == "about";
    about = page["sections"][0];
    assert about["fields"]["text"] == "Hello." and about["fields"]["title"] == "";
    assert sorted(s["type"] for s in page["sections"]) == sorted(SECTION_TYPES);
    assert all(not s["visible"] for s in page["sections"][1:]);
}

test "unknown templates, section types and fields are refused" {
    assert _codes(_page([], template="neon")) == [("template", "unknown_template")];
    assert _codes(_page([_section("marquee_banner")]))
        == [("sections.0.type", "unknown_section")];
    assert _codes(_page([_section("about", {"html": "<b>hi</b>"})]))
        == [("sections.0.fields.html", "unknown_field")];
    assert _codes(_page([_section("about"), _section("about")]))
        == [("sections.1.type", "duplicate_section")];
    assert _codes("not a page") == [("", "not_a_page")];
    assert _codes(_page([{"type": "about", "visible": "yes", "fields": {}}]))
        == [("sections.0.visible", "bad_value")];
}

test "text over its limit, or with markup, is refused" {
    too_long = "x" * (LIMITS["headline"] + 1);
    assert _codes(_page([_section("hero", {"headline": too_long})]))
        == [("sections.0.fields.headline", "too_long")];
    for bad in ["<script>alert(1)</script>", "Hi <b>there</b>", "a > b"] {
        assert _codes(_page([_section("about", {"text": bad})]))
            == [("sections.0.fields.text", "markup")] , bad;
    }
    assert _codes(_page([_section("hero", {"headline": 42})]))
        == [("sections.0.fields.headline", "bad_value")];
}

test "links must be https, and lists have a maximum length" {
    for bad in ["javascript:alert(1)", "http://maps.example.com", "maps.example.com"] {
        assert _codes(_page([_section("location", {"map_url": bad})]))
            == [("sections.0.fields.map_url", "bad_url")] , bad;
    }
    assert _codes(
        _page(
            [
                _section(
                    "contact",
                    {"links": [{"label": "Site", "url": "data:text/html,hi"}]}
                )
            ]
        )
    )
        == [("sections.0.fields.links.0.url", "bad_url")];
    too_many = [{"question": "Q?", "answer": "A."}] * (LIMITS["faq_items"] + 1);
    assert _codes(_page([_section("faq", {"items": too_many})]))
        == [("sections.0.fields.items", "too_many")];
    assert _codes(_page([_section("contact", {"email": "not-an-email"})]))
        == [("sections.0.fields.email", "bad_value")];
}

test "every problem is reported at once" {
    data = _page(
        [
            _section("hero", {"headline": "<i>x</i>"}),
            _section("location", {"map_url": "ftp://x"}),
            _section("party")
        ],
        template="neon"
    );
    assert sorted(_codes(data))
        == [
            ("sections.0.fields.headline", "markup"),
            ("sections.1.fields.map_url", "bad_url"),
            ("sections.2.type", "unknown_section"),
            ("template", "unknown_template")
        ];
}

test "About can show a few photos, named by the photos the cinema uploaded" {
    (page, problems) = parse_page(
        _page([_section("about", {"text": "Our lobby.", "photos": ["p1", "p2"]})])
    );
    assert problems == [] and page is not None , problems;
    assert page["sections"][0]["fields"]["photos"] == ["p1", "p2"];
    too_many = [f"p{i}" for i in range(LIMITS["photos"] + 1)];
    assert _codes(_page([_section("about", {"photos": too_many})]))
        == [("sections.0.fields.photos", "too_many")];
}
