"""P4.1: the public storefront reads, through the production app (main.jac).

A visitor needs no login. public_home(slug) lists the movies on sale, each once, with its
next showtimes; public_movie(slug, movie_key) shows one movie and its showtimes;
public_screening(slug, screening_id) one showtime and its seat map; public_poster(slug,
movie_key) a movie's poster. Only published screenings that haven't started are shown,
a movie is public only while it has one, and a cinema's address never shows another
cinema's movies, screenings or posters. Movies are named by an opaque movie_key, never
by their internal id. Dropping showtimes once they start is unit-tested
(tests/unit/storefront_tests.jac).
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
    START,
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
     MEDIA_ENV: str = "AFRICINEMAS_MEDIA_DIR",
     # What the home page shows about a movie, and about each of its next showtimes.
     MOVIE_KEYS: list[str] = [
         "age_rating",
         "genres",
         "has_backdrop",
         "has_poster",
         "language",
         "movie_key",
         "next",
         "release_date",
         "runtime_minutes",
         "synopsis",
         "title",
         "venues"
     ],
     # Showtimes are shown in the cinema's time zone, from its price list (P3.6).
     NOVA_CINEMA: dict[str, str] = {
         "name": "Nova Cinemas",
         "slug": "nova",
         "timezone": "Africa/Nairobi"
     },
     SHOWTIME_KEYS: list[str] = ["screen", "screening_id", "starts_at", "venue"];

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

def _key(app: Served, title: str, slug: str = "nova") -> str {
    # The public key of a movie on the home page.
    return [
        m
        for m in _home(app, slug)["movies"]
        if m["title"] == title
    ][0]["movie_key"];
}

def _png -> str {
    out = io.BytesIO();
    Image.new("RGB", (400, 600), "#E7B03A").save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

test "the home page lists each movie on sale once, earliest first, with its next showtimes" {
    (app, nova) = _nova();
    try {
        first = add_screening(app, "owner", nova, "Rafiki", 0);
        middle = add_screening(app, "owner", nova, "Supa Modo", 3);
        later = add_screening(app, "owner", nova, "Rafiki", 6);
        add_screening(app, "owner", nova, "Rafiki", 9, state="scheduled");
        add_screening(app, "owner", nova, "Kati Kati", 12, state="draft");
        home = _home(app);
        assert home["ok"] and home["cinema"] == NOVA_CINEMA , home;
        assert [m["title"] for m in home["movies"]] == ["Rafiki", "Supa Modo"] , home;
        rafiki = home["movies"][0];
        assert sorted(rafiki.keys()) == MOVIE_KEYS , sorted(rafiki.keys());
        assert [s["screening_id"] for s in rafiki["next"]] == [first, later];
        assert sorted(rafiki["next"][0].keys()) == SHOWTIME_KEYS;
        assert rafiki["next"][0]["venue"] == {"name": "Westgate", "city": "Nairobi"};
        assert rafiki["next"][0]["screen"] == {"name": "Screen 1"};
        assert rafiki["runtime_minutes"] == 90 and rafiki["has_poster"] is False;
        assert home["movies"][1]["next"][0]["screening_id"] == middle;
        assert home["venues"] == [{"name": "Westgate", "city": "Nairobi"}];
        # No internal ids or staff data anywhere in the public answer.
        tenant_id = app.call("owner", "my_access", {"tenant": "nova"})["tenant_id"];
        text = str(home);
        for secret in [tenant_id, nova.venue, nova.screen, app.actors["owner"].root_id]
            + list(nova.movies.values()) {
            assert secret not in text , f"leaked {secret}";
        }
    } finally {
        app.close();
    }
}

test "a movie page shows the movie and its published showtimes only" {
    (app, nova) = _nova();
    try {
        first = add_screening(app, "owner", nova, "Rafiki", 0);
        add_screening(app, "owner", nova, "Rafiki", 3, state="scheduled");
        later = add_screening(app, "owner", nova, "Rafiki", 6);
        key = _key(app, "Rafiki");
        page = browse(app, "public_movie", {"slug": "nova", "movie_key": key});
        assert page["ok"] , page;
        assert page["cinema"] == NOVA_CINEMA;
        assert page["movie"]["title"] == "Rafiki"
            and page["movie"]["synopsis"] == "About Rafiki."
            and page["movie"]["movie_key"] == key , page["movie"];
        assert [s["screening_id"] for s in page["screenings"]] == [first, later];
        assert nova.movies["Rafiki"] not in str(page);
        for wrong in ["", "no-such-movie", nova.movies["Rafiki"]] {
            assert code_of(
                browse(app, "public_movie", {"slug": "nova", "movie_key": wrong})
            )
                == "not_found" , wrong;
        }
    } finally {
        app.close();
    }
}

test "a movie's trailer shows on its page, with its embed link, once it's set" {
    (app, nova) = _nova();
    try {
        add_screening(app, "owner", nova, "Rafiki", 0);
        key = _key(app, "Rafiki");
        before = browse(app, "public_movie", {"slug": "nova", "movie_key": key});
        assert before["movie"]["trailer_url"] == "";
        assert app.call(
            "owner",
            "set_trailer",
            {
                "tenant": "nova",
                "movie_id": nova.movies["Rafiki"],
                "url": "https://youtu.be/dQw4w9WgXcQ"
            }
        )["ok"];
        page = browse(app, "public_movie", {"slug": "nova", "movie_key": key});
        assert page["movie"]["trailer_url"]
            == "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
        assert page["movie"]["trailer_embed"]
            == "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ";
    } finally {
        app.close();
    }
}

test "a movie leaves the storefront when its last showtime is unpublished" {
    (app, nova) = _nova();
    try {
        shown = add_screening(app, "owner", nova, "Supa Modo", 0);
        key = _key(app, "Supa Modo");
        app.call(
            "owner", "unpublish_screening", {"tenant": "nova", "screening_id": shown}
        );
        assert _home(app)["movies"] == [];
        assert code_of(browse(app, "public_movie", {"slug": "nova", "movie_key": key}))
            == "not_found";
    } finally {
        app.close();
    }
}

test "a screening page shows a published showtime and its seat map; others aren't found" {
    (app, nova) = _nova();
    try {
        shown = add_screening(app, "owner", nova, "Rafiki", 0);
        hidden = add_screening(app, "owner", nova, "Rafiki", 3, state="scheduled");
        page = browse(app, "public_screening", {"slug": "nova", "screening_id": shown});
        assert page["ok"] , page;
        screening = page["screening"];
        assert screening["screening_id"] == shown
            and screening["starts_at"] == START.isoformat() , screening;
        assert screening["movie"]["title"] == "Rafiki"
            and screening["movie"]["movie_key"] == _key(app, "Rafiki");
        assert screening["venue"] == {"name": "Westgate", "city": "Nairobi"};
        assert [x["label"] for x in screening["seat_map"]["seats"]]
            == ["A1", "A2", "A3", "A4", "A5"];
        for wrong in ["", "no-such-screening", hidden] {
            assert code_of(
                browse(app, "public_screening", {"slug": "nova", "screening_id": wrong})
            )
                == "not_found" , wrong;
        }
    } finally {
        app.close();
    }
}

test "a cinema's address never shows another cinema's movies, showtimes or posters" {
    (app, nova) = _nova(["rival"]);
    try {
        add_screening(app, "owner", nova, "Rafiki", 0);
        rift = open_cinema_for(app, "rival", "rift", "Rift Cinemas");
        add_movie(app, "rival", rift, "Rift Feature");
        theirs = add_screening(app, "rival", rift, "Rift Feature", 0);
        their_key = _key(app, "Rift Feature", "rift");
        assert [m["title"] for m in _home(app)["movies"]] == ["Rafiki"];
        assert [m["title"] for m in _home(app, "rift")["movies"]] == ["Rift Feature"];
        for (name, body) in [
            ("public_movie", {"slug": "nova", "movie_key": their_key}),
            ("public_poster", {"slug": "nova", "movie_key": their_key}),
            ("public_screening", {"slug": "nova", "screening_id": theirs})
        ] {
            assert code_of(browse(app, name, body)) == "not_found" , name;
        }
        for (name, body) in [
            ("public_home", {"slug": "no-such-cinema"}),
            ("public_movie", {"slug": "no-such-cinema", "movie_key": their_key}),
            ("public_poster", {"slug": "no-such-cinema", "movie_key": their_key}),
            ("public_screening", {"slug": "no-such-cinema", "screening_id": theirs})
        ] {
            assert code_of(browse(app, name, body)) == "not_found" , name;
        }
    } finally {
        app.close();
    }
}

test "a poster is public while its movie is on sale, and follows new uploads" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    (app, nova) = _nova();
    try {
        uploaded = app.call(
            "owner",
            "upload_poster",
            {
                "tenant": "nova",
                "movie_id": nova.movies["Rafiki"],
                "content_type": "image/png",
                "data_base64": _png()
            }
        );
        assert uploaded["ok"] , uploaded;
        add_screening(app, "owner", nova, "Rafiki", 0);
        add_screening(app, "owner", nova, "Supa Modo", 3);
        movies = _home(app)["movies"];
        assert [m["has_poster"] for m in movies] == [True, False] , movies;
        poster = browse(
            app, "public_poster", {"slug": "nova", "movie_key": movies[0]["movie_key"]}
        );
        assert poster["ok"]
            and poster["poster"].startswith("data:image/webp;base64,") , poster;
        assert code_of(
            browse(
                app,
                "public_poster",
                {"slug": "nova", "movie_key": movies[1]["movie_key"]}
            )
        )
            == "no_poster";
        # A poster added after publishing reaches the storefront too.
        app.call(
            "owner",
            "upload_poster",
            {
                "tenant": "nova",
                "movie_id": nova.movies["Supa Modo"],
                "content_type": "image/png",
                "data_base64": _png()
            }
        );
        assert [m["has_poster"] for m in _home(app)["movies"]] == [True, True];
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}

test "showtimes come with the cinema's own time zone, from its price list" {
    (app, nova) = _nova();
    try {
        add_screening(app, "owner", nova, "Rafiki", 0);
        saved = app.call(
            "owner",
            "save_price_list",
            {
                "tenant": "nova",
                "timezone": "Africa/Lagos",
                "ticket_types": [{"code": "ADULT", "name": "Adult"}],
                "prices": [],
                "surcharges": [],
                "service_fee_cents": 0
            }
        );
        assert saved["ok"] , saved;
        assert _home(app)["cinema"]["timezone"] == "Africa/Lagos";
    } finally {
        app.close();
    }
}
