"""Chat accounts (P8.6a): the Jac account an MCP token belongs to, one per customer.

A token from our OAuth provider is a normal Jac session token, so Jac's own sign-in
check (on every request) runs the MCP endpoint as its account. But that account is not
the customer's: it's a separate account made for chat, linked to the customer
(state.jac), holding no staff role in any cinema. So a token Claude holds (or loses)
can do what a signed-out visitor can, plus what the MCP tools do for the linked
customer, and never what the customer's staff roles allow.

Its password is random and never shown: nobody signs in to it. Deleting the account
voids its tokens (Jac checks the account exists).
"""

import os;
import uuid;
import secrets;
import from jaclang { JacRuntime }
import from jaclang.server.identity.user_manager { UserManager }
import from jaclang.server.identity.config { token_ttl_days }
import from core.oauth.state { chat_account_of, link_chat_account }

glob _managers: dict[str, any] = {};  # jac:ignore[W1037]

def _users -> any {  # jac:ignore[W1037]
    # The identity store of the app serving this request.
    base = JacRuntime.get_base_path_dir() or os.getcwd();
    if base not in _managers {
        _managers[base] = UserManager(base_path=base);
    }
    return _managers[base];
}

def chat_account(customer_root: str) -> dict[str, str] {
    # The customer's chat account, made on first use.
    found = chat_account_of(customer_root);
    if found is not None {
        return found;
    }
    made: dict[str, any] = _users().create_user(  # jac:ignore[W1037]
        f"chat-{uuid.uuid4().hex}", secrets.token_urlsafe(32)
    );
    if not made.get("user_id") or not made.get("root_id") {
        raise RuntimeError("the chat account couldn't be made");
    }
    return link_chat_account(customer_root, str(made["user_id"]), str(made["root_id"]));
}

def access_token(user_id: str) -> str {
    # A Jac session token for the chat account, without a role claim.
    return _users().create_jwt_token(user_id, include_role=False);
}

def token_seconds -> int {
    return int(token_ttl_days()) * 24 * 3600;
}
