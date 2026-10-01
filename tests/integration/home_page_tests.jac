"""P4.1b: a cinema's home page, through the production app (main.jac).

The owner edits a draft page (save_home_page, checked by core/homepage/page.jac),
publishes it as the next numbered version and can roll back to an earlier one, like the
theme (P3.8). public_home then carries the published page with its sections filled from
the programme: the featured movie, today's showtimes, what's on and coming soon.
Hidden sections and sections with nothing to show are left out. Movies are named by
their public keys only, and another cinema's page is never affected.
"""

import io;
import os;
import base64;
import shutil;
import tempfile;
import from os { path }
import from PIL { Image }
import from tests.support.served { Served, served }
import from tests.support.storefront_setup {
    Cinema,
    open_cinema_for,
    add_movie,
    add_screening,
    browse,
    code_of
}

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     MEDIA_ENV: str = "AFRICINEMAS_MEDIA_DIR";

def _nova(names: list[str] | None = None) -> tuple[Served, Cinema] {  # jac:ignore[W1037]
    app = served(MAIN, ["owner"] + (names or []));
    nova = open_cinema_for(app, "owner", "nova", "Nova Cinemas");
    for title in ["Rafiki", "Supa Modo", "Kati Kati"] {
        add_movie(app, "owner", nova, title);
    }
    return (app, nova);
}

def _home(app: Served, slug: str = "nova") -> any {  # jac:ignore[W1037]
    return browse(app, "public_home", {"slug": slug});
}

def _types(app: Served, slug: str = "nova") -> list[str] {
    return [s["type"] for s in _home(app, slug)["page"]["sections"]];
}

def _section(app: Served, kind: str) -> dict[str, any] {  # jac:ignore[W1037]
    return [
        s
        for s in _home(app)["page"]["sections"]
        if s["type"] == kind
    ][0];
}

def _save(
    app: Served,
    template: str,
    sections: list[dict[str, any]],  # jac:ignore[W1037]
    slug: str = "nova"
) -> any {  # jac:ignore[W1037]
    return app.call(
        "owner" if slug == "nova" else "rival",
        "save_home_page",
        {"tenant": slug, "page": {"template": template, "sections": sections}}
    );
}

def _publish(app: Served, who: str = "owner", slug: str = "nova") -> any {  # jac:ignore[W1037]
    return app.call(who, "publish_home_page", {"tenant": slug});
}

def _about(text: str) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "type": "about",
        "visible": True,
        "fields": {"title": "About", "text": text}
    };
}

test "a new cinema's page is the Marquee template, and an empty cinema shows no empty sections" {
    (app, nova) = _nova();
    try {
        draft = app.call("owner", "get_home_page", {"tenant": "nova"});
        assert draft["ok"] , draft;
        assert draft["home"]["draft"]["template"] == "marquee";
        assert draft["home"]["published"] is None and draft["home"]["versions"] == [];
        options = draft["options"];
        assert sorted(options["templates"].keys())
            == ["compact", "marquee", "schedule"];
        assert [m["title"] for m in options["movies"]]
            == ["Kati Kati", "Rafiki", "Supa Modo"];
        home = _home(app);
        assert home["page"] == {"template": "marquee", "sections": []} , home["page"];
    } finally {
        app.close();
    }
}

test "an owner saves, publishes and rolls back the home page" {
    (app, nova) = _nova();
    try {
        saved = _save(app, "schedule", [_about("Two screens in Westlands.")]);
        assert saved["ok"] , saved;
        # The draft isn't public until it's published.
        assert _home(app)["page"]["template"] == "marquee";
        first = _publish(app);
        assert first["ok"] and first["version"] == 1 , first;
        page = _home(app)["page"];
        assert page["template"] == "schedule";
        assert page["sections"]
            == [
                {
                    "type": "about",
                    "fields": {"title": "About", "text": "Two screens in Westlands."}
                }
            ] , page;
        assert code_of(_publish(app)) == "nothing_to_publish";
        _save(app, "compact", [_about("Now with a café.")]);
        assert _publish(app)["version"] == 2;
        assert _section(app, "about")["fields"]["text"] == "Now with a café.";
        back = app.call(
            "owner", "rollback_home_page", {"tenant": "nova", "version": 1}
        );
        assert back["ok"] and back["version"] == 3 , back;
        assert _home(app)["page"]["template"] == "schedule";
        assert _section(app, "about")["fields"]["text"] == "Two screens in Westlands.";
        home = app.call("owner", "get_home_page", {"tenant": "nova"})["home"];
        assert [v["version"] for v in home["versions"]] == [3, 2, 1];
        assert home["draft"]["template"] == "schedule";
        assert code_of(
            app.call("owner", "rollback_home_page", {"tenant": "nova", "version": 9})
        )
            == "unknown_version";
    } finally {
        app.close();
    }
}

test "a bad page is refused with every problem, and the draft stays as it was" {
    (app, nova) = _nova(["rival"]);
    try {
        _save(app, "compact", [_about("Hello.")]);
        refused = _save(
            app,
            "neon",
            [
                _about("<script>alert(1)</script>"),
                {"type": "party", "visible": True, "fields": {}}
            ]
        );
        assert code_of(refused) == "invalid_page" , refused;
        assert sorted(p["path"] for p in refused["error"]["problems"])
            == ["sections.0.fields.text", "sections.1.type", "template"];
        draft = app.call("owner", "get_home_page", {"tenant": "nova"})["home"]["draft"];
        assert draft["template"] == "compact";
        # Another cinema's movie can't be featured.
        rift = open_cinema_for(app, "rival", "rift", "Rift Cinemas");
        theirs = add_movie(app, "rival", rift, "Rift Feature");
        refused = _save(
            app,
            "marquee",
            [{"type": "hero", "visible": True, "fields": {"movie_id": theirs}}]
        );
        assert code_of(refused) == "invalid_page";
        assert [(p["path"], p["code"]) for p in refused["error"]["problems"]]
            == [("sections.0.fields.movie_id", "unknown_movie")];
    } finally {
        app.close();
    }
}

test "sections fill from the programme, by public key, and hidden or empty ones are left out" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    (app, nova) = _nova();
    try {
        add_screening(app, "owner", nova, "Rafiki", 0);
        out = io.BytesIO();
        Image.new("RGB", (400, 600), "#7A2E3B").save(out, format="PNG");
        assert app.call(
            "owner",
            "upload_poster",
            {
                "tenant": "nova",
                "movie_id": nova.movies["Kati Kati"],
                "content_type": "image/png",
                "data_base64": base64.b64encode(out.getvalue()).decode()
            }
        )["ok"];
        saved = _save(
            app,
            "marquee",
            [
                {
                    "type": "hero",
                    "visible": True,
                    "fields": {
                        "headline": "Films worth the trip",
                        "movie_id": nova.movies["Rafiki"]
                    }
                },
                {"type": "now_showing", "visible": True, "fields": {}},
                {
                    "type": "coming_soon",
                    "visible": True,
                    "fields": {"movie_ids": [nova.movies["Kati Kati"]]}
                },
                {"type": "today", "visible": True, "fields": {}},
                {"type": "about", "visible": True, "fields": {}},
                {
                    "type": "faq",
                    "visible": False,
                    "fields": {"items": [{"question": "Parking?", "answer": "Yes."}]}
                }
            ]
        );
        assert saved["ok"] , saved;
        assert _publish(app)["ok"];
        # No showtimes today (they're two days ahead), an empty about, a hidden FAQ.
        assert _types(app) == ["hero", "now_showing", "coming_soon"];
        rafiki_key = _home(app)["movies"][0]["movie_key"];
        hero = _section(app, "hero");
        assert hero["fields"] == {"headline": "Films worth the trip", "text": ""};
        assert hero["movie"]["movie_key"] == rafiki_key
            and hero["movie"]["title"] == "Rafiki" , hero;
        assert [m["title"] for m in _section(app, "now_showing")["movies"]]
            == ["Rafiki"];
        soon = _section(app, "coming_soon")["movies"];
        assert [(m["title"], m["has_poster"]) for m in soon] == [("Kati Kati", True)];
        poster = browse(
            app, "public_poster", {"slug": "nova", "movie_key": soon[0]["movie_key"]}
        );
        assert poster["ok"] , poster;
        text = str(_home(app));
        for movie_id in nova.movies.values() {
            assert movie_id not in text , f"leaked {movie_id}";
        }
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}

test "a featured movie that isn't showing falls back to the next one on sale" {
    (app, nova) = _nova();
    try {
        add_screening(app, "owner", nova, "Supa Modo", 0);
        _save(
            app,
            "marquee",
            [
                {
                    "type": "hero",
                    "visible": True,
                    "fields": {"movie_id": nova.movies["Kati Kati"]}
                }
            ]
        );
        _publish(app);
        assert _section(app, "hero")["movie"]["title"] == "Supa Modo";
    } finally {
        app.close();
    }
}

test "one cinema's page never changes another's" {
    (app, nova) = _nova(["rival"]);
    try {
        _save(app, "compact", [_about("Nova.")]);
        _publish(app);
        open_cinema_for(app, "rival", "rift", "Rift Cinemas");
        assert _home(app, "rift")["page"] == {"template": "marquee", "sections": []};
        _save(app, "schedule", [_about("Rift.")], slug="rift");
        _publish(app, "rival", "rift");
        assert _section(app, "about")["fields"]["text"] == "Nova.";
        assert _home(app)["page"]["template"] == "compact";
    } finally {
        app.close();
    }
}
