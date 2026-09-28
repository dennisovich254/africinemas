"""P2.1: tenant slug validation (charset, length, reserved words).

A slug becomes the cinema's subdomain (nova.africinemas.co.ke) and its storefront
selector (ADR-0006), so it must be DNS-safe, readable and never collide with a
platform name.
"""

import from core.tenancy.slugs {
    InvalidSlug,
    SLUG_MIN,
    SLUG_MAX,
    RESERVED_SLUGS,
    validate_slug
}

def _reason(raw: str) -> str {
    try {
        validate_slug(raw);
    } except InvalidSlug as e {
        return e.reason;
    }
    return "accepted";
}

test "ordinary cinema names are accepted as they are" {
    for slug in ["nova", "imax-rift", "cinema-254", "abc", "a" * SLUG_MAX] {
        assert validate_slug(slug) == slug , slug;
    }
}

test "input is trimmed and lower-cased before checking" {
    assert validate_slug("  Nova-Cinemas ") == "nova-cinemas";
}

test "length is limited both ways" {
    assert SLUG_MIN == 3 and SLUG_MAX == 40;
    assert _reason("ab") == "length";
    assert _reason("a" * (SLUG_MAX + 1)) == "length";
    assert _reason("") == "length";
}

test "only lowercase ascii letters, digits and hyphens are allowed" {
    for bad in ["nová", "nova_1", "nova.ke", "nova cinema", "nova!", "ñova"] {
        assert _reason(bad) == "charset" , bad;
    }
}

test "hyphens can't lead, trail or repeat" {
    for bad in ["-nova", "nova-", "no--va"] {
        assert _reason(bad) == "hyphen" , bad;
    }
}

test "platform and infrastructure names are reserved" {
    for name in [
        "www",
        "api",
        "admin",
        "app",
        "static",
        "auth",
        "africinemas",
        "support"
    ] {
        assert name in RESERVED_SLUGS , name;
        assert _reason(name) == "reserved" , name;
    }
    assert _reason("Admin") == "reserved" , "reserved words are checked after lower-casing";
}

test "the error carries a readable message as well as the reason code" {
    try {
        validate_slug("no--va");
        assert False , "should have raised";
    } except InvalidSlug as e {
        assert e.reason == "hyphen";
        assert "hyphen" in str(e).lower();
    }
}
