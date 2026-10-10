"""What the OAuth provider remembers (P8.6a), on the shared store's claims (core/claims.jac).

- Clients (Dynamic Client Registration): a random client id, the client's name and its
  exact redirect URIs. Public clients: no secret (PKCE protects the code).
- Authorization codes: single-use and valid for CODE_TTL seconds, bound to the client,
  redirect URI, PKCE challenge, resource, scope and the approving customer.
- Refresh tokens: valid for REFRESH_TTL, rotated on every use (a used one is gone).
- Chat accounts: the customer an MCP token acts for has a separate Jac account of their
  own (core/oauth/accounts.jac), linked both ways here.

Codes and refresh tokens are kept only as their SHA-256, so the store never holds a
usable secret; taking one (claims.take) is a single statement, so exactly one caller
gets it, and never after it expires.
"""

import json;
import uuid;
import hashlib;
import secrets;
import from core.claims { claim, holder, take }

glob CLIENTS: str = "oauth-client",
     CODES: str = "oauth-code",
     REFRESHES: str = "oauth-refresh",
     CHAT_ACCOUNTS: str = "oauth-chat-account",
     CHAT_CUSTOMERS: str = "oauth-chat-customer",
     CODE_TTL: int = 60,
     REFRESH_TTL: int = 30 * 24 * 3600;

def same_id(root_id: str) -> str {
    # A root id in one form: Jac's identity store writes hex, node_id dashed UUIDs.
    try {
        return str(uuid.UUID(root_id));
    } except ValueError {
        return root_id;
    }
}

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
    kept = take(namespace, _hash(secret));
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

def chat_account_of(customer_root: str) -> dict[str, str] | None {
    kept = holder(CHAT_ACCOUNTS, same_id(customer_root));
    return json.loads(kept) if kept else None;
}

def link_chat_account(
    customer_root: str, user_id: str, chat_root: str
) -> dict[str, str] {
    # Links once: if another request linked first, its account wins.
    kept = claim(
        CHAT_ACCOUNTS,
        same_id(customer_root),
        json.dumps({"user_id": user_id, "root_id": same_id(chat_root)})
    );
    linked: dict[str, str] = json.loads(kept);
    claim(CHAT_CUSTOMERS, linked["root_id"], same_id(customer_root));
    return linked;
}

def customer_of_chat(chat_root: str) -> str | None {
    # The customer a chat account acts for, or None if `chat_root` isn't one.
    return holder(CHAT_CUSTOMERS, same_id(chat_root)) if chat_root else None;
}
