"""P14.5b: personal files are deleted when the retention rules say, and nothing else.

In-process app (payment_app.jac). Kim's cinema is verified, and Kim asked for help with
a screenshot, since closed. The job, run as of later dates (t_retention):
- 10 days on, nothing is due;
- 91 days on, the ID photos and the screenshot go; the certificates and the written
  conversation stay;
- once the cinema closes, its certificates go a year on; running again finds nothing.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of }
import from tests.support.platform_setup { super_admin }
import from tests.support.verification_setup {
    verifying_app,
    close_app,
    submitted,
    png_base64
}

def _file(app: Served, item: str) -> str {
    # "" if Kim can still open the file, else the refusal's code.
    return code_of(
        app.call("kim", "verification_file", {"tenant": "kims", "item": item})
    );
}

test "ID photos and screenshots go after 90 days, business documents a year after closing" {
    app = verifying_app();
    try {
        super_admin(app, "boss", "boss@example.com");
        submitted(app);
        asked = app.call(
            "kim",
            "ask_for_help",
            {
                "tenant": "kims",
                "category": "storefront",
                "text": "The poster looks wrong.",
                "image_type": "image/png",
                "image_base64": png_base64()
            }
        );
        assert asked["ok"] , asked;
        request_id = asked["request"]["request_id"];
        assert app.call(
            "boss",
            "platform_support_status",
            {"request_id": request_id, "status": "closed"}
        )["ok"];
        assert app.call(
            "boss",
            "platform_decide",
            {"slug": "kims", "decision": "approve", "reasons": []}
        )["ok"];
        # Verified, it says so in listings too (once it has showtimes on sale).
        assert app.call("kim", "my_access", {"tenant": "kims"})["verified_at"];
        nothing = {"id_photos": 0, "business_documents": 0, "screenshots": 0};
        assert app.call("owner", "t_retention", {"days_ahead": "10"}) == nothing;
        assert _file(app, "id_front") == "";
        due = app.call("owner", "t_retention", {"days_ahead": "91"});
        assert due == {"id_photos": 2, "business_documents": 0, "screenshots": 1} , due;
        for item in ["id_front", "id_back"] {
            assert _file(app, item) == "no_file" , item;
        }
        for item in ["registration_certificate", "kra_certificate", "county_permit"] {
            assert _file(app, item) == "" , item;
        }
        # The record that the ID was checked stays, with when the photos went.
        page = app.call("boss", "platform_review", {"slug": "kims"});
        assert page["status"] == "approved"
            and page["reviewed_by"] == "boss@example.com";
        removed = {f["item"]: f["removed_at"] for f in page["files"]};
        assert removed["id_front"] and not removed["county_permit"] , removed;
        # The conversation stays; its screenshot doesn't.
        mine = app.call("kim", "support_requests", {"tenant": "kims"})["requests"][0];
        first = mine["messages"][0];
        assert first["text"] == "The poster looks wrong." and not first["has_image"];
        assert first["image_removed_at"];
        # A year after the cinema starts closing, its business documents go too.
        assert app.call("owner", "t_close_cinema", {"slug": "kims"});
        assert app.call("owner", "t_retention", {"days_ahead": "300"}) == nothing;
        late = app.call("owner", "t_retention", {"days_ahead": "366"});
        assert late
            == {"id_photos": 0, "business_documents": 3, "screenshots": 0} , late;
        assert app.call("owner", "t_retention", {"days_ahead": "400"}) == nothing;
    } finally {
        close_app(app);
    }
}
