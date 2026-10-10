"""P8.6a: signing Claude in with OAuth 2.1 (core/oauth), against a real cinema.

In-process app (tests/apps/payment_app.jac). The flow MCP's authorization spec sets out:
discovery, Dynamic Client Registration, the customer's consent (signed in, on our page),
the code for a token with PKCE S256, then MCP calls with that token.

- The discovery documents are served for each cinema's own MCP connector; sign-in is per
  cinema (P8.6c), so the platform's /mcp has none.
- A signed-in customer approves; the code buys a token; with it, MCP offers and answers
  my_bookings with that customer's bookings (and nothing private). Without it, no.
- A code is single-use and bound to its PKCE verifier, client and redirect; approval
  refuses an unregistered redirect, an unknown client and anything but S256;
  registration refuses a redirect that isn't https or this machine.
- Refresh tokens rotate: the old one is refused once used.
- The token belongs to a chat account linked to the customer, with no staff power:
  signed in as staff, the token still can't touch the cinema.

Jac can't send 401 or 400 (JI-033): errors come back as 200 with an OAuth `error`.
"""

import json;
import os;
import from urllib.parse { urlencode, urlparse, parse_qs }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, customer_at, open_cinema_for }
import from tests.support.payment_setup { ANNA, ANNA_EMAIL, paying_cinema, paid }

glob VERIFIER: str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
     CHALLENGE: str = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
     REDIRECT: str = "https://claude.ai/api/mcp/auth_callback",
     BASE: str = "http://localhost:8000",
     # Sign-in is per cinema (P8.6c): Nova's own connector.
     RESOURCE: str = "http://localhost:8000/c/nova/mcp",
     NOVA_MCP: str = "/c/nova/mcp";


# The public address these tests expect, whatever a developer's .env says (Jac loads
# .env into test apps too; a tunnel address there would change every URL).
with entry {
    os.environ["AFRICINEMAS_PUBLIC_URL"] = "http://localhost:8000";
}

def _get(app: Served, path: str) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token("");
    resp = app.client.get(path);
    assert resp.status_code == 200 , f"{path}: {resp.status_code} {resp.text[:200]}";
    return json.loads(resp.text);
}

def _register(app: Served, redirect: str = REDIRECT) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token("");
    resp = app.client.post(
        "/oauth/register",
        json={
            "client_name": "Claude",
            "redirect_uris": [redirect],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "logo_uri": "https://claude.ai/logo.png"
        }
    );
    assert resp.status_code == 200 , resp.text;
    return json.loads(resp.text);
}

def _approve(
    app: Served,
    who: str,
    client_id: str,
    redirect: str = REDIRECT,
    method: str = "S256"
) -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "oauth_approve",
        {
            "client_id": client_id,
            "redirect_uri": redirect,
            "code_challenge": CHALLENGE,
            "code_challenge_method": method,
            "resource": RESOURCE,
            "scope": "africinemas",
            "state": "xyz 1"
        }
    );
}

def _code(approved: dict[str, any]) -> str {  # jac:ignore[W1037]
    assert approved["ok"] , approved;
    return parse_qs(urlparse(approved["redirect"]).query)["code"][0];
}

def _token(app: Served, fields: dict[str, str]) -> any {  # jac:ignore[W1037]
    # The token endpoint takes a form, as OAuth clients send it.
    app.client.set_auth_token("");
    resp = app.client._execute_request(
        "POST",
        "/oauth/token",
        urlencode(fields).encode(),
        {"Content-Type": "application/x-www-form-urlencoded"}
    );
    assert resp.status_code == 200 , resp.text;
    return json.loads(resp.text);
}

def _swap(
    app: Served,
    code: str,
    verifier: str = VERIFIER,
    redirect: str = REDIRECT,
    client_id: str = ""
) -> any {  # jac:ignore[W1037]
    return _token(
        app,
        {
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": client_id,
            "redirect_uri": redirect,
            "resource": RESOURCE
        }
    );
}

def _signed_in(app: Served, who: str) -> tuple[str, dict[str, any]] {  # jac:ignore[W1037]
    # Claude registers, `who` approves, and the code becomes tokens.
    client = _register(app)["client_id"];
    tokens = _swap(app, _code(_approve(app, who, client)), VERIFIER, REDIRECT, client);
    assert "access_token" in tokens , tokens;
    return (client, tokens);
}

def _mcp(
    app: Served,
    token: str,
    method: str,
    params: dict[str, any] | None = None  # jac:ignore[W1037]
) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token(token);
    resp = app.client.post(
        NOVA_MCP,
        json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}
    );
    app.client.set_auth_token("");
    assert resp.status_code == 200 , resp.text;
    return json.loads(resp.text);
}

test "the discovery documents are served for each cinema's own connector only" {
    (app, _, _) = paying_cinema([]);
    try {
        meta = _get(app, "/.well-known/oauth-authorization-server");
        assert meta["issuer"] == BASE
            and meta["code_challenge_methods_supported"] == ["S256"] , meta;
        doc = _get(app, "/.well-known/oauth-protected-resource/c/nova/mcp");
        assert doc["resource"] == RESOURCE and doc["authorization_servers"] == [BASE];
        # The platform's /mcp serves every cinema: nobody signs in on it (P8.6c).
        for path in [
            "/.well-known/oauth-protected-resource",
            "/.well-known/oauth-protected-resource/mcp"
        ] {
            assert app.client.get(path).status_code in [404, 405] , path;
        }
    } finally {
        app.close();
    }
}

test "a customer signs Claude in, and with the token Claude sees their bookings" {
    (app, _, screening) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        paid(app, screening);
        link = browse(
            app,
            "my_payment",
            {"slug": "nova", "screening_id": screening, "holder": ANNA}
        )["payment"]["link"];
        assert app.call(
            "kim",
            "save_booking",
            {"slug": "nova", "token": link.rsplit("/", 1)[1], "display_name": "Kim"}
        )["ok"];
        client = _register(app)["client_id"];
        # The consent page shows who asks and where the customer goes back to.
        info = app.call(
            "kim",
            "oauth_consent_info",
            {"client_id": client, "redirect_uri": REDIRECT, "resource": RESOURCE}
        );
        assert info["ok"] and info["client_name"] == "Claude" , info;
        assert info["redirect_host"] == "claude.ai";
        approved = _approve(app, "kim", client);
        assert approved["redirect"].startswith(REDIRECT + "?") , approved;
        assert parse_qs(urlparse(approved["redirect"]).query)["state"] == ["xyz 1"];
        tokens = _swap(app, _code(approved), VERIFIER, REDIRECT, client);
        assert tokens["token_type"] == "Bearer" and tokens["access_token"] , tokens;
        assert tokens["refresh_token"] and tokens["expires_in"] > 0;
        # Signed in, Claude gets the customer's bookings; signed out, no such tool.
        names = [
            t["name"]
            for t in _mcp(app, tokens["access_token"], "tools/list")["result"]["tools"]
        ];
        assert "my_bookings" in names , names;
        assert "my_bookings"
            not in [t["name"] for t in _mcp(app, "", "tools/list")["result"]["tools"]];
        got = _mcp(
            app,
            tokens["access_token"],
            "tools/call",
            {"name": "my_bookings", "arguments": {"cinema": "nova"}}
        )["result"];
        text = got["content"][0]["text"];
        assert got["isError"] == False and "Rafiki" in text , got;
        assert ANNA_EMAIL not in text and '"qr"' not in text;
    } finally {
        app.close();
    }
}

test "a code is single-use and bound to its verifier, client and redirect" {
    (app, _, _) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        client = _register(app)["client_id"];
        # A wrong verifier spends the code: it's refused, and so is the right one after.
        code = _code(_approve(app, "kim", client));
        assert _swap(app, code, "w" * 43, REDIRECT, client)["error"] == "invalid_grant";
        assert _swap(app, code, VERIFIER, REDIRECT, client)["error"] == "invalid_grant";
        # Another client, or another redirect, can't use it.
        code = _code(_approve(app, "kim", client));
        other = _register(app)["client_id"];
        assert _swap(app, code, VERIFIER, REDIRECT, other)["error"] == "invalid_grant";
        code = _code(_approve(app, "kim", client));
        assert _swap(app, code, VERIFIER, "https://claude.ai/other", client)["error"]
            == "invalid_grant";
        # A good code works once.
        code = _code(_approve(app, "kim", client));
        assert "access_token" in _swap(app, code, VERIFIER, REDIRECT, client);
        assert _swap(app, code, VERIFIER, REDIRECT, client)["error"] == "invalid_grant";
        assert _token(app, {"grant_type": "password"})["error"]
            == "unsupported_grant_type";
    } finally {
        app.close();
    }
}

test "approval and registration refuse what the spec forbids" {
    (app, _, _) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        client = _register(app)["client_id"];
        assert _approve(app, "kim", client, "https://evil.example.com/cb")["ok"]
            == False;
        assert _approve(app, "kim", "made-up-client")["ok"] == False;
        assert _approve(app, "kim", client, REDIRECT, "plain")["ok"] == False;
        # Only a cinema's own connector signs in: not the platform's /mcp.
        platform = app.call(
            "kim",
            "oauth_approve",
            {
                "client_id": client,
                "redirect_uri": REDIRECT,
                "code_challenge": CHALLENGE,
                "code_challenge_method": "S256",
                "resource": f"{BASE}/mcp",
                "scope": "africinemas",
                "state": ""
            }
        );
        assert platform["ok"] == False
            and platform["error"]["code"] == "invalid_target";
        bad = _register(app, "http://evil.example.com/cb");
        assert bad.get("error") == "invalid_redirect_uri" , bad;
    } finally {
        app.close();
    }
}

test "refresh tokens rotate, and a used one is refused" {
    (app, _, _) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        (client, tokens) = _signed_in(app, "kim");
        fresh = _token(
            app,
            {
                "grant_type": "refresh_token",
                "refresh_token": tokens["refresh_token"],
                "client_id": client
            }
        );
        assert fresh["access_token"]
            and fresh["refresh_token"] != tokens["refresh_token"] , fresh;
        again = _token(
            app,
            {
                "grant_type": "refresh_token",
                "refresh_token": tokens["refresh_token"],
                "client_id": client
            }
        );
        assert again["error"] == "invalid_grant";
    } finally {
        app.close();
    }
}

test "only the cinema's own customers sign Claude in, and the token has no staff power" {
    (app, _, _) = paying_cinema([]);
    try {
        open_cinema_for(app, "owner", "rift", "Rift Cinemas");
        client = _register(app)["client_id"];
        # Staff accounts, and other cinemas' customers, can't sign Claude in at Nova.
        customer_at(app, "rift", "riftfan");
        for who in ["owner", "riftfan"] {
            refused = _approve(app, who, client);
            assert refused["ok"] == False
                and refused["error"]["code"] == "not_your_cinema" , f"{who}: {refused}";
        }
        # Nova's customer can; the token still can't reach the back office.
        customer_at(app, "nova", "kim");
        (_, tokens) = _signed_in(app, "kim");
        app.client.set_auth_token(tokens["access_token"]);
        resp = app.client.post("/function/staff_home", json={"tenant": "nova"});
        app.client.set_auth_token("");
        assert resp.status_code == 200 , resp.text;
        assert resp.data["result"]["ok"] == False , resp.data;
        # Nor does it sign anyone in at Rift's connector.
        app.client.set_auth_token(tokens["access_token"]);
        listed = app.client.post(
            "/c/rift/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
        );
        app.client.set_auth_token("");
        names = [t["name"] for t in json.loads(listed.text)["result"]["tools"]];
        assert "my_bookings" not in names , names;
    } finally {
        app.close();
    }
}
