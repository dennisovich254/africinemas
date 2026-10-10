"""Our OAuth 2.1 authorization server for MCP sign-in (P8.6a), beside the MCP server.

MCP's authorization spec (2025-11-25): the client (Claude) discovers us, registers,
sends the customer to our consent page with a PKCE S256 challenge, swaps the code for
tokens, and calls MCP with `Authorization: Bearer`.

- Discovery (GET): /.well-known/oauth-authorization-server, and the protected-resource
  document for /mcp and each /c/{slug}/mcp (rules.jac).
- POST /oauth/register: Dynamic Client Registration; redirect URIs must be https or this
  machine, and are kept exactly.
- The consent page (web/oauth/AuthorizePage.jac) asks oauth_consent_info and, on Allow,
  oauth_approve (signed in only): a single-use code bound to the client, redirect, PKCE
  challenge, resource and customer; oauth_deny sends the refusal back.
- POST /oauth/token (a form, as OAuth clients send it): the code (with its verifier) or
  a refresh token (rotated) buys a Jac session token for the customer's chat account
  (accounts.jac), which has no staff power.

Jac can't answer 400 or 401 or add WWW-Authenticate (JI-033): errors come back as 200
with an OAuth `error`, and clients find us through the discovery documents instead of a
401's challenge. ADR-0035.
"""

import os;
import re;
import time;
import from http { HTTPMethod }
import from urllib.parse { urlparse }
import from core.oauth.rules {
    SCOPE,
    challenge_ok,
    challenge_matches,
    redirect_ok,
    with_query,
    protected_resource,
    authorization_server
}
import from core.oauth.state {
    register_client,
    client_of,
    issue_code,
    take_code,
    issue_refresh,
    take_refresh,
    customer_of_chat
}
import from core.oauth.accounts { chat_account, access_token, token_seconds }
import from core.booking.ticket_delivery { PUBLIC_URL_ENV, DEFAULT_PUBLIC_URL }
import from core.tenancy.principal { node_id }
import from core.tenancy.responses { refused }

def base_url -> str {
    # Our public address (the tunnel's, or production's), as ticket links use.
    return os.environ.get(PUBLIC_URL_ENV, "").strip().rstrip("/") or DEFAULT_PUBLIC_URL;
}

def our_resource(resource: str) -> bool {
    # One of our MCP routes (or none named, which means the platform's).
    base = base_url();
    if resource in ["", f"{base}/mcp"] {
        return True;
    }
    return re.fullmatch(re.escape(base) + r"/c/[a-z0-9-]{1,63}/mcp", resource)
        is not None;
}

def _problem(error: str, description: str) -> dict[str, str] {
    return {"error": error, "error_description": description};
}

def _checked(
    client_id: str, redirect_uri: str, resource: str
) -> tuple[dict[str, any] | None, dict[str, any] | None] {  # jac:ignore[W1037]
    # (the client, None) when the request names a registered client, one of its exact
    # redirect URIs and one of our MCP routes; else (None, the refusal).
    client = client_of(client_id);
    if client is None {
        return (None, refused("invalid_client", "This app isn't registered here."));
    }
    if redirect_uri not in client["redirect_uris"] {
        return (
            None,
            refused("invalid_redirect", "This app can't send you back to that address.")
        );
    }
    if not our_resource(resource) {
        return (None, refused("invalid_target", "That isn't an AfriCinemas service."));
    }
    return (client, None);
}

@restspec(
    method=HTTPMethod.GET,
    path="/.well-known/oauth-authorization-server",
    produces="application/json",
    envelope=False
)
def:pub oauth_server_metadata -> dict[str, any] {  # jac:ignore[W1037]
    return authorization_server(base_url());
}

@restspec(
    method=HTTPMethod.GET,
    path="/.well-known/oauth-protected-resource",
    produces="application/json",
    envelope=False
)
def:pub oauth_resource_metadata -> dict[str, any] {  # jac:ignore[W1037]
    return protected_resource(base_url(), "/mcp");
}

@restspec(
    method=HTTPMethod.GET,
    path="/.well-known/oauth-protected-resource/mcp",
    produces="application/json",
    envelope=False
)
def:pub oauth_resource_metadata_mcp -> dict[str, any] {  # jac:ignore[W1037]
    return protected_resource(base_url(), "/mcp");
}

@restspec(
    method=HTTPMethod.GET,
    path="/.well-known/oauth-protected-resource/c/{slug}/mcp",
    produces="application/json",
    envelope=False
)
def:pub oauth_resource_metadata_cinema(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return protected_resource(base_url(), f"/c/{slug}/mcp");
}

@restspec(
    method=HTTPMethod.POST,
    path="/oauth/register",
    produces="application/json",
    envelope=False
)
def:pub oauth_register(
    redirect_uris: list[str], client_name: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # Dynamic Client Registration (RFC 7591) for public clients.
    if not redirect_uris
        or len(
            [
                u
                for u in redirect_uris
                if not redirect_ok(u)
            ]
        )
            > 0 {
        return _problem(
            "invalid_redirect_uri",
            "Redirect URIs must be https, or http to this machine."
        );
    }
    name = client_name.strip()[:100] or "An app";
    client_id = register_client(name, redirect_uris);
    return {
        "client_id": client_id,
        "client_id_issued_at": int(time.time()),
        "client_name": name,
        "redirect_uris": redirect_uris,
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": "none"
    };
}

def:priv oauth_consent_info(
    client_id: str, redirect_uri: str, resource: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # What the consent page shows: who asks, and where the customer goes back to.
    (client, problem) = _checked(client_id, redirect_uri, resource);
    if problem is not None {
        return problem;
    }
    return {
        "ok": True,
        "client_name": client["name"],
        "redirect_host": urlparse(redirect_uri).hostname or ""
    };
}

def:priv oauth_approve(
    client_id: str,
    redirect_uri: str,
    code_challenge: str,
    code_challenge_method: str,
    resource: str,
    scope: str,  # jac:ignore[W2003] asked for; we grant our one scope
    state: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # The signed-in customer allows the app: a single-use code, sent back to its redirect.
    (client, problem) = _checked(client_id, redirect_uri, resource);
    if problem is not None {
        return problem;
    }
    if not challenge_ok(code_challenge, code_challenge_method) {
        return refused("invalid_request", "This app must use PKCE with S256.");
    }
    customer = node_id(root);
    if customer == node_id(root.shared) or customer_of_chat(customer) is not None {
        return refused("forbidden", "Sign in with your own account to allow this.");
    }
    code = issue_code(
        {
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "challenge": code_challenge,
            "resource": resource or f"{base_url()}/mcp",
            "scope": SCOPE,
            "customer": customer
        }
    );
    back = {"code": code};
    if state {
        back["state"] = state[:500];
    }
    return {"ok": True, "redirect": with_query(redirect_uri, back)};
}

def:priv oauth_deny(
    client_id: str, redirect_uri: str, resource: str, state: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # The customer said no: the app hears access_denied, at a redirect it registered.
    (client, problem) = _checked(client_id, redirect_uri, resource);
    if problem is not None {
        return problem;
    }
    back = {"error": "access_denied"};
    if state {
        back["state"] = state[:500];
    }
    return {"ok": True, "redirect": with_query(redirect_uri, back)};
}

def _tokens(customer: str, client_id: str, resource: str) -> dict[str, any] {  # jac:ignore[W1037]
    account = chat_account(customer);
    refresh = issue_refresh(
        {"client_id": client_id, "customer": customer, "resource": resource}
    );
    return {
        "access_token": access_token(account["user_id"]),
        "token_type": "Bearer",
        "expires_in": token_seconds(),
        "refresh_token": refresh,
        "scope": SCOPE
    };
}

@restspec(
    method=HTTPMethod.POST,
    path="/oauth/token",
    produces="application/json",
    envelope=False
)
def:pub oauth_token(
    grant_type: str,
    code: str = "",
    code_verifier: str = "",
    client_id: str = "",
    redirect_uri: str = "",
    resource: str = "",
    refresh_token: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    if grant_type == "authorization_code" {
        # Taken first, so a code is spent even by a failed attempt.
        kept = take_code(code);
        if kept is None {
            return _problem("invalid_grant", "This code isn't valid (any more).");
        }
        if kept["client_id"] != client_id
            or kept["redirect_uri"] != redirect_uri
            or not challenge_matches(code_verifier, kept["challenge"])
            or (resource and resource != kept["resource"]) {
            return _problem(
                "invalid_grant", "This code wasn't issued for this request."
            );
        }
        return _tokens(kept["customer"], client_id, kept["resource"]);
    }
    if grant_type == "refresh_token" {
        kept = take_refresh(refresh_token);
        if kept is None or kept["client_id"] != client_id {
            return _problem(
                "invalid_grant", "This refresh token isn't valid (any more)."
            );
        }
        return _tokens(kept["customer"], client_id, kept["resource"]);
    }
    return _problem(
        "unsupported_grant_type", "Use authorization_code or refresh_token."
    );
}
