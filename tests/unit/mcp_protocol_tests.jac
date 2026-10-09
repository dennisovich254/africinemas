"""P8.2: the MCP server's protocol and its movie card (core/mcp/server.jac).

Claude (or any MCP Apps host) talks JSON-RPC 2.0 to POST /mcp. These tests call the
server's `respond` directly, without HTTP or a cinema:

- the handshake: the client's protocol version is echoed when we speak it, else ours;
  tools and resources are offered; a notification gets nothing back;
- exactly three read-only tools (no seats held, nothing ordered, nothing paid), and only
  show_movie draws a card;
- the card resource: MCP Apps' HTML type, a CSP that lets only the two trailer players
  be framed, and HTML that loads nothing from outside and never writes data as HTML;
- JSON-RPC's errors: a bad version, an unknown method, tool or resource.
"""

import from os { path }
import from core.mcp.server { respond, PROTOCOLS, CARD_URI, CARD_MIME, card_html }

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

test "three read-only tools, and only show_movie draws the card" {
    tools = _ask("tools/list")["result"]["tools"];
    assert [t["name"] for t in tools] == ["find_cinemas", "whats_on", "show_movie"];
    for t in tools {
        assert t["inputSchema"]["type"] == "object" , t["name"];
        assert t["annotations"]["readOnlyHint"] == True , t["name"];
        assert t["description"] , t["name"];
    }
    card = [
        t
        for t in tools
        if t["name"] == "show_movie"
    ][0];
    assert card["_meta"]["ui"]["resourceUri"] == CARD_URI;
    assert sorted(card["inputSchema"]["required"]) == ["cinema", "movie"];
    for t in tools {
        assert t["name"] == "show_movie" or "_meta" not in t , t["name"];
    }
}

test "the card resource is MCP Apps HTML that may frame only the trailer players" {
    listed = _ask("resources/list")["result"]["resources"];
    assert [(r["uri"], r["mimeType"]) for r in listed] == [(CARD_URI, CARD_MIME)];
    assert CARD_MIME == "text/html;profile=mcp-app";
    read = _ask("resources/read", {"uri": CARD_URI})["result"]["contents"];
    assert len(read) == 1 and read[0]["uri"] == CARD_URI;
    assert read[0]["mimeType"] == CARD_MIME and read[0]["text"] == card_html();
    csp = read[0]["_meta"]["ui"]["csp"];
    assert sorted(csp["frameDomains"])
        == ["https://player.vimeo.com", "https://www.youtube-nocookie.com"];
    assert csp.get("connectDomains", []) == [] and csp.get("resourceDomains", []) == [];
    assert _error(_ask("resources/read", {"uri": "ui://africinemas/other"})) == -32602;
}

test "the card speaks the MCP Apps handshake and loads nothing from outside" {
    html = card_html();
    for message in [
        "ui/initialize",
        "ui/notifications/initialized",
        "ui/notifications/tool-result",
        "ui/notifications/size-changed",
        "ui/open-link",
        "ui/resource-teardown",
        "2026-01-26"
    ] {
        assert message in html , message;
    }
    lowered = html.lower();
    for outside in ["<script src", "<link", "@import", "http://", "url("] {
        assert outside not in lowered , outside;
    }
    # The movie's text is the cinema's: it's set as text, never parsed as HTML.
    assert "innerhtml" not in lowered and "insertadjacenthtml" not in lowered;
    assert "document.write" not in lowered;
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
