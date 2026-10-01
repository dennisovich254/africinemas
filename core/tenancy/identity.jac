"""Who the caller is, as they sign in (P3.7c).

A request only carries the caller's root, and Jac's identity store maps people to roots,
not back. So a sign-in name (an email in the web app) is taken from the client and kept
only when the identity store confirms it belongs to the caller: nobody can label their
staff record with someone else's address.
"""

import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from core.tenancy.principal { node_id }

glob CLAIM_MAX: int = 254;

def _same_id(a: str, b: str) -> bool {
    try {
        return UUID(a) == UUID(b);
    } except (ValueError, TypeError) {
        return False;
    }
}

def verified_sign_in(claimed: str) -> str {
    # `claimed` tidied, if it is one of the caller's own sign-in names; otherwise "".
    if not isinstance(claimed, str) {
        return "";
    }
    value = claimed.strip().lower();
    if not value or len(value) > CLAIM_MAX {
        return "";
    }
    users: any = Jac.get_user_manager(Jac.get_context().base_path_dir or "");  # jac:ignore[W1037]
    found = users.find_user_by_identity(value);
    if not found {
        return "";
    }
    owner = str(
        found.get("root_id") or users.get_root_id(str(found.get("user_id", ""))) or ""
    );
    return value if _same_id(owner, node_id(root)) else "";
}
