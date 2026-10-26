"""The signed-in person's own profile (P12.15, ADR-0077; improvements #13): their name
and their password.

For everyone who signs in: a cinema's staff (Your profile in the back office), a
storefront's customers (My account) and AfriCinemas' own team.
- my_profile(sign_in): their name, the sign-in name (only if it's the caller's own:
  verified_sign_in) and what kind of account it is.
- save_my_name(name): plain text, up to NAME_MAX. A customer's is kept with their
  storefront account (core/tenancy/storefront_accounts.jac), anyone else's as a claim
  per account (PROFILE_NAMES), which their colleagues see (staff_name).
- change_my_password(sign_in, current_password, new_password): through Jac's user
  manager, so its password rules apply; the current password is asked first. Staff
  send the email they signed in with; a customer's sign-in name comes from their
  account, so they may send "".

Not here, because Jac can't do them yet: changing the sign-in email (an account holds
one email, and nothing replaces it: JI-058), and signing out everywhere (a password
change leaves other sessions signed in: JI-059).
"""

import json;
import from jaclang { JacRuntime as Jac }
import from core.claims { claim, holder, take_claim }
import from core.catalog.answers { Refused, answer }
import from core.tenancy.identity { verified_sign_in }
import from core.tenancy.principal { node_id, same_id }
import from core.tenancy.storefront_accounts { ACCOUNTS, account_of, password_advice }
import from core.platform.accounts { account_email as platform_email }

glob PROFILE_NAMES: str = "profile-name",
     NAME_MAX: int = 80;

def name_of(root_id: str) -> str {
    # The name someone gave themselves on their profile, or "".
    if not root_id {
        return "";
    }
    customer = account_of(root_id);
    if customer is not None {
        return str(customer.get("name", ""));
    }
    return holder(PROFILE_NAMES, same_id(root_id)) or "";
}

def _kind(root_id: str) -> str {
    if account_of(root_id) is not None {
        return "customer";
    }
    return "platform" if platform_email(root_id) else "staff";
}

def _customer_sign_in(customer: dict[str, any]) -> str {  # jac:ignore[W1037]
    # A customer's sign-in name, from their account: the current form, or the one
    # made before Jac 0.38 (web/storefront/customer_session.jac).
    email = str(customer.get("email", "")).lower();
    slug = str(customer.get("slug", ""));
    for value in [f"{slug}:{email.replace('@', ':')}", f"{slug}:{email}"] {
        if verified_sign_in(value) {
            return value;
        }
    }
    return "";
}

def _mine(sign_in: str) -> str {
    # The caller's own sign-in name: the one they sent if it is theirs; a customer's
    # from their account.
    mine = verified_sign_in(sign_in) if sign_in else "";
    customer = account_of(node_id(root)) if not mine else None;
    if customer is not None {
        mine = _customer_sign_in(customer);
    }
    if not mine {
        raise Refused("not_you", "Sign out and back in, then try again.");
    }
    return mine;
}

def _profile(sign_in: str) -> dict[str, any] {  # jac:ignore[W1037]
    me = node_id(root);
    return {
        "ok": True,
        "kind": _kind(me),
        "name": name_of(me),
        # The sign-in name, only when it's the caller's own.
        "sign_in": verified_sign_in(sign_in) if sign_in else ""
    };
}

def _save_name(name: str) -> dict[str, any] {  # jac:ignore[W1037]
    clean = " ".join(name.split()) if isinstance(name, str) else "";
    if not clean or len(clean) > NAME_MAX or "<" in clean or ">" in clean {
        raise Refused(
            "invalid_name",
            f"Enter your name, up to {NAME_MAX} characters, in plain text."
        );
    }
    me = node_id(root);
    key = same_id(me);
    customer = account_of(me);
    if customer is not None {
        kept = {** customer, "name": clean};
        take_claim(ACCOUNTS, key);
        claim(ACCOUNTS, key, json.dumps(kept));
    } else {
        take_claim(PROFILE_NAMES, key);
        claim(PROFILE_NAMES, key, clean);
    }
    return {"ok": True, "name": clean};
}

def _change_password(
    sign_in: str, current_password: str, new_password: str
) -> dict[str, any] {  # jac:ignore[W1037]
    mine = _mine(sign_in);
    if not isinstance(current_password, str) or not current_password {
        raise Refused("wrong_password", "Enter your current password.");
    }
    users: any = Jac.get_user_manager(Jac.get_context().base_path_dir or "");  # jac:ignore[W1037]
    found = users.find_user_by_identity(mine);
    if not found {
        raise Refused("not_you", "Sign out and back in, then try again.");
    }
    done = users.update_password(
        str(found.get("user_id", "")), current_password, str(new_password or "")
    );
    if "error" not in done {
        return {"ok": True};
    }
    if done.get("code", "") == "POLICY_VIOLATION" {
        raise Refused("weak_password", password_advice(done.get("violations") or []));
    }
    if "incorrect" in str(done["error"]).lower() {
        raise Refused("wrong_password", "That isn't your current password.");
    }
    raise Refused("not_changed", "Your password wasn't changed. Try again.");
}

def:protect my_profile(sign_in: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _profile(sign_in); });  # jac:ignore[W1037]
}

def:protect save_my_name(name: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _save_name(name); });  # jac:ignore[W1037]
}

def:protect change_my_password(
    sign_in: str, current_password: str, new_password: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _change_password(
            sign_in, current_password, new_password
        ); }  # jac:ignore[W1037]
    );
}
