"""Signing an MCP client (Claude) in through our OAuth provider, for tests (P8.6a, P8.6d).

The flow MCP's authorization spec sets out: Dynamic Client Registration, the customer's
consent (signed in, on our page), the code for tokens with PKCE S256, refresh, and MCP
calls with the token, all on Nova's own connector.
"""

import json;
import os;
import from urllib.parse { urlencode, urlparse, parse_qs }
import from tests.support.served { Served }

glob VERIFIER: str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
     CHALLENGE: str = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
     REDIRECT: str = "https://claude.ai/api/mcp/auth_callback",
     BASE: str = "http://localhost:8000",
     # Sign-in is per cinema (P8.6c): Nova's own connector.
     RESOURCE: str = "http://localhost:8000/mcp/c/nova",
     NOVA_MCP: str = "/mcp/c/nova";


# The public address these tests expect, whatever a developer's .env says (Jac loads
# .env into test apps too; a tunnel address there would change every URL).
with entry {
    os.environ["AFRICINEMAS_PUBLIC_URL"] = "http://localhost:8000";
}

def get_json(app: Served, path: str) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token("");
    resp = app.client.get(path);
    assert resp.status_code == 200 , f"{path}: {resp.status_code} {resp.text[:200]}";
    return json.loads(resp.text);
}

def register_client(app: Served, redirect: str = REDIRECT) -> any {  # jac:ignore[W1037]
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

def approve(
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

def code_of(approved: dict[str, any]) -> str {  # jac:ignore[W1037]
    assert approved["ok"] , approved;
    return parse_qs(urlparse(approved["redirect"]).query)["code"][0];
}

def token_call(app: Served, fields: dict[str, str]) -> any {  # jac:ignore[W1037]
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

def swap(
    app: Served,
    code: str,
    verifier: str = VERIFIER,
    redirect: str = REDIRECT,
    client_id: str = ""
) -> any {  # jac:ignore[W1037]
    return token_call(
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

def signed_in(app: Served, who: str) -> tuple[str, dict[str, any]] {  # jac:ignore[W1037]
    # Claude registers, `who` approves, and the code becomes tokens.
    client = register_client(app)["client_id"];
    tokens = swap(app, code_of(approve(app, who, client)), VERIFIER, REDIRECT, client);
    assert "access_token" in tokens , tokens;
    return (client, tokens);
}

def mcp_call(
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

def refresh(app: Served, client_id: str, token: str) -> any {  # jac:ignore[W1037]
    return token_call(
        app,
        {"grant_type": "refresh_token", "refresh_token": token, "client_id": client_id}
    );
}
