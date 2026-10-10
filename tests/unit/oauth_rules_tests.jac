"""P8.6a: the OAuth rules for MCP sign-in (core/oauth/rules.jac), without a server.

- PKCE S256, checked against RFC 7636's own example; a verifier of the wrong shape never
  matches, and only S256 is accepted.
- Redirect URIs: https, or http to the machine itself (localhost, 127.0.0.1); never a
  fragment, never another scheme.
- The redirect back to the client keeps its own query and adds code and state, encoded.
- The discovery documents name our endpoints, PKCE S256 only, the code flow, public
  clients, and the resource each MCP route is.
"""

import from core.oauth.rules {
    s256,
    challenge_matches,
    challenge_ok,
    redirect_ok,
    with_query,
    protected_resource,
    authorization_server,
    SCOPE
}

glob VERIFIER: str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
     CHALLENGE: str = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
     BASE: str = "https://cinemas.example.com";

test "PKCE S256 matches RFC 7636's example, and nothing else" {
    assert s256(VERIFIER) == CHALLENGE;
    assert challenge_matches(VERIFIER, CHALLENGE);
    assert not challenge_matches(VERIFIER + "x", CHALLENGE);
    assert not challenge_matches("short", s256("short"));
    assert not challenge_matches(
        "has space " + "a" * 40, s256("has space " + "a" * 40)
    );
    assert challenge_ok(CHALLENGE, "S256");
    assert not challenge_ok(CHALLENGE, "plain");
    assert not challenge_ok("too-short", "S256");
}

test "redirect URIs are https, or http to the machine itself" {
    for good in [
        "https://claude.ai/api/mcp/auth_callback",
        "http://localhost:3000/callback",
        "http://127.0.0.1:8080/cb"
    ] {
        assert redirect_ok(good) , good;
    }
    for bad in [
        "http://evil.example.com/cb",
        "https://claude.ai/cb#steal",
        "javascript:alert(1)",
        "claude://callback",
        "",
        "https://"
    ] {
        assert not redirect_ok(bad) , bad;
    }
}

test "the redirect back keeps the client's query and adds code and state" {
    assert with_query("https://claude.ai/cb", {"code": "abc", "state": "a b&c"})
        == "https://claude.ai/cb?code=abc&state=a+b%26c";
    assert with_query("https://claude.ai/cb?x=1", {"code": "abc"})
        == "https://claude.ai/cb?x=1&code=abc";
}

test "the discovery documents name our endpoints, S256 only, and each MCP resource" {
    meta = authorization_server(BASE);
    assert meta["issuer"] == BASE;
    assert meta["authorization_endpoint"] == f"{BASE}/oauth/authorize";
    assert meta["token_endpoint"] == f"{BASE}/oauth/token";
    assert meta["registration_endpoint"] == f"{BASE}/oauth/register";
    assert meta["code_challenge_methods_supported"] == ["S256"];
    assert meta["response_types_supported"] == ["code"];
    assert sorted(meta["grant_types_supported"])
        == ["authorization_code", "refresh_token"];
    assert meta["token_endpoint_auth_methods_supported"] == ["none"];
    assert meta["scopes_supported"] == [SCOPE];
    platform = protected_resource(BASE, "/mcp");
    assert platform["resource"] == f"{BASE}/mcp";
    assert platform["authorization_servers"] == [BASE];
    assert platform["bearer_methods_supported"] == ["header"];
    assert platform["scopes_supported"] == [SCOPE];
    assert protected_resource(BASE, "/c/nova/mcp")["resource"] == f"{BASE}/c/nova/mcp";
}
