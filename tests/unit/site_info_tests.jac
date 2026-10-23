"""P14.3a: a cinema's public information, checked as plain logic (core/catalog/site_info.jac)."""

import from core.catalog.site_info { parse_info, public_view, kenyan_number }

test "Kenyan numbers are kept one way, and anything else is refused" {
    assert kenyan_number("0712 345 678") == "+254712345678";
    assert kenyan_number("+254 712-345-678") == "+254712345678";
    assert kenyan_number("254112345678") == "+254112345678";
    assert kenyan_number("0201234567") == "";
    assert kenyan_number("12345") == "";
}

test "the information is kept as plain text, and every problem is reported at once" {
    (info, problems) = parse_info(
        {
            "business_name": "  Anga   Cinemas  Ltd ",
            "phone": "0712345678",
            "whatsapp": "nope",
            "email": "Hello@Anga.co.ke",
            "support_hours": "<b>9 to 5</b>",
            "socials": {
                "instagram": "@anga_cinemas",
                "facebook": "https://facebook.com/anga"
            },
            "ticket_notes": [
                {"name": "Child", "note": "Under 12."},
                {"name": "Student", "note": ""}
            ]
        }
    );
    assert info["business_name"] == "Anga Cinemas Ltd";
    assert info["phone"] == "+254712345678" and info["email"] == "hello@anga.co.ke";
    assert info["socials"]["instagram"] == "anga_cinemas";
    assert info["ticket_notes"] == [{"name": "Child", "note": "Under 12."}];
    found = sorted([(p.field, p.code) for p in problems]);
    assert found
        == [
            ("socials.facebook", "invalid_handle"),
            ("support_hours", "markup"),
            ("ticket_notes.1", "incomplete"),
            ("whatsapp", "invalid_phone")
        ] , found;
}

test "the storefront gets links built from what was typed, never the text itself" {
    (info, problems) = parse_info(
        {"whatsapp": "0712 345 678", "socials": {"tiktok": "anga", "x": "anga_ke"}}
    );
    assert problems == [];
    shown = public_view(info);
    assert shown["whatsapp_url"] == "https://wa.me/254712345678";
    assert [(s["network"], s["url"]) for s in shown["socials"]]
        == [("x", "https://x.com/anga_ke"), ("tiktok", "https://www.tiktok.com/@anga")];
}
