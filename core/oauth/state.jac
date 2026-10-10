"""What the OAuth provider remembers (P8.6a), on the shared store's claims (core/claims.jac).

- Clients (Dynamic Client Registration): a random client id, the client's name and its
  exact redirect URIs. Public clients: no secret (PKCE protects the code).
- Authorization codes: single-use and valid for CODE_TTL seconds, bound to the client,
  redirect URI, PKCE challenge, resource, scope and the approving customer.
- Refresh tokens: valid for REFRESH_TTL, rotated on every use (a used one is gone).
- Connections (P8.6d): each app a customer signs in has its own chat account (a separate
  Jac account, core/oauth/accounts.jac), kept here per customer and app with the app's
  name, the cinema and when it was connected. A connection lasts as long as a refresh
  token (REFRESH_TTL), renewed with each refresh; the chat account's root points back
  to its customer.

Codes and refresh tokens are kept only as their SHA-256, so the store never holds a
usable secret; taking one (claims.take_claim) is a single statement, so exactly one caller
gets it, and never after it expires.
"""

import json;
import hashlib;
import secrets;
import from core.claims { claim, holder, release, renew, take_claim, claims_in }
import from core.tenancy.principal { same_id }

glob CLIENTS: str = "oauth-client",
     CODES: str = "oauth-code",
     REFRESHES: str = "oauth-refresh",
     CONNECTIONS: str = "oauth-connection",
     CHAT_CUSTOMERS: str = "oauth-chat-customer",
     CODE_TTL: int = 60,
     REFRESH_TTL: int = 30 * 24 * 3600;

def _hash(secret: str) -> str {
    return hashlib.sha256(secret.encode("utf-8")).hexdigest();
}

def register_client(name: str, redirect_uris: list[str]) -> str {
    client_id = "ac-" + secrets.token_urlsafe(18);
    claim(
        CLIENTS,
        client_id,
        json.dumps({"name": name[:100], "redirect_uris": redirect_uris[:10]})
    );
    return client_id;
}

def client_of(client_id: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    if not client_id {
        return None;
    }
    kept = holder(CLIENTS, client_id);
    return json.loads(kept) if kept else None;
}

def _issue(namespace: str, record: dict[str, any], ttl: int) -> str {  # jac:ignore[W1037]
    secret = secrets.token_urlsafe(32);
    claim(namespace, _hash(secret), json.dumps(record), ttl);
    return secret;
}

def _take(namespace: str, secret: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    if not secret {
        return None;
    }
    kept = take_claim(namespace, _hash(secret));
    return json.loads(kept) if kept else None;
}

def issue_code(record: dict[str, any]) -> str {  # jac:ignore[W1037]
    return _issue(CODES, record, CODE_TTL);
}

def take_code(code: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    return _take(CODES, code);
}

def issue_refresh(record: dict[str, any]) -> str {  # jac:ignore[W1037]
    return _issue(REFRESHES, record, REFRESH_TTL);
}

def take_refresh(token: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    return _take(REFRESHES, token);
}

def _connections(customer_root: str) -> str {
    # The namespace of one customer's connections, keyed by the app's client id.
    return f"{CONNECTIONS}:{same_id(customer_root)}";
}

def connection_of(customer_root: str, client_id: str) -> dict[str, str] | None {
    # The app's live connection for this customer: its name, cinema, when, and its
    # chat account's ids.
    kept = holder(_connections(customer_root), client_id) if client_id else None;
    return json.loads(kept) if kept else None;
}

def connections_of(customer_root: str) -> list[tuple[str, dict[str, str]]] {
    # The customer's live connections as (client id, connection), oldest first.
    found: list[tuple[str, dict[str, str]]] = [];
    for (client_id, _, _) in claims_in(_connections(customer_root)) {
        live = connection_of(customer_root, client_id);
        if live is not None {
            found.append((client_id, live));
        }
    }
    return found;
}

def record_connection(
    customer_root: str, client_id: str, record: dict[str, str]
) -> dict[str, str] {
    # Records the connection once: if another request recorded it first, that one wins.
    kept = claim(
        _connections(customer_root), client_id, json.dumps(record), REFRESH_TTL
    );
    won: dict[str, str] = json.loads(kept);
    claim(CHAT_CUSTOMERS, same_id(won["root_id"]), same_id(customer_root));
    return won;
}

def keep_connection(customer_root: str, client_id: str) -> bool {
    # Another REFRESH_TTL for a live connection; False if it has ended.
    space = _connections(customer_root);
    kept = holder(space, client_id);
    return kept is not None and renew(space, client_id, kept, REFRESH_TTL);
}

def end_connection(customer_root: str, client_id: str) -> dict[str, str] | None {
    # Ends the connection (exactly one caller gets it) and unlinks its chat account.
    kept = take_claim(_connections(customer_root), client_id);
    if not kept {
        return None;
    }
    ended: dict[str, str] = json.loads(kept);
    release(CHAT_CUSTOMERS, same_id(ended["root_id"]), same_id(customer_root));
    return ended;
}

def customer_of_chat(chat_root: str) -> str | None {
    # The customer a chat account acts for, or None if `chat_root` isn't one.
    return holder(CHAT_CUSTOMERS, same_id(chat_root)) if chat_root else None;
}
