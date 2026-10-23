"""P14.3b: a cinema's policies, checked as plain logic (core/catalog/policies.jac)."""

import from core.catalog.policies {
    KINDS,
    REQUIRED,
    template_for,
    clean_text,
    title_of,
    missing_from
}

test "every policy has a template, with the cinema's name and contact filled in" {
    info = {
        "business_name": "Anga Cinemas Ltd",
        "email": "hello@anga.example",
        "phone": ""
    };
    for (kind, title) in KINDS {
        text = template_for(kind, "Anga", info);
        assert text , kind;
        assert "Anga Cinemas Ltd" in text , kind;
        assert "{" not in text and "}" not in text , kind;
        assert title_of(kind) == title;
    }
    assert "hello@anga.example" in template_for("refunds", "Anga", info);
    assert "Data Protection Act, 2019" in template_for("privacy", "Anga", info);
    for rating in ["GE", "PG", "16", "18"] {
        assert rating in template_for("age_ratings", "Anga", info);
    }
    # Without contact details, the templates point to the footer's.
    assert "bottom of this page" in template_for("terms", "Anga", {});
    assert REQUIRED == ["terms", "privacy", "refunds"];
    assert template_for("nope", "Anga", info) == "";
}

test "text is kept as typed, without control characters or Windows line ends" {
    assert clean_text("  ## Rules\r\n\r\n- No\x07 food\r\n\n")
        == "## Rules\n\n- No food";
    assert clean_text(None) == "";
    assert clean_text("Tabs\tstay") == "Tabs\tstay";
}

test "the required policies not yet published are named, for the review" {
    assert missing_from({}) == ["terms", "privacy", "refunds"];
    kept = {
        "terms": {"text": "Ours.", "published": True},
        "privacy": {"text": "Draft.", "published": False},
        "house_rules": {"text": "Ours.", "published": True}
    };
    assert missing_from(kept) == ["privacy", "refunds"];
}
