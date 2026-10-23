"""Platform accounts (P13.1b.a): AfriCinemas staff sign in with accounts of their own.

A platform account is apart from any cinema account with the same email, as a
cinema's customer accounts are (ADR-0037): its own username, its own password, and a
permanent claim on its root naming its email. Only the server makes one, from a join
link; there is no sign-up for the platform, and Jac's own sign-up can't make one (a
name it made is no one's platform account, and joining replaces it).

- sign_in_name(email): "platform:<local part>:<domain>" ("platform" is a reserved
  slug, so it's never a cinema's customer account).
- account_email(root_id): the email of a platform account, or "".
- A join link is a single-use token naming the email: an invitation from a super admin
  (INVITE_TTL_S) or, for the super admins in the server's settings, one printed by
  scripts/platform_setup.jac (SETUP_TTL_S). It sets the account's password, making the
  account the first time.
"""

import from jaclang { JacRuntime as Jac }
import from jaclang.server.identity.app_tokens {
    token_create,
    token_peek,
    token_consume,
    token_revoke
}
import from core.claims { claim, holder, claims_in }
import from core.tenancy.principal { same_id }

glob ACCOUNTS: str = "platform-account",
     JOIN_PURPOSE: str = "platform-join",
     PREFIX: str = "platform:",
     INVITE_TTL_S: int = 72 * 3600,
     SETUP_TTL_S: int = 24 * 3600;

def sign_in_name(email: str) -> str {
    # The account's username: Jac 0.38 refuses "@" in a username, so ":" stands in.
    return PREFIX + email.strip().lower().replace("@", ":");
}

def users -> any {  # jac:ignore[W1037]
    return Jac.get_user_manager(Jac.get_context().base_path_dir or "");
}

def account_email(root_id: str) -> str {
    return (holder(ACCOUNTS, same_id(root_id)) or "") if root_id else "";
}

def has_account(email: str) -> bool {
    return any([value == email for (_, value, _) in claims_in(ACCOUNTS)]);
}

def record_account(root_id: str, email: str) {
    claim(ACCOUNTS, same_id(root_id), email);
}

def join_link(email: str, ttl_seconds: int) -> str {
    # A new join token for `email`; any earlier one stops working.
    token_revoke(JOIN_PURPOSE, email);
    return token_create(
        JOIN_PURPOSE, subject=email, ttl_seconds=ttl_seconds, payload={"email": email}
    );
}

def peek_join(token: str) -> str {
    # The email a join token names while it's valid, else "".
    found = token_peek(JOIN_PURPOSE, token)
        if isinstance(token, str) and token
        else None;
    return str(found["payload"].get("email", "")) if found else "";
}

def use_join(token: str) -> bool {
    # Spends the token; False if another request spent it first.
    return token_consume(JOIN_PURPOSE, token) is not None;
}

def cancel_joins(email: str) {
    token_revoke(JOIN_PURPOSE, email);
}
