"""P8.4: the storefront chat (cinema_chat), against a real cinema with a scripted model.

In-process app (tests/apps/payment_app.jac), MockLLM (no key, no network). Nova shows
Rafiki, with a YouTube trailer; Rift shows Kesho.

- The reply comes with cards built from what the tools returned this turn: the
  programme and a movie card. A reply that names a showtime no tool returned shows no
  card, and the cards carry nothing private.
- A cinema's chat answers about that cinema only: any other cinema the model names is
  replaced, it isn't offered the directory or (until 8.5) the booking tools, and the
  model is told which cinema it serves.
- Limits: a long conversation and a busy cinema get a polite pointer to the website
  instead of a model call.
- Unknown cinemas and bad holder ids are refused before the model is asked anything.
"""

import os;
import json;
import from tests.support.served { Served }
import from tests.support.storefront_setup {
    browse,
    code_of,
    open_cinema_for,
    add_movie,
    add_screening,
    set_prices
}
import from tests.support.payment_setup { paying_cinema }

glob HOLDER: str = "holder-chat-0123456789abcdef",
     PER_MINUTE_ENV: str = "AFRICINEMAS_CHAT_PER_MINUTE",
     HIDDEN: list[str] = [
         '"email"',
         '"phone"',
         '"qr"',
         '"holder"',
         '"token"',
         "tenant_id"
     ];

def _chat(
    app: Served,
    message: str,
    history: list[any] | None = None,  # jac:ignore[W1037]
    slug: str = "nova"
) -> any {  # jac:ignore[W1037]
    return browse(
        app,
        "cinema_chat",
        {"slug": slug, "message": message, "history": history or [], "holder": HOLDER}
    );
}

def _mock(app: Served, steps: list[any]) {  # jac:ignore[W1037]
    assert app.call("owner", "agent_mock", {"steps": steps});
}

def _rafiki_key(app: Served) -> str {
    on = app.call(
        "owner",
        "agent_tool",
        {"name": "whats_on", "args": {"cinema": "nova", "day": ""}, "holder": HOLDER}
    );
    return on["showtimes"][0]["movie_key"];
}

test "the chat answers with cards built from what the tools returned" {
    (app, nova, screening) = paying_cinema([]);
    try {
        assert app.call(
            "owner",
            "set_trailer",
            {
                "tenant": "nova",
                "movie_id": nova.movies["Rafiki"],
                "url": "https://youtu.be/dQw4w9WgXcQ"
            }
        )["ok"];
        key = _rafiki_key(app);
        _mock(
            app,
            [
                {"tool": "whats_on", "args": {"cinema": "nova", "day": ""}},
                {"tool": "movie_details", "args": {"cinema": "nova", "movie_key": key}},
                "Rafiki is on tonight."
            ]
        );
        got = _chat(app, "What's on tonight?");
        assert got["ok"] and got["reply"] == "Rafiki is on tonight." , got;
        assert [c["type"] for c in got["cards"]] == ["programme", "movie"] , got;
        (programme, movie) = got["cards"];
        assert programme["cinema"] == "Nova Cinemas";
        assert [m["title"] for m in programme["movies"]] == ["Rafiki"];
        assert [s["showtime_id"] for s in programme["days"][0]["showtimes"]]
            == [screening];
        assert movie["title"] == "Rafiki" and movie["movie_key"] == key;
        assert [s["showtime_id"] for s in movie["showtimes"]] == [screening];
        assert movie["trailer_embed"]
            == "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ";
        for hidden in HIDDEN {
            assert hidden not in json.dumps(got["cards"]) , hidden;
        }
        # A reply that names a showtime no tool returned shows no card.
        _mock(app, ["Rafiki is on at 21:00 and 23:30."]);
        made_up = _chat(app, "When is Rafiki on?");
        assert made_up["reply"] == "Rafiki is on at 21:00 and 23:30.";
        assert made_up["cards"] == [];
    } finally {
        app.close();
    }
}

test "a cinema's chat answers about that cinema only" {
    (app, _, _) = paying_cinema(["kim"]);
    try {
        rift = open_cinema_for(app, "kim", "rift", "Rift Cinemas");
        add_movie(app, "kim", rift, "Kesho");
        set_prices(app, "kim", rift);
        add_screening(app, "kim", rift, "Kesho", 0);
        # The model asks about Rift; Nova's chat answers about Nova.
        _mock(
            app,
            [
                {"tool": "whats_on", "args": {"cinema": "rift", "day": ""}},
                "Here you go."
            ]
        );
        got = _chat(app, "What's on at Rift?");
        titles = [m["title"] for m in got["cards"][0]["movies"]];
        assert titles == ["Rafiki"] , got;
        # It serves Nova, and it has neither the directory nor (until 8.5) booking tools.
        assert "Nova Cinemas" in app.call("owner", "agent_sent")["messages"];
        # byLLM adds its own finish_tool to every call.
        offered = sorted(
            [
                t
                for t in app.call("owner", "agent_offered")
                if t != "finish_tool"
            ]
        );
        assert offered
            == [
                "movie_details",
                "my_bookings",
                "seat_map",
                "ticket_types",
                "whats_on"
            ] , offered;
        # A tool it wasn't given gets the fallback, not an answer.
        _mock(app, [{"tool": "find_cinemas", "args": {"city": ""}}]);
        assert "can't answer right now" in _chat(app, "Any other cinemas?")["reply"];
        # Rift's own chat answers about Rift.
        _mock(
            app,
            [
                {"tool": "whats_on", "args": {"cinema": "nova", "day": ""}},
                "Here you go."
            ]
        );
        theirs = _chat(app, "What's on?", None, "rift");
        assert [m["title"] for m in theirs["cards"][0]["movies"]] == ["Kesho"];
    } finally {
        app.close();
    }
}

test "a long conversation or a busy cinema gets a pointer to the website, not a model call" {
    (app, _, _) = paying_cinema([]);
    try {
        long_talk = [
            {"role": "user" if i % 2 == 0 else "assistant", "content": f"turn {i}"}
            for i in range(40)
        ];
        _mock(app, ["This should not be sent."]);
        got = _chat(app, "And now?", long_talk);
        assert got["ok"] and "website" in got["reply"] , got;
        assert got["reply"] != "This should not be sent." and got["cards"] == [];
    } finally {
        app.close();
    }
    os.environ[PER_MINUTE_ENV] = "2";
    (app, _, _) = paying_cinema([]);
    try {
        for i in range(2) {
            _mock(app, ["Hello."]);
            assert _chat(app, f"Hi {i}")["reply"] == "Hello.";
        }
        _mock(app, ["Hello."]);
        busy = _chat(app, "Hi again");
        assert "website" in busy["reply"] and busy["reply"] != "Hello." , busy;
    } finally {
        os.environ.pop(PER_MINUTE_ENV, None);
        app.close();
    }
}

test "an unknown cinema or a bad holder id is refused before the model is asked" {
    (app, _, _) = paying_cinema([]);
    try {
        _mock(app, ["Should not answer."]);
        assert code_of(_chat(app, "Hi", None, "no-such-cinema")) == "not_found";
        bad = browse(
            app,
            "cinema_chat",
            {"slug": "nova", "message": "Hi", "history": [], "holder": "x"}
        );
        assert code_of(bad) == "invalid_holder";
    } finally {
        app.close();
    }
}
