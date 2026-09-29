"""P3.4: movies and their posters, through the production app (main.jac).

Movies belong to the cinema (not to a venue). Reading needs movies.read, creating needs
movies.create, and changing or deleting a movie or its poster needs movies.update.
Posters are checked and re-encoded (core/catalog/poster.jac), stored under
tenant/{tenant_id}/media/{uuid}.webp, and read back through get_poster; the storage key
never comes from the client. Another cinema's movie ids answer not_found.
"""

import io;
import os;
import base64;
import shutil;
import tempfile;
import from os { path }
import from pathlib { Path }
import from PIL { Image }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     NOVA: str = "nova",
     MEDIA_ENV: str = "AFRICINEMAS_MEDIA_DIR";

def _cinema(names: list[str]) -> Served {
    app = served(MAIN, ["owner"] + names);
    app.call("owner", "create_cinema", {"name": "Nova Cinemas", "slug": NOVA});
    app.call("owner", "start_shift", {"tenant": NOVA});
    return app;
}

def _details(title: str = "Rafiki") -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "tenant": NOVA,
        "title": title,
        "synopsis": "Two young women in Nairobi fall in love.",
        "runtime_minutes": 83,
        "age_rating": "18",
        "genres": ["Drama", "Romance"],
        "language": "English, Swahili"
    };
}

def _movie(app: Served, title: str = "Rafiki", who: str = "owner") -> dict[str, any] {  # jac:ignore[W1037]
    answer = app.call(who, "create_movie", _details(title));
    assert answer["ok"] , answer;
    return answer["movie"];
}

def _png(size: tuple[int, int] = (400, 600)) -> str {
    out = io.BytesIO();
    Image.new("RGB", size, "#E7B03A").save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _upload(
    app: Served, movie_id: str, data: str, kind: str = "image/png", who: str = "owner"
) -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "upload_poster",
        {
            "tenant": NOVA,
            "movie_id": movie_id,
            "content_type": kind,
            "data_base64": data
        }
    );
}

def _code(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

def _stored(media: str) -> list[str] {
    # Every file in the media folder, as paths relative to it.
    return sorted(
        [
            str(p.relative_to(media))
            for p in Path(media).rglob("*")
            if p.is_file()
        ]
    );
}

test "an owner creates, lists, edits and deletes movies, and they persist" {
    app = _cinema([]);
    try {
        rafiki = _movie(app);
        assert rafiki
            == {
                "movie_id": rafiki["movie_id"],
                "title": "Rafiki",
                "synopsis": "Two young women in Nairobi fall in love.",
                "runtime_minutes": 83,
                "age_rating": "18",
                "genres": ["Drama", "Romance"],
                "language": "English, Swahili",
                "has_poster": False
            } , rafiki;
        _movie(app, "Atlantics");
        changed = _details("Rafiki");
        changed["movie_id"] = rafiki["movie_id"];
        changed["runtime_minutes"] = 85;
        changed["age_rating"] = "16";
        updated = app.call("owner", "update_movie", changed);
        assert updated["ok"] and updated["movie"]["runtime_minutes"] == 85 , updated;
        app.restart();
        listed = app.call("owner", "list_movies", {"tenant": NOVA})["movies"];
        assert [(m["title"], m["age_rating"]) for m in listed]
            == [("Atlantics", "18"), ("Rafiki", "16")] , listed;
        got = app.call(
            "owner", "get_movie", {"tenant": NOVA, "movie_id": rafiki["movie_id"]}
        );
        assert got["ok"] and got["movie"]["runtime_minutes"] == 85;
        assert app.call(
            "owner", "delete_movie", {"tenant": NOVA, "movie_id": rafiki["movie_id"]}
        )["ok"];
        assert [
            m["title"]
            for m in app.call("owner", "list_movies", {"tenant": NOVA})["movies"]
        ]
            == ["Atlantics"];
    } finally {
        app.close();
    }
}

test "movie details are checked, and nothing is saved on a refusal" {
    app = _cinema([]);
    try {
        cases = [
            ("title", "", "invalid_title"),
            ("title", "x" * 121, "invalid_title"),
            ("synopsis", "s" * 2001, "invalid_synopsis"),
            ("runtime_minutes", 0, "invalid_runtime"),
            ("runtime_minutes", 601, "invalid_runtime"),
            ("age_rating", "PG-13", "invalid_rating"),
            ("genres", ["a", "b", "c", "d", "e", "f"], "invalid_genres"),
            ("genres", ["g" * 31], "invalid_genres"),
            ("genres", [""], "invalid_genres"),
            ("language", "l" * 41, "invalid_language")
        ];
        for (field, value, code) in cases {
            body = _details();
            body[field] = value;
            answer = app.call("owner", "create_movie", body);
            assert _code(answer) == code , f"{field}={value!r}: {answer}";
        }
        assert app.call("owner", "list_movies", {"tenant": NOVA})["movies"] == [];
        for rating in ["GE", "PG", "16", "18", "R"] {
            body = _details(f"Rated {rating}");
            body["age_rating"] = rating;
            assert app.call("owner", "create_movie", body)["ok"] , rating;
        }
    } finally {
        app.close();
    }
}

test "a poster is checked, stored under the cinema's media folder, and read back as WebP" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    app = _cinema([]);
    try {
        tenant_id = app.call("owner", "my_access", {"tenant": NOVA})["tenant_id"];
        movie = _movie(app)["movie_id"];
        answer = _upload(app, movie, _png((1000, 1500)));
        assert answer["ok"] and answer["movie"]["has_poster"] , answer;
        files = _stored(media);
        assert len(files) == 1 , files;
        parts = files[0].split("/");
        assert parts[:3] == ["tenant", tenant_id, "media"]
            and parts[3].endswith(".webp") , files;
        assert len(parts[3]) == len("00000000-0000-0000-0000-000000000000.webp") , "a random uuid name";
        poster = app.call("owner", "get_poster", {"tenant": NOVA, "movie_id": movie});
        assert poster["ok"] and poster["content_type"] == "image/webp" , poster;
        img = Image.open(io.BytesIO(base64.b64decode(poster["data_base64"])));
        assert (img.format, img.size) == ("WEBP", (800, 1200));
        # Replacing the poster removes the old file; deleting the movie removes the new one.
        _upload(app, movie, _png());
        replaced = _stored(media);
        assert len(replaced) == 1 and replaced != files , replaced;
        app.call("owner", "delete_movie", {"tenant": NOVA, "movie_id": movie});
        assert _stored(media) == [];
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}

test "a bad poster is refused and the movie keeps its old one" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    app = _cinema([]);
    try {
        movie = _movie(app)["movie_id"];
        _upload(app, movie, _png());
        before = _stored(media);
        attempts = [
            (_png(), "image/gif", "wrong_type"),
            (base64.b64encode(b"%PDF-1.7").decode(), "image/png", "wrong_type"),
            ("not base64!!", "image/png", "invalid_image"),
            (_png((100, 150)), "image/png", "too_small"),
            (
                base64.b64encode(b"\x00" * (5 * 1024 * 1024 + 1)).decode(),
                "image/png",
                "too_large"
            )
        ];
        for (data, kind, code) in attempts {
            assert _code(_upload(app, movie, data, kind)) == code , code;
        }
        assert _stored(media) == before , "the old poster is untouched";
        assert app.call("owner", "get_poster", {"tenant": NOVA, "movie_id": movie})[
            "ok"
        ];
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}

test "a movie without a poster has none to read" {
    app = _cinema([]);
    try {
        movie = _movie(app)["movie_id"];
        answer = app.call("owner", "get_poster", {"tenant": NOVA, "movie_id": movie});
        assert _code(answer) == "no_poster" , answer;
    } finally {
        app.close();
    }
}

test "catalogue staff can read movies; content managers change them; ushers can't see them" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    app = _cinema(["cara", "bob", "uma"]);
    try {
        movie = _movie(app)["movie_id"];
        _upload(app, movie, _png());
        for (who, role) in [
            ("cara", "content_manager"),
            ("bob", "box_office_agent"),
            ("uma", "usher")
        ] {
            token = app.call(
                "owner", "invite_staff", {"tenant": NOVA, "role": role, "venue_id": ""}
            )["token"];
            app.call(who, "accept_invite", {"token": token});
            app.call(who, "start_shift", {"tenant": NOVA});
        }
        assert _movie(app, "Supa Modo", who="cara")["title"] == "Supa Modo";
        assert _upload(app, movie, _png(), who="cara")["ok"];
        assert app.call("bob", "list_movies", {"tenant": NOVA})["ok"];
        assert app.call("bob", "get_poster", {"tenant": NOVA, "movie_id": movie})["ok"];
        assert _code(app.call("bob", "create_movie", _details("X"))) == "forbidden";
        assert _code(_upload(app, movie, _png(), who="bob")) == "forbidden";
        assert _code(
            app.call("bob", "delete_movie", {"tenant": NOVA, "movie_id": movie})
        )
            == "forbidden";
        assert _code(app.call("uma", "list_movies", {"tenant": NOVA})) == "forbidden";
        assert _code(app.call("uma", "get_poster", {"tenant": NOVA, "movie_id": movie}))
            == "forbidden";
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}

test "another cinema's movies and posters are not found" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    app = _cinema(["rival"]);
    try {
        movie = _movie(app)["movie_id"];
        _upload(app, movie, _png());
        app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        app.call("rival", "start_shift", {"tenant": "rift"});
        body = _details("Mine");
        body["tenant"] = "rift";
        body["movie_id"] = movie;
        aimed = [
            ("get_movie", {"tenant": "rift", "movie_id": movie}),
            ("update_movie", body),
            ("delete_movie", {"tenant": "rift", "movie_id": movie}),
            ("get_poster", {"tenant": "rift", "movie_id": movie}),
            (
                "upload_poster",
                {
                    "tenant": "rift",
                    "movie_id": movie,
                    "content_type": "image/png",
                    "data_base64": _png()
                }
            ),
            ("get_movie", {"tenant": "rift", "movie_id": "not-an-id"})
        ];
        for (name, args) in aimed {
            assert _code(app.call("rival", name, args)) == "not_found" , name;
        }
        assert app.call("owner", "get_poster", {"tenant": NOVA, "movie_id": movie})[
            "ok"
        ] , "untouched";
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}

test "movie changes need an open shift" {
    app = _cinema([]);
    try {
        app.call("owner", "end_shift", {"tenant": NOVA});
        assert _code(app.call("owner", "create_movie", _details())) == "no_shift";
        assert _code(app.call("owner", "list_movies", {"tenant": NOVA})) == "no_shift";
    } finally {
        app.close();
    }
}
