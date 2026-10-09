"""P8.2: the MCP server over HTTP (POST /mcp), against a real cinema.

In-process app (tests/apps/payment_app.jac): Nova shows Rafiki, with a poster and a
YouTube trailer. Nobody signs in: an MCP client browses as the storefront does.

- A client's handshake and a notification go through the real route.
- show_movie finds a movie by title or key and answers the card (title, showtimes, the
  trailer's player, the storefront's movie page, the poster in _meta for the card only)
  and the model (text), with no private value anywhere.
- What the storefront doesn't show, the tools don't either: an unknown cinema or movie
  is a tool error the model can read, not a JSON-RPC failure.
- 8.3: a showtime that has started is no longer on sale in the chat; a cinema's own
  connector (/c/{slug}/mcp) answers about that cinema only, whatever its arguments say,
  and as the platform's does; whats_on draws the programme card, whose posters come
  one at a time from movie_poster.
"""

import io;
import os;
import json;
import base64;
import shutil;
import tempfile;
import from PIL { Image }
import from tests.support.served { Served }
import from tests.support.payment_setup { paying_cinema }
import from tests.support.storefront_setup {
    open_cinema_for,
    add_movie,
    add_screening,
    set_prices
}

glob MEDIA_ENV: str = "AFRICINEMAS_MEDIA_DIR",
     CLOCK_ENV: str = "AFRICINEMAS_CLOCK_CONTROL",
     NOVA_MCP: str = "/c/nova/mcp",
     HIDDEN: list[str] = [
         '"email"',
         '"phone"',
         '"qr"',
         '"holder"',
         '"token"',
         "tenant_id"
     ];

def _rpc(
    app: Served,
    method: str,
    params: dict[str, any] | None = None,  # jac:ignore[W1037]
    id: any = 1,  # jac:ignore[W1037]
    path: str = "/mcp"
) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token("");
    body: dict[str, any] = {"jsonrpc": "2.0", "method": method};  # jac:ignore[W1037]
    if id is not None {
        body["id"] = id;
    }
    if params is not None {
        body["params"] = params;
    }
    resp = app.client.post(path, json=body);
    assert resp.status_code == 200 , f"{method}: {resp.status_code} {resp.text[:300]}";
    return json.loads(resp.text);
}

def _call(
    app: Served,
    tool: str,
    args: dict[str, any],  # jac:ignore[W1037]
    path: str = "/mcp"
) -> dict[str, any] {  # jac:ignore[W1037]
    got = _rpc(app, "tools/call", {"name": tool, "arguments": args}, 1, path);
    assert "result" in got , got;
    return got["result"];
}

def _poster_and_trailer(app: Served, movie_id: str) {
    out = io.BytesIO();
    Image.new("RGB", (400, 600), "#E7B03A").save(out, format="PNG");
    assert app.call(
        "owner",
        "upload_poster",
        {
            "tenant": "nova",
            "movie_id": movie_id,
            "content_type": "image/png",
            "data_base64": base64.b64encode(out.getvalue()).decode()
        }
    )["ok"];
    assert app.call(
        "owner",
        "set_trailer",
        {"tenant": "nova", "movie_id": movie_id, "url": "https://youtu.be/dQw4w9WgXcQ"}
    )["ok"];
}

test "a client's handshake and notification go through the real route" {
    (app, _, _) = paying_cinema([]);
    try {
        hello = _rpc(
            app, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}}
        );
        assert hello["result"]["protocolVersion"] == "2025-06-18" , hello;
        assert _rpc(app, "notifications/initialized", None, None) == {};
        names = [t["name"] for t in _rpc(app, "tools/list")["result"]["tools"]];
        assert "show_movie" in names;
        card = _rpc(app, "resources/read", {"uri": "ui://africinemas/movie-card"});
        assert "ui/initialize" in card["result"]["contents"][0]["text"];
    } finally {
        app.close();
    }
}

test "show_movie answers the card and the model, with nothing private" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    (app, nova, screening) = paying_cinema([]);
    try {
        _poster_and_trailer(app, nova.movies["Rafiki"]);
        on = json.loads(
            _call(app, "whats_on", {"cinema": "nova", "day": ""})["content"][0]["text"]
        );
        key = on["showtimes"][0]["movie_key"];
        for asked in ["rafiki", key] {
            got = _call(app, "show_movie", {"cinema": "nova", "movie": asked});
            assert got.get("isError", False) == False , got;
            card = got["structuredContent"];
            assert card["title"] == "Rafiki"
                and card["cinema"] == "Nova Cinemas" , card;
            assert [s["showtime_id"] for s in card["showtimes"]] == [screening];
            assert card["trailer_embed"]
                == "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ";
            assert card["book_url"].endswith(f"/c/nova/m/{key}") , card["book_url"];
            # The poster is for the card only: in _meta, not in what the model reads.
            assert got["_meta"]["africinemas/poster"].startswith(
                "data:image/webp;base64,"
            );
            assert "base64" not in json.dumps(card);
            text = got["content"][0]["text"];
            assert got["content"][0]["type"] == "text" and "Rafiki" in text;
            assert "base64" not in text;
            for hidden in HIDDEN {
                assert hidden not in json.dumps(got) , hidden;
            }
        }
        # The poster's file is gone (another media folder): still a card, no poster.
        shutil.rmtree(media, ignore_errors=True);
        got = _call(app, "show_movie", {"cinema": "nova", "movie": "Rafiki"});
        assert got.get("isError", False) == False and "_meta" not in got , got;
        assert got["structuredContent"]["title"] == "Rafiki";
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}

test "an unknown cinema or movie is a tool error the model can read" {
    (app, _, _) = paying_cinema([]);
    try {
        for args in [
            {"cinema": "nova", "movie": "Not A Real Film"},
            {"cinema": "no-such-cinema", "movie": "Rafiki"}
        ] {
            got = _call(app, "show_movie", args);
            assert got["isError"] == True and got["content"][0]["text"] , got;
            assert "structuredContent" not in got;
        }
        # The text tools answer as the agent's do.
        found = _call(app, "find_cinemas", {"city": ""});
        assert "nova" in found["content"][0]["text"] , found;
        # A customer names the cinema: Claude searches by that name.
        named = json.loads(
            _call(app, "find_cinemas", {"name": "Nova"})["content"][0]["text"]
        );
        assert [c["slug"] for c in named["cinemas"]] == ["nova"] , named;
        assert json.loads(
            _call(app, "find_cinemas", {"name": "Westgate"})["content"][0]["text"]
        )["cinemas"]
            == [];
        on = _call(app, "whats_on", {"cinema": "nova", "day": ""});
        assert "Rafiki" in on["content"][0]["text"] , on;
    } finally {
        app.close();
    }
}

def _text_of(result: dict[str, any]) -> str {  # jac:ignore[W1037]
    return result["content"][0]["text"];
}

test "a showtime that has started is no longer on sale in the chat" {
    os.environ[CLOCK_ENV] = "1";
    (app, _, screening) = paying_cinema([]);
    try {
        app.call(
            "owner",
            "rd_freeze",
            {"slug": "nova", "screening_id": screening, "minutes": 5}
        );
        on = json.loads(_text_of(_call(app, "whats_on", {"cinema": "nova"})));
        assert on["showtimes"] == [] , on;
        assert _call(app, "show_movie", {"cinema": "nova", "movie": "Rafiki"})[
            "isError"
        ]
            == True;
        # A minute before it starts, it's on sale.
        app.call(
            "owner",
            "rd_freeze",
            {"slug": "nova", "screening_id": screening, "minutes": -1}
        );
        on = json.loads(_text_of(_call(app, "whats_on", {"cinema": "nova"})));
        assert [s["showtime_id"] for s in on["showtimes"]] == [screening];
    } finally {
        app.call("owner", "rd_unfreeze", {});
        os.environ.pop(CLOCK_ENV, None);
        app.close();
    }
}

test "a cinema's own connector answers about that cinema only, as the platform's does" {
    (app, _, _) = paying_cinema(["kim"]);
    try {
        rift = open_cinema_for(app, "kim", "rift", "Rift Cinemas");
        add_movie(app, "kim", rift, "Kesho");
        set_prices(app, "kim", rift);
        add_screening(app, "kim", rift, "Kesho", 0);
        hello = _rpc(app, "initialize", {"protocolVersion": "2025-06-18"}, 1, NOVA_MCP);
        assert hello["result"]["serverInfo"]["title"] == "Nova Cinemas" , hello;
        # Asked about Rift, Nova's connector still answers about Nova.
        for args in [{"cinema": "rift"}, {}] {
            text = _text_of(_call(app, "whats_on", args, NOVA_MCP));
            assert "Rafiki" in text and "Kesho" not in text , text;
        }
        kesho = _call(
            app, "show_movie", {"cinema": "rift", "movie": "Kesho"}, NOVA_MCP
        );
        assert kesho["isError"] == True , kesho;
        # The same card as the platform connector's, for the same cinema.
        scoped = _call(app, "show_movie", {"movie": "Rafiki"}, NOVA_MCP);
        platform = _call(app, "show_movie", {"cinema": "nova", "movie": "Rafiki"});
        assert scoped["structuredContent"] == platform["structuredContent"];
        # No directory on a cinema's connector.
        assert "error"
            in _rpc(
                app,
                "tools/call",
                {"name": "find_cinemas", "arguments": {}},
                1,
                NOVA_MCP
            );
        # An unknown cinema's connector answers nothing.
        assert _rpc(app, "initialize", {}, 1, "/c/no-such-cinema/mcp")["error"]["code"]
            == -32602;
    } finally {
        app.close();
    }
}

test "whats_on draws the programme card, and posters come from movie_poster" {
    media = tempfile.mkdtemp(prefix="africinemas-media-");
    os.environ[MEDIA_ENV] = media;
    (app, nova, screening) = paying_cinema([]);
    try {
        _poster_and_trailer(app, nova.movies["Rafiki"]);
        got = _call(app, "whats_on", {"cinema": "nova"});
        card = got["structuredContent"];
        assert card["cinema"] == "Nova Cinemas" , card;
        assert [m["title"] for m in card["movies"]] == ["Rafiki"];
        day = card["days"][0];
        assert [s["showtime_id"] for s in day["showtimes"]] == [screening];
        # The cinema's colours, as plain hex for light and dark.
        for mode in ["light", "dark"] {
            for role in ["accent", "on_accent"] {
                colour = card["brand"][mode][role];
                assert len(colour) == 7 and colour.startswith("#") , colour;
            }
        }
        # The model still reads the showtimes as text; the card gets no images.
        assert "Rafiki" in _text_of(got) and "base64" not in json.dumps(got);
        key = card["movies"][0]["movie_key"];
        poster = _call(app, "movie_poster", {"cinema": "nova", "movie_key": key});
        assert poster["_meta"]["africinemas/poster"].startswith("data:image/webp");
        assert "base64" not in _text_of(poster);
        assert _call(app, "movie_poster", {"cinema": "nova", "movie_key": "made-up"})[
            "isError"
        ]
            == True;
    } finally {
        os.environ.pop(MEDIA_ENV, None);
        app.close();
        shutil.rmtree(media, ignore_errors=True);
    }
}
