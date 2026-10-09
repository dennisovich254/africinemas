"""P8.2: the MCP server's protocol and its movie card (core/mcp/server.jac).

Claude (or any MCP Apps host) talks JSON-RPC 2.0 to POST /mcp. These tests call the
server's `respond` directly, without HTTP or a cinema:

- the handshake: the client's protocol version is echoed when we speak it, else ours;
  tools and resources are offered; a notification gets nothing back;
- read-only tools only (no seats held, nothing ordered, nothing paid): whats_on and
  show_movie draw cards, and movie_poster is for the cards alone (8.3);
- a cinema's own connector (/c/{slug}/mcp, 8.3) has no cinema argument and no directory;
- the cards: MCP Apps' HTML type, a CSP that frames nothing (trailers open through the
  host), and HTML that loads nothing from outside and never writes data as HTML;
- JSON-RPC's errors: a bad version, an unknown method, tool or resource.
"""

import from os { path }
import from core.mcp.server {
    respond,
    PROTOCOLS,
    CARD_URI,
    PROGRAMME_URI,
    CARD_MIME,
    card_html,
    programme_html
}

glob ROOT: str = path.dirname(path.dirname(path.dirname(path.abspath(__file__))));

def _ask(method: str, params: any = None, id: any = 1) -> dict[str, any] {  # jac:ignore[W1037]
    return respond("2.0", method, id, params if params is not None else {});
}

def _error(answer: dict[str, any]) -> int {  # jac:ignore[W1037]
    return answer["error"]["code"] if "error" in answer else 0;
}

test "initialize echoes a protocol version we speak and offers tools and resources" {
    got = _ask("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}});
    assert got["jsonrpc"] == "2.0" and got["id"] == 1;
    result = got["result"];
    assert result["protocolVersion"] == "2025-06-18";
    assert "tools" in result["capabilities"] and "resources" in result["capabilities"];
    assert result["serverInfo"]["name"] == "africinemas";
    # A version we don't know gets our newest.
    newer = _ask("initialize", {"protocolVersion": "2099-01-01"})["result"];
    assert newer["protocolVersion"] == PROTOCOLS[0];
    # The id comes back as sent, string or number.
    assert _ask("ping", {}, "abc") == {"jsonrpc": "2.0", "id": "abc", "result": {}};
}

test "a notification gets nothing back" {
    # Omitted id and params reach the endpoint as the string "None".
    assert respond("2.0", "notifications/initialized", "None", "None") == {};
    assert respond("2.0", "notifications/cancelled", "None", {"requestId": 3}) == {};
}

test "read-only tools: whats_on and show_movie draw cards, movie_poster is the cards' own" {
    tools = _ask("tools/list")["result"]["tools"];
    assert [t["name"] for t in tools]
        == ["find_cinemas", "whats_on", "show_movie", "movie_poster"];
    for t in tools {
        assert t["inputSchema"]["type"] == "object" , t["name"];
        assert t["annotations"]["readOnlyHint"] == True , t["name"];
        assert t["description"] , t["name"];
    }
    named = {t["name"]: t for t in tools};
    assert named["show_movie"]["_meta"]["ui"]["resourceUri"] == CARD_URI;
    assert named["whats_on"]["_meta"]["ui"]["resourceUri"] == PROGRAMME_URI;
    assert sorted(named["show_movie"]["inputSchema"]["required"])
        == ["cinema", "movie"];
    assert "_meta" not in named["find_cinemas"];
    # Only the cards call movie_poster: the model never sees it, nor any image.
    assert named["movie_poster"]["_meta"]["ui"]["visibility"] == ["app"];
}

test "a cinema's own connector has no cinema argument and no directory" {
    tools = respond("2.0", "tools/list", 1, {}, "nova", "Nova Cinemas")["result"][
        "tools"
    ];
    assert [t["name"] for t in tools] == ["whats_on", "show_movie", "movie_poster"];
    for t in tools {
        assert "cinema" not in t["inputSchema"]["properties"] , t["name"];
        assert "cinema" not in t["inputSchema"].get("required", []) , t["name"];
    }
    hello = respond("2.0", "initialize", 1, {}, "nova", "Nova Cinemas")["result"];
    assert hello["serverInfo"]["title"] == "Nova Cinemas";
    assert "Nova Cinemas" in hello["instructions"];
    refused = respond(
        "2.0",
        "tools/call",
        2,
        {"name": "find_cinemas", "arguments": {}},
        "nova",
        "Nova Cinemas"
    );
    assert _error(refused) == -32602;
    # The platform's tool list is untouched by a cinema's.
    assert "find_cinemas" in [t["name"] for t in _ask("tools/list")["result"]["tools"]];
}

test "both cards are MCP Apps HTML that frame nothing and load nothing outside" {
    listed = _ask("resources/list")["result"]["resources"];
    assert [(r["uri"], r["mimeType"]) for r in listed]
        == [(CARD_URI, CARD_MIME), (PROGRAMME_URI, CARD_MIME)];
    assert CARD_MIME == "text/html;profile=mcp-app";
    for (uri, html) in [(CARD_URI, card_html()), (PROGRAMME_URI, programme_html())] {
        read = _ask("resources/read", {"uri": uri})["result"]["contents"];
        assert len(read) == 1 and read[0]["uri"] == uri;
        assert read[0]["mimeType"] == CARD_MIME and read[0]["text"] == html;
        csp = read[0]["_meta"]["ui"]["csp"];
        # No frames at all: claude.ai ignores frameDomains (P8.3), so trailers open
        # through the host instead of playing in an embedded player.
        assert csp.get("frameDomains", []) == [];
        assert csp.get("connectDomains", []) == []
            and csp.get("resourceDomains", []) == [];
    }
    assert _error(_ask("resources/read", {"uri": "ui://africinemas/other"})) == -32602;
}

test "the cards speak the MCP Apps handshake and load nothing from outside" {
    for html in [card_html(), programme_html()] {
        for message in [
            "ui/initialize",
            "ui/notifications/initialized",
            "ui/notifications/tool-result",
            "ui/notifications/size-changed",
            "ui/resource-teardown",
            "2026-01-26"
        ] {
            assert message in html , message;
        }
        lowered = html.lower();
        for outside in ["<script src", "<link", "@import", "http://", "url("] {
            assert outside not in lowered , outside;
        }
        # The cinema's text is set as text, never parsed as HTML.
        assert "innerhtml" not in lowered and "insertadjacenthtml" not in lowered;
        assert "document.write" not in lowered;
        # Brand colours are used only when they're plain hex colours.
        assert "#[0-9a-fa-f]{6}" in lowered;
    }
    # The movie card: the trailer opens through the host; no card embeds a player.
    movie = card_html();
    assert "ui/open-link" in movie and "Watch trailer" in movie;
    for html in [card_html(), programme_html()] {
        assert "iframe" not in html.lower();
    }
    # The programme card: lazy posters through the cards' own tool, and a tap on a
    # movie asks the chat to show it.
    programme = programme_html();
    assert "movie_poster" in programme and "tools/call" in programme;
    assert "ui/message" in programme;
}

test "JSON-RPC errors: a bad version, an unknown method, tool or arguments" {
    assert _error(respond("1.0", "tools/list", 1, {})) == -32600;
    unknown = _ask("tools/delete", {}, 9);
    assert _error(unknown) == -32601 and unknown["id"] == 9;
    assert _error(_ask("tools/call", {"name": "hold_chosen_seats", "arguments": {}}))
        == -32602;
    assert _error(_ask("tools/call", {"name": "show_movie", "arguments": "x"}))
        == -32602;
    assert _error(_ask("tools/call", {"name": "show_movie", "arguments": {}}))
        == -32602;
    # Params that aren't an object are treated as none.
    assert _ask("tools/list", "None")["result"]["tools"];
}
