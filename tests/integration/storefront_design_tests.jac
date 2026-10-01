"""P4.1c-a: what the storefront's home design needs from the server.

- A movie may have a landscape backdrop for the storefront's hero: checked and
  re-encoded like a poster (upload_backdrop, remove_backdrop), and public
  (public_backdrop) only while the movie is on sale or coming soon, like its poster.
- The home page's showtimes-by-day section lists the next 7 days in the cinema's time
  zone that have published, not-started showtimes, each with that day's showtimes and
  what the storefront needs to group them by movie.
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
     # What a day's showtime carries for the storefront to group it by movie.
     DAY_SHOWTIME_KEYS: list[str] = [
         "has_poster",
         "movie_key",
         "screen",
         "screening_id",
         "starts_at",
         "title",
         "venue"
     ];

def _nova -> tuple[Served, Cinema] {  # jac:ignore[W1037]
    app = served(MAIN, ["owner"]);
    nova = open_cinema_for(app, "owner", "nova", "Nova Cinemas");
    for title in ["Rafiki", "Supa Modo", "Kati Kati"] {
        add_movie(app, "owner", nova, title);
    }
    return (app, nova);
}

def _png(width: int, height: int) -> str {
    out = io.BytesIO();
    Image.new("RGB", (width, height), "#1D3557").save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _upload(app: Served, nova: Cinema, title: str, data: str) -> any {  # jac:ignore[W1037]
    return app.call(
        "owner",
        "upload_backdrop",
        {
            "tenant": "nova",
            "movie_id": nova.movies[title],
            "content_type": "image/png",
            "data_base64": data
        }
    );
}

def _home(app: Served) -> any {  # jac:ignore[W1037]
    return browse(app, "public_home", {"slug": "nova"});
}

def _section(app: Served, kind: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    found = [
        s
        for s in _home(app)["page"]["sections"]
        if s["type"] == kind
    ];
    return found[0] if found else None;
}

test "a backdrop is checked, shown while its movie is on sale, and can be removed" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    (app, nova) = _nova();
    try {
        assert code_of(_upload(app, nova, "Rafiki", _png(300, 200))) == "too_small";
        uploaded = _upload(app, nova, "Rafiki", _png(1600, 900));
        assert uploaded["ok"] and uploaded["movie"]["has_backdrop"] , uploaded;
        key_body = {"slug": "nova", "movie_key": "x"};
        # Not on the storefront yet: no public key, nothing public.
        assert code_of(browse(app, "public_backdrop", key_body)) == "not_found";
        add_screening(app, "owner", nova, "Rafiki", 0);
        movie = _home(app)["movies"][0];
        assert movie["has_backdrop"] is True , movie;
        key_body["movie_key"] = movie["movie_key"];
        shown = browse(app, "public_backdrop", key_body);
        assert shown["ok"]
            and shown["backdrop"].startswith("data:image/webp;base64,") , shown;
        removed = app.call(
            "owner",
            "remove_backdrop",
            {"tenant": "nova", "movie_id": nova.movies["Rafiki"]}
        );
        assert removed["ok"] and not removed["movie"]["has_backdrop"] , removed;
        assert _home(app)["movies"][0]["has_backdrop"] is False;
        assert code_of(browse(app, "public_backdrop", key_body)) == "no_backdrop";
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}

test "showtimes by day lists each of the next days that has showtimes, in order" {
    (app, nova) = _nova();
    try {
        first = add_screening(app, "owner", nova, "Rafiki", 0);
        later_same_day = add_screening(app, "owner", nova, "Supa Modo", 2);  # 23:00 there
        next_day = add_screening(app, "owner", nova, "Rafiki", 24);
        add_screening(app, "owner", nova, "Kati Kati", 27, state="scheduled");
        app.call(
            "owner",
            "save_home_page",
            {
                "tenant": "nova",
                "page": {
                    "template": "schedule",
                    "sections": [{"type": "today", "visible": True, "fields": {}}]
                }
            }
        );
        app.call("owner", "publish_home_page", {"tenant": "nova"});
        section = _section(app, "today");
        assert section is not None;
        days = section["days"];
        assert [len(d["showtimes"]) for d in days] == [2, 1] , days;
        assert [s["screening_id"] for s in days[0]["showtimes"]]
            == [first, later_same_day];
        assert days[1]["showtimes"][0]["screening_id"] == next_day;
        # Dates are the cinema's calendar days (Africa/Nairobi, UTC+3).
        assert days[0]["date"] == START.date().isoformat() , days[0]["date"];
        one = days[0]["showtimes"][0];
        assert sorted(one.keys()) == DAY_SHOWTIME_KEYS , sorted(one.keys());
        assert one["title"] == "Rafiki" and one["has_poster"] is False;
    } finally {
        app.close();
    }
}

test "showtimes more than a week ahead wait for their week" {
    (app, nova) = _nova();
    try {
        add_screening(app, "owner", nova, "Rafiki", 0);
        add_screening(app, "owner", nova, "Supa Modo", 24 * 8);
        app.call(
            "owner",
            "save_home_page",
            {
                "tenant": "nova",
                "page": {
                    "template": "schedule",
                    "sections": [{"type": "today", "visible": True, "fields": {}}]
                }
            }
        );
        app.call("owner", "publish_home_page", {"tenant": "nova"});
        section = _section(app, "today");
        assert section is not None;
        assert [s["title"] for d in section["days"] for s in d["showtimes"]]
            == ["Rafiki"];
    } finally {
        app.close();
    }
}
