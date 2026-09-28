"""Tenant slugs: the cinema's subdomain and storefront selector (ADR-0006).

A slug is 3-40 characters of lowercase ascii letters, digits and single hyphens (not
at either end), and not a reserved platform name. Input is trimmed and lower-cased
first, so "Nova" and "nova" are the same slug.
"""

import re;

glob SLUG_MIN: int = 3,
     SLUG_MAX: int = 40,
     _CHARSET: str = r"^[a-z0-9-]+$",
     # Names the platform itself uses, or that would mislead customers as a cinema.
     RESERVED_SLUGS: set[str] = {
         "admin",
         "africinemas",
         "api",
         "app",
         "assets",
         "auth",
         "billing",
         "blog",
         "cdn",
         "dashboard",
         "dev",
         "docs",
         "help",
         "login",
         "logout",
         "mail",
         "platform",
         "register",
         "root",
         "signup",
         "staging",
         "static",
         "status",
         "support",
         "system",
         "test",
         "www"
     };

class InvalidSlug(ValueError) {
    def init(self: InvalidSlug, reason: str, message: str) {
        super.init(message);
        self.reason = reason;
    }
}

def normalize_slug(raw: str) -> str {
    return raw.strip().lower();
}

def validate_slug(raw: str) -> str {
    slug = normalize_slug(raw);
    if not SLUG_MIN <= len(slug) <= SLUG_MAX {
        raise InvalidSlug(
            "length", f"A slug must be {SLUG_MIN} to {SLUG_MAX} characters long."
        );
    }
    if re.fullmatch(_CHARSET, slug) is None {
        raise InvalidSlug(
            "charset", "Use only lowercase letters (a-z), digits and hyphens."
        );
    }
    if slug.startswith("-") or slug.endswith("-") or "--" in slug {
        raise InvalidSlug(
            "hyphen", "A hyphen can't start or end the slug, or follow another hyphen."
        );
    }
    if slug in RESERVED_SLUGS {
        raise InvalidSlug("reserved", f"'{slug}' is reserved. Choose another name.");
    }
    return slug;
}
