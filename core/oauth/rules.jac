"""OAuth 2.1 rules for MCP sign-in (P8.6a), as pure functions: PKCE, redirects, discovery.

MCP's authorization spec (2025-11-25) makes the MCP server an OAuth resource server and
lets the authorization server live beside it; ours does (core/oauth/provider.jac).

- PKCE: only S256. A verifier is 43 to 128 unreserved characters; the challenge is its
  SHA-256, base64url without padding (RFC 7636). Compared in constant time.
- Redirect URIs: https, or http to the machine itself (localhost, 127.0.0.1), as the
  spec requires; never a fragment. Clients register theirs exactly, and every request
  must name one of them exactly (state.jac).
- Discovery: the protected-resource document (RFC 9728) for each MCP route, and the
  authorization-server document (RFC 8414) naming our endpoints.
"""

import re;
import hmac;
import base64;
import hashlib;
import from urllib.parse { urlparse, urlencode }

glob SCOPE: str = "africinemas",
     VERIFIER_SHAPE: str = r"^[A-Za-z0-9\-._~]{43,128}$",
     CHALLENGE_SHAPE: str = r"^[A-Za-z0-9\-_]{43}$",
     LOOPBACK: list[str] = ["localhost", "127.0.0.1"];

def s256(verifier: str) -> str {
    digest = hashlib.sha256(verifier.encode("ascii")).digest();
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=");
}

def challenge_ok(challenge: str, method: str) -> bool {
    # A code challenge we accept: S256 only, and a SHA-256's shape.
    return method == "S256" and re.fullmatch(CHALLENGE_SHAPE, challenge) is not None;
}

def challenge_matches(verifier: str, challenge: str) -> bool {
    if re.fullmatch(VERIFIER_SHAPE, verifier) is None {
        return False;
    }
    return hmac.compare_digest(s256(verifier), challenge);
}

def redirect_ok(uri: str) -> bool {
    # https, or http to this machine; a host, and no fragment.
    try {
        parts = urlparse(uri);
    } except ValueError {
        return False;
    }
    if parts.fragment or not parts.hostname or "#" in uri {
        return False;
    }
    if parts.scheme == "https" {
        return True;
    }
    return parts.scheme == "http" and parts.hostname in LOOPBACK;
}

def with_query(uri: str, params: dict[str, str]) -> str {
    # `uri` with `params` added to its query, encoded.
    joiner = "&" if "?" in uri else "?";
    return uri + joiner + urlencode(params);
}

def protected_resource(base: str, path: str) -> dict[str, any] {  # jac:ignore[W1037]
    # RFC 9728: which authorization server issues tokens for the MCP route at `path`.
    return {
        "resource": f"{base}{path}",
        "authorization_servers": [base],
        "bearer_methods_supported": ["header"],
        "scopes_supported": [SCOPE],
        "resource_name": "AfriCinemas"
    };
}

def authorization_server(base: str) -> dict[str, any] {  # jac:ignore[W1037]
    # RFC 8414: our endpoints and what they accept.
    return {
        "issuer": base,
        "authorization_endpoint": f"{base}/oauth/authorize",
        "token_endpoint": f"{base}/oauth/token",
        "registration_endpoint": f"{base}/oauth/register",
        "scopes_supported": [SCOPE],
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported": ["none"],
        "client_id_metadata_document_supported": False
    };
}
