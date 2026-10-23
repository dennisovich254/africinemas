"""AfriCinemas platform staff and their roles (P13.1; ADR-0055). Endpoints listed in
tests/isolation/registry.jac with the "platform" scope (the "caller" one for
platform_whoami).

Platform staff run the platform, apart from every cinema's staff and customers:
- **Super admins** are the verified emails in AFRICINEMAS_PLATFORM_ADMINS (comma
  separated, read on every request). Nobody can become one through the app, and they
  can't be removed through it.
- **Reviewers** (verification decisions, Phase 14) and **support** (technical support,
  13.5) are invited and removed by a super admin, kept as permanent claims (STAFF: email
  -> role). Removing someone takes effect on their next request, and their unused
  invitation stops working.
- **More super admins** can be made in the console, but only by a super admin from the
  server's settings (owner decision, 2026-10-22), who alone may also change or remove
  them: a super admin made in the app can't make others.

Platform accounts (P13.1b.a, core/platform/accounts.jac): platform staff sign in with
an account of their own, never a cinema's. There's no sign-up: a super admin invites
someone (invite_platform_member, a link valid 72 hours), the settings' super admins get
a link from scripts/platform_setup.jac, and platform_join sets the password from the
link, making the account the first time. Every platform endpoint finds the caller's
email from the account their root belongs to, and their role from the allowlist or
STAFF, fresh each time: a cinema's staff or customer account is never platform staff,
whatever its email.

Refusals: not_platform ("This area is for AfriCinemas staff.") for anyone who isn't
platform staff, the same whatever they ask; not_allowed ("Your platform role can't do
this.") for anything else the caller may not do, including touching a super admin, never
saying which rule stopped them or which super admins come from the settings. Only the
settings' super admins see which accounts are the settings' (`fixed`).
Every change is recorded in the platform's own audit log (core/audit/log.jac).
"""

import os;
import re;
import from core.claims { claim, holder, take_claim, claims_in }
import from jaclang.server.identity.policy { check_password, refusal }
import from core.tenancy.principal { node_id }
import from core.tenancy.storefront_accounts {
    EMAIL_SHAPE,
    PASSWORD_MIN,
    PASSWORD_MAX,
    password_advice
}
import from core.platform.accounts {
    sign_in_name,
    users,
    account_email,
    has_account,
    record_account,
    join_link,
    peek_join,
    use_join,
    cancel_joins,
    INVITE_TTL_S
}
import from core.catalog.answers { Refused, answer }
import from core.audit.log { platform_audited }

glob ADMINS_ENV: str = "AFRICINEMAS_PLATFORM_ADMINS",
     STAFF: str = "platform-staff",
     SUPER_ADMIN: str = "super_admin",
     REVIEWER: str = "reviewer",
     SUPPORT: str = "support",
     ROLES: list[str] = ["super_admin", "reviewer", "support"],
     ROLE_LABELS: dict[str, str] = {
         "super_admin": "Super admin",
         "reviewer": "Reviewer",
         "support": "Support"
     },
     # What each role may do. platform.read: the console; .staff: platform staff;
     # .review: verification decisions; .suspend: suspend and reinstate cinemas;
     # .support: technical support; .settings: platform settings (the fee, brands).
     PLATFORM_PERMISSIONS: dict[str, set[str]] = {
         "super_admin": {
             "platform.read",
             "platform.staff",
             "platform.review",
             "platform.suspend",
             "platform.support",
             "platform.settings"
         },
         "reviewer": {"platform.read", "platform.review", "platform.suspend"},
         "support": {"platform.read", "platform.support"}
     },
     INVALID_JOIN: str = "This link has expired or was already used. Ask a super admin for a new one.";

obj PlatformCaller {
    # Who's calling the platform: their root, email and role.
    has root_id: str,
        email: str,
        role: str;
}

def allowlisted -> list[str] {
    # The super admins' emails from AFRICINEMAS_PLATFORM_ADMINS, tidied.
    raw = os.environ.get(ADMINS_ENV, "");
    return [
        e.strip().lower()
        for e in raw.split(",")
        if e.strip()
    ];
}

def role_of_email(email: str) -> str {
    # The platform role of an email: super admin when allowlisted, else as added; "".
    if not email {
        return "";
    }
    if email in allowlisted() {
        return SUPER_ADMIN;
    }
    found = holder(STAFF, email);
    return found if found in ROLES else "";
}

def caller -> PlatformCaller | None {
    # The caller as platform staff, or None.
    me = node_id(root);
    email = account_email(me);
    role = role_of_email(email);
    if not role {
        return None;
    }
    return PlatformCaller(root_id=me, email=email, role=role);
}

def _not_allowed -> Refused {
    # The one refusal for anything a platform member may not do: it never says why.
    return Refused("not_allowed", "Your platform role can't do this.");
}

def require_platform(permission: str) -> PlatformCaller {
    # The caller, if they're platform staff whose role allows `permission`.
    found = caller();
    if found is None {
        raise Refused("not_platform", "This area is for AfriCinemas staff.");
    }
    if permission not in PLATFORM_PERMISSIONS[found.role] {
        raise _not_allowed();
    }
    return found;
}

def _whoami -> dict[str, any] {  # jac:ignore[W1037]
    # The caller's platform role, from the platform account they signed in with.
    found = caller();
    if found is None {
        return {"ok": True, "platform": False};
    }
    return {
        "ok": True,
        "platform": True,
        "email": found.email,
        "role": found.role,
        "role_label": ROLE_LABELS[found.role],
        "permissions": sorted(PLATFORM_PERMISSIONS[found.role]),
        # Set in the server's settings: may make, change and remove super admins.
        "settings_admin": found.email in allowlisted()
    };
}

def _row(email: str, role: str, fixed: bool) -> dict[str, any] {  # jac:ignore[W1037]
    # `joined`: they've set their password; until then they're invited.
    return {
        "email": email,
        "role": role,
        "role_label": ROLE_LABELS[role],
        "fixed": fixed,
        "joined": has_account(email)
    };
}

def _staff_list -> dict[str, any] {  # jac:ignore[W1037]
    me = require_platform("platform.staff");
    fixed = allowlisted();
    # Which super admins are the settings' is shown to the settings' own only.
    shown = me.email in fixed;
    rows: list[dict[str, any]] = [_row(e, SUPER_ADMIN, shown) for e in fixed];  # jac:ignore[W1037]
    for (email, role, _) in claims_in(STAFF) {
        if email not in fixed and role in ROLES {
            rows.append(_row(email, role, False));
        }
    }
    return {"ok": True, "staff": rows};
}

def _tidy_email(email: str) -> str {
    clean = email.strip().lower() if isinstance(email, str) else "";
    if not re.fullmatch(EMAIL_SHAPE, clean) {
        raise Refused(
            "invalid_email", "Enter an email address, like name@example.com."
        );
    }
    return clean;
}

def _check_role(role: str) {
    if role not in ROLES {
        raise Refused("invalid_role", "Choose super admin, reviewer or support.");
    }
}

def _check_super_admins(clean: str, role: str, me: PlatformCaller) {
    # Making, changing or removing a super admin is for super admins from the server's
    # settings only.
    if me.email in allowlisted() {
        return;
    }
    if role == SUPER_ADMIN or holder(STAFF, clean) == SUPER_ADMIN {
        raise _not_allowed();
    }
}

def _invite(email: str, role: str, me: PlatformCaller) -> dict[str, any] {  # jac:ignore[W1037]
    # Adds `email` with `role` and makes their join link. Someone who has joined can't
    # be invited again: a link sets the password, so it would take over their account.
    clean = _tidy_email(email);
    _check_role(role);
    if clean in allowlisted() {
        raise _not_allowed();
    }
    _check_super_admins(clean, role, me);
    if has_account(clean) {
        raise Refused("already_staff", "That person is already platform staff.");
    }
    take_claim(STAFF, clean);
    claim(STAFF, clean, role);
    token = join_link(clean, INVITE_TTL_S);
    listed = _staff_list();
    listed["token"] = token;
    listed["expires_in_hours"] = INVITE_TTL_S // 3600;
    return listed;
}

def _set_role(email: str, role: str, me: PlatformCaller) -> dict[str, any] {  # jac:ignore[W1037]
    clean = _tidy_email(email);
    _check_role(role);
    if clean in allowlisted() {
        raise _not_allowed();
    }
    if holder(STAFF, clean) is None {
        raise Refused("not_staff", "That email isn't platform staff.");
    }
    _check_super_admins(clean, role, me);
    take_claim(STAFF, clean);
    claim(STAFF, clean, role);
    return _staff_list();
}

def _remove(email: str, me: PlatformCaller) -> dict[str, any] {  # jac:ignore[W1037]
    clean = _tidy_email(email);
    if clean in allowlisted() {
        raise _not_allowed();
    }
    if clean == me.email {
        raise Refused("remove_self", "You can't remove yourself.");
    }
    if holder(STAFF, clean) is None {
        raise Refused("not_staff", "That email isn't platform staff.");
    }
    _check_super_admins(clean, "", me);
    take_claim(STAFF, clean);
    cancel_joins(clean);
    return _staff_list();
}

def _existing(email: str) -> str {
    # The user id of the platform account for `email`, or "". A name Jac's own sign-up
    # took is no one's platform account: it's removed, so nobody already signed in to
    # it gets the role.
    found: any = users().find_user_by_identity(sign_in_name(email));  # jac:ignore[W1037]
    if not found {
        return "";
    }
    user_id = str(found.get("user_id", ""));
    owner = str(found.get("root_id") or users().get_root_id(user_id) or "");
    if account_email(owner) == email {
        return user_id;
    }
    users().delete_user(user_id);
    return "";
}

def _password_refusal(email: str, password: str, user_id: str) -> str {
    # Why Jac's password rules refuse `password` for this account, or "".
    if not isinstance(password, str)
        or len(password) < PASSWORD_MIN
        or len(password) > PASSWORD_MAX {
        return f"Use a password of at least {PASSWORD_MIN} characters.";
    }
    found: any = None;  # jac:ignore[W1037]
    if user_id {
        found = users().password_refusal(user_id, password);
    } else {
        broken = check_password(password, [sign_in_name(email), email]);
        found = refusal(broken) if broken else None;
    }
    return password_advice(found.get("violations") or []) if found else "";
}

def _join(token: str, password: str) -> dict[str, any] {  # jac:ignore[W1037]
    # From a join link: sets the password of the platform account the link names,
    # making the account the first time. The link is spent only once the password is
    # good, so a weak one can be tried again.
    email = peek_join(token);
    # Someone removed after they were invited can't join.
    if not email or not role_of_email(email) {
        raise Refused("invalid_link", INVALID_JOIN);
    }
    user_id = _existing(email);
    advice = _password_refusal(email, password, user_id);
    if advice {
        raise Refused("weak_password", advice);
    }
    if not use_join(token) {
        raise Refused("invalid_link", INVALID_JOIN);
    }
    if user_id {
        users().reset_password_by_user_id(user_id, password);
    } else {
        made: dict[str, any] = users().create_user_with_identities(  # jac:ignore[W1037]
            identities=[{"type": "username", "value": sign_in_name(email)}],
            credential={"type": "password", "password": password}
        );
        if not made.get("root_id") {
            raise Refused("not_made", "We couldn't set up your account. Try again.");
        }
        record_account(str(made["root_id"]), email);
    }
    return {"ok": True, "sign_in_name": sign_in_name(email)};
}

def:protect platform_whoami -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_whoami);
}

def:pub platform_join(token: str, password: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A join link's page: the account's password; the page then signs in with
    # sign_in_name. Public: the person has no account until this makes it.
    named = peek_join(token);
    return platform_audited(
        node_id(root),
        named,
        "platform.joined",
        "platform_staff",
        named,
        lambda -> any { return _join(token, password); }  # jac:ignore[W1037]
    );
}

def:protect platform_staff -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_staff_list);
}

def:protect set_platform_role(email: str, role: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.staff");
    } except Refused as e {
        return answer(lambda -> any { raise e; });  # jac:ignore[W1037]
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.staff_role_set",
        "platform_staff",
        str(email).strip().lower(),
        lambda -> any { return _set_role(email, role, me); },  # jac:ignore[W1037]
        detail=str(role)
    );
}

def:protect remove_platform_staff(email: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.staff");
    } except Refused as e {
        return answer(lambda -> any { raise e; });  # jac:ignore[W1037]
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.staff_removed",
        "platform_staff",
        str(email).strip().lower(),
        lambda -> any { return _remove(email, me); }  # jac:ignore[W1037]
    );
}

def:protect invite_platform_member(email: str, role: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Adds someone to the platform staff; the answer carries their join link's token.
    try {
        me = require_platform("platform.staff");
    } except Refused as e {
        return answer(lambda -> any { raise e; });  # jac:ignore[W1037]
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.staff_invited",
        "platform_staff",
        str(email).strip().lower(),
        lambda -> any { return _invite(email, role, me); },  # jac:ignore[W1037]
        detail=str(role)
    );
}
