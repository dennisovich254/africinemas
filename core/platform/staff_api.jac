"""AfriCinemas platform staff and their roles (P13.1; ADR-0055). Endpoints listed in
tests/isolation/registry.jac with the "platform" scope (the "caller" one for
platform_whoami).

Platform staff run the platform, apart from every cinema's staff and customers:
- **Super admins** are the verified emails in AFRICINEMAS_PLATFORM_ADMINS (comma
  separated, read on every request). Nobody can become one through the app, and they
  can't be removed through it.
- **Reviewers** (verification decisions, Phase 14) and **support** (technical support,
  13.5) are added and removed by a super admin, kept as permanent claims (STAFF: email
  -> role). Removing someone takes effect on their next request.
- **More super admins** can be made in the console, but only by a super admin from the
  server's settings (owner decision, 2026-10-22), who alone may also change or remove
  them: a super admin made in the app can't make others.

Who's calling: a request carries only the caller's root, and Jac's identity store maps
people to roots, not back. platform_whoami takes the email the browser signed in with,
keeps it only if it's the caller's own (core/tenancy/identity.jac), and links the root
to it (MEMBERS: root -> email). Every platform endpoint then finds the caller's email
from their root and their role from the allowlist or STAFF, fresh each time. A cinema's
customer account signs in with a username, never an email, so it can't be platform
staff.

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
import from core.tenancy.identity { verified_sign_in }
import from core.tenancy.principal { node_id }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { platform_audited }

glob ADMINS_ENV: str = "AFRICINEMAS_PLATFORM_ADMINS",
     STAFF: str = "platform-staff",
     MEMBERS: str = "platform-member",
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
     # A staff sign-in name (an email in the web app). A customer's username has ":"
     # in it ("<slug>:<local>:<domain>", P8.6c), so it can never be added.
     SIGN_IN_PATTERN: str = r"[A-Za-z0-9._+@-]{1,254}";

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
    email = holder(MEMBERS, me) or "";
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

def _whoami(email: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The caller's platform role, linking their root to their own verified email.
    mine = verified_sign_in(email);
    role = role_of_email(mine);
    if not role {
        return {"ok": True, "platform": False};
    }
    me = node_id(root);
    if holder(MEMBERS, me) != mine {
        take_claim(MEMBERS, me);
        claim(MEMBERS, me, mine);
    }
    return {
        "ok": True,
        "platform": True,
        "email": mine,
        "role": role,
        "role_label": ROLE_LABELS[role],
        "permissions": sorted(PLATFORM_PERMISSIONS[role]),
        # Set in the server's settings: may make, change and remove super admins.
        "settings_admin": mine in allowlisted()
    };
}

def _row(email: str, role: str, fixed: bool) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "email": email,
        "role": role,
        "role_label": ROLE_LABELS[role],
        "fixed": fixed
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
    if not re.fullmatch(SIGN_IN_PATTERN, clean) {
        raise Refused(
            "invalid_email", "Enter an email address, like name@example.com."
        );
    }
    return clean;
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

def _set_role(email: str, role: str, me: PlatformCaller) -> dict[str, any] {  # jac:ignore[W1037]
    clean = _tidy_email(email);
    if role not in ROLES {
        raise Refused("invalid_role", "Choose super admin, reviewer or support.");
    }
    if clean in allowlisted() {
        raise _not_allowed();
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
    return _staff_list();
}

def:protect platform_whoami(email: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _whoami(email); });  # jac:ignore[W1037]
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
