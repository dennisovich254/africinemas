"""P14.3a: a cinema's public information, saved in the back office and shown to everyone.

In-process app (payment_app.jac). Nova's owner saves its business name, contact,
WhatsApp, social media, directions and booking notes; anyone reading the storefront
gets them, with links built from what was typed. A save with problems is refused with
every problem. Only staff who change the cinema's settings may save; another cinema's
staff find nothing. Each save is in the cinema's audit log.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, browse }
import from tests.support.payment_setup { paying_cinema, hire }

glob INFO: dict[str, any] = {  # jac:ignore[W1037]
         "business_name": "Nova Cinemas Ltd",
         "address": "Westgate Mall, Mwanzi Road, Nairobi",
         "phone": "0712 345 678",
         "email": "hello@nova.example",
         "whatsapp": "0798 765 432",
         "support_hours": "Every day, 9am to 10pm",
         "socials": {"instagram": "@nova_cinemas", "tiktok": "nova"},
         "directions": "Third floor, by the food court.",
         "parking": "Free for two hours with a ticket.",
         "ticket_notes": [{"name": "Child", "note": "Under 12."}],
         "payment_note": "Pay with M-Pesa online, or cash at the box office."
     };

def _app -> Served {
    (app, nova, _) = paying_cinema(["usher", "rival"]);
    hire(app, "usher", "usher", nova.venue);
    app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
    return app;
}

test "the owner saves the cinema's information, and every storefront visitor sees it" {
    app = _app();
    try {
        assert app.call("owner", "site_info", {"tenant": "nova"})["info"][
            "business_name"
        ]
            == "";
        saved = app.call("owner", "save_site_info", {"tenant": "nova", "info": INFO});
        assert saved["ok"] , saved;
        assert saved["info"]["phone"] == "+254712345678";
        assert app.call("owner", "site_info", {"tenant": "nova"})["info"]["socials"][
            "instagram"
        ]
            == "nova_cinemas";
        shown = browse(app, "public_branding", {"slug": "nova"})["info"];
        assert shown["business_name"] == "Nova Cinemas Ltd" , shown;
        assert shown["whatsapp_url"] == "https://wa.me/254798765432";
        assert [s["url"] for s in shown["socials"]]
            == [
                "https://www.instagram.com/nova_cinemas",
                "https://www.tiktok.com/@nova"
            ];
        assert shown["ticket_notes"] == [{"name": "Child", "note": "Under 12."}];
        logged = app.call("owner", "audit_log", {"tenant": "nova", "limit": 10});
        assert "site_info.saved" in [e["action"] for e in logged["events"]];
    } finally {
        app.close();
    }
}

test "a save with problems is refused with all of them, and only settings staff may save" {
    app = _app();
    try {
        refused = app.call(
            "owner",
            "save_site_info",
            {
                "tenant": "nova",
                "info": {"phone": "12", "email": "nope", "parking": "<i>x</i>"}
            }
        );
        assert code_of(refused) == "invalid_info" , refused;
        fields = sorted([p["field"] for p in refused["error"]["problems"]]);
        assert fields == ["email", "parking", "phone"] , fields;
        assert code_of(
            app.call("usher", "save_site_info", {"tenant": "nova", "info": INFO})
        )
            == "forbidden";
        assert code_of(
            app.call("rival", "save_site_info", {"tenant": "nova", "info": INFO})
        )
            == "not_found";
        assert code_of(app.call("rival", "site_info", {"tenant": "nova"}))
            == "not_found";
    } finally {
        app.close();
    }
}
