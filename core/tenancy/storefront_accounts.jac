"""Storefront accounts (P8.6c): a customer account belongs to one cinema, apart from the back office.

User decision (2026-10-10), replacing ADR-0009's one login for everything: a storefront
is its own product. A customer signs up AT a cinema (customer_sign_up); the account is
that cinema's alone. It never works in the back office, never at another cinema, and
the same email can have a separate account, with its own password, at each cinema and
as staff. Staff accounts are no one's customer.

Under Jac's one identity store, a customer account is a username,
"<slug>:<local part>:<domain>" (sign_in_name; Jac 0.38 refuses an "@" in a username,
and accounts made before it keep "<slug>:<email>"), so it never collides with a staff account's email or another cinema's
customer. Signing up here, not through Jac's own sign-up, is what lets the server
record which cinema owns the account (a claim on its root id): every storefront and
back-office check asks that (cinema_of_account), never the client.

- require_customer_of(slug): the caller is a customer account of this cinema.
- require_staff_account(): the caller isn't a customer account (create a cinema, join
  a cinema's staff).
- my_storefront_account(slug): what a storefront needs to know about the caller.
ADR-0037.
"""

import re;
import json;
import from jaclang { JacRuntime as Jac }
import from core.claims { claim, holder }
import from core.catalog.answers { answer, Refused }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id, same_id }
import from core.tenancy.responses { NOT_FOUND, refused }
import from core.tenancy.models { NAME_MAX }
import from core.platform.accounts { account_email }

glob ACCOUNTS: str = "customer-account",
     # An account its customer asked to delete (P15.0): {"slug", "asked_at", "due"},
     # until it's deleted or they cancel (core/accounts/customer_data.jac).
     DELETING: str = "customer-deleting",
     EMAIL_SHAPE: str = r"^[^@\s:]{1,64}@[^@\s:]{1,190}\.[^@\s:]{2,63}$",
     PASSWORD_MIN: int = 8,
     PASSWORD_MAX: int = 128;

def sign_in_name(slug: str, email: str) -> str {
    # The account's username: its cinema, then its email with ":" for "@" (Jac 0.38
    # refuses "@" in a username; EMAIL_SHAPE keeps ":" out of an address, so it's still
    # one name per email).
    return f"{slug}:{email.strip().lower().replace('@', ':')}";
}

def old_sign_in_name(slug: str, email: str) -> str {
    # The username of an account made before Jac 0.38: "<slug>:<email>".
    return f"{slug}:{email.strip().lower()}";
}

def _users -> any {  # jac:ignore[W1037]
    return Jac.get_user_manager(Jac.get_context().base_path_dir or "");
}

def account_of(root_id: str) -> dict[str, str] | None {
    # {"slug", "email", "name"} when `root_id` is a customer account, else None.
    kept = holder(ACCOUNTS, same_id(root_id)) if root_id else None;
    return json.loads(kept) if kept else None;
}

def name_of_account(root_id: str) -> str {
    # The name a customer account signed up with, or "".
    found = account_of(root_id);
    return str(found.get("name", "")) if found is not None else "";
}

def cinema_of_account(root_id: str) -> str {
    # The cinema a customer account belongs to, or "" for any other account.
    found = account_of(root_id);
    return found["slug"] if found is not None else "";
}

def _caller -> str {
    me = node_id(root);
    return "" if me == node_id(root.shared) else me;
}

def deletion_of(root_id: str) -> dict[str, str] | None {
    # The account's deletion, asked for and not yet done, or None.
    kept = holder(DELETING, same_id(root_id)) if root_id else None;
    return json.loads(kept) if kept else None;
}

def require_customer_of(slug: str, while_deleting: bool = False) {
    # Refuses anyone but a customer account of the cinema `slug` names. An account
    # being deleted is locked (owner, 2026-10-29): only what `while_deleting` allows
    # (downloading their data, cancelling) still works.
    me = _caller();
    cinema = open_cinema(slug);
    if not me or cinema is None or cinema_of_account(me) != cinema.slug {
        raise Refused(
            "not_your_cinema", "Sign in with your account at this cinema to do that."
        );
    }
    if not while_deleting and deletion_of(me) is not None {
        raise Refused(
            "being_deleted",
            "Your account is being deleted. Keep it from Your account to use it again."
        );
    }
}

def require_staff_account {
    # Refuses customer accounts: they belong to a storefront, never the back office;
    # and AfriCinemas platform accounts, which belong to the platform (P13.1b.a).
    me = _caller();
    if me and cinema_of_account(me) {
        raise Refused(
            "customer_account",
            "This is a cinema's customer account. Sign in to the back office with your staff account."
        );
    }
    if me and account_email(me) {
        raise Refused(
            "platform_account",
            "This is an AfriCinemas platform account. Sign in to the back office with your staff account."
        );
    }
}

def password_advice(violations: list[str]) -> str {
    # What to tell someone when Jac's password rules refuse their password.
    if "PASSWORD_CONTAINS_IDENTIFIER" in violations {
        return "Choose a password that doesn't contain your email.";
    }
    if "PASSWORD_COMMON" in violations or "PASSWORD_BREACHED" in violations {
        return "That password is too easy to guess. Choose another one.";
    }
    return f"Use a password of at least {PASSWORD_MIN} characters.";
}

def _sign_up(slug: str, email: str, password: str, name: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    address = email.strip().lower() if isinstance(email, str) else "";
    if re.fullmatch(EMAIL_SHAPE, address) is None {
        return refused(
            "invalid_email", "Enter your email address, like name@example.com."
        );
    }
    if not isinstance(password, str)
        or len(password) < PASSWORD_MIN
        or len(password) > PASSWORD_MAX {
        return refused(
            "weak_password", f"Use a password of at least {PASSWORD_MIN} characters."
        );
    }
    username = sign_in_name(cinema.slug, address);
    if _users().find_user_by_identity(old_sign_in_name(cinema.slug, address)) {
        return refused(
            "taken",
            f"There's already an account for this email at {cinema.name}. Sign in instead."
        );
    }
    made: dict[str, any] = _users().create_user_with_identities(  # jac:ignore[W1037]
        identities=[{"type": "username", "value": username}],
        credential={"type": "password", "password": password}
    );
    if made.get("code") == "IDENTITY_TAKEN" {
        return refused(
            "taken",
            f"There's already an account for this email at {cinema.name}. Sign in instead."
        );
    }
    if made.get("code") == "POLICY_VIOLATION" {
        return refused("weak_password", password_advice(made.get("violations") or []));
    }
    if not made.get("root_id") {
        return refused("not_made", "We couldn't create your account. Try again.");
    }
    claim(
        ACCOUNTS,
        same_id(str(made["root_id"])),
        json.dumps(
            {
                "slug": cinema.slug,
                "email": address,
                "name": (name.strip() if isinstance(name, str) else "")[:NAME_MAX]
            }
        )
    );
    return {"ok": True, "sign_in_name": username};
}

def:pub customer_sign_up(
    slug: str, email: str, password: str, name: str = "", adult: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # A customer account at this cinema, with the name its bookings are saved under;
    # the page then signs in with sign_in_name. adult: "yes" when they declared they're
    # 18 or over (Data Protection Act s.33, P15.0); none is made without it. Text, not
    # a bool, for JI-060.
    return answer(
        lambda -> any { return _adult_sign_up(slug, email, password, name, adult); }
    );  # jac:ignore[W1037]
}

def _adult_sign_up(
    slug: str, email: str, password: str, name: str, adult: str
) -> dict[str, any] {  # jac:ignore[W1037]
    if adult != "yes" {
        raise Refused(
            "adult_required", "Confirm you're 18 or over to create an account."
        );
    }
    return _sign_up(slug, email, password, name);
}

def:pub my_storefront_account(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The storefront's view of the caller: signed in at all, and as this cinema's
    # customer (with the email they signed up with). `account_cinema` is the cinema
    # the caller's own account belongs to ("" for staff), so the back office's sign-in
    # knows a customer account isn't one of its own.
    me = _caller();
    cinema = open_cinema(slug);
    found = account_of(me) if me else None;
    mine = found is not None and cinema is not None and found["slug"] == cinema.slug;
    return {
        "ok": True,
        "signed_in": bool(me),
        "customer": mine,
        "email": found["email"] if mine else "",
        "name": str((found or {}).get("name", "")) if mine else "",
        "account_cinema": found["slug"] if found is not None else "",
        # When it's being deleted (P15.0): {"asked_at", "due"}, else None.
        "deleting": deletion_of(me) if mine else None
    };
}
