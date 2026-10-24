"""P14.5: a cinema's own text can't imitate the Verified badge."""

import from core.tenancy.reserved_words { name_claims, text_claims }

test "names can't use 'verified' or 'AfriCinemas'" {
    for name in [
        "Verified Cinemas",
        "Anga (verified)",
        "AfriCinemas Westgate",
        "Afri-Cinemas",
        "afri cinemas"
    ] {
        assert name_claims(name) , name;
    }
    for name in [
        "Anga Cinemas",
        "Nova Cinemas Ltd",
        "Kenya Film Hub",
        "Africa Cinema Club"
    ] {
        assert not name_claims(name) , name;
    }
}

test "longer text can't claim the badge, but may mention AfriCinemas" {
    for text in [
        "We are a Verified cinema!",
        "Verified by AfriCinemas since 2024.",
        "AfriCinemas verified us.",
        "✓ Verified",
        "Officially verified."
    ] {
        assert text_claims(text) , text;
    }
    for text in [
        "Our ticketing provider, AfriCinemas, runs this website for us.",
        "Your booking is confirmed once payment succeeds.",
        "IDs are verified at the door for 18 films.",
        "Tickets are verified on entry, and IDs verified by our staff."
    ] {
        assert not text_claims(text) , text;
    }
}
