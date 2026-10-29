"""P15.0: verification files are sealed at rest, and owners hear when they're viewed or
changed (DPIA R1, R4).

verifying_app (tests/support/verification_setup.jac), with the development outbox.
- An uploaded ID photo is stored sealed ("ACF1", not the image's own bytes); the owner
  and the reviewer still get the image.
- Saving the details, uploading or submitting emails each owner "changed", at most
  once an hour; a reviewer opening a document emails "viewed", once, however many
  they open.
- Without the files' secret, uploading is refused, and nothing is stored.
"""

import os;
import base64;
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of }
import from tests.support.platform_setup { super_admin, join_platform }
import from tests.support.verification_setup {
    verifying_app,
    close_app,
    submitted,
    upload_file,
    png_base64,
    KIM
}

def _notices(app: Served) -> list[str] {
    # The subjects of the notices sent to Kim, now.
    app.call("owner", "t_send_verification_notices");
    return [
        m["subject"]
        for m in app.call("owner", "tm_outbox")
        if m["to"] == KIM and "verification" in m["subject"]
    ];
}

test "verification files are sealed at rest, and owners hear of views and changes" {
    app = verifying_app();
    try {
        app.call("owner", "tm_clear_outbox");
        # Stored sealed, read back as the image.
        assert upload_file(app, "id_front", "image/png", png_base64())["ok"];
        stored = app.call(
            "owner", "t_stored_verification_file", {"slug": "kims", "item": "id_front"}
        );
        assert stored.startswith(b"ACF1".hex()) , stored;
        assert b"RIFF".hex() not in stored and b"\\x89PNG".hex() not in stored;
        mine = app.call(
            "kim", "verification_file", {"tenant": "kims", "item": "id_front"}
        );
        assert mine["ok"] and base64.b64decode(mine["file"])[:4] == b"RIFF" , mine[
            "type"
        ];
        # Without the secret, uploading is refused.
        sealing = os.environ.pop("AFRICINEMAS_FILES_KEY");
        try {
            refused = upload_file(app, "id_back", "image/png", png_base64());
            assert code_of(refused) == "uploads_unavailable" , refused;
        } finally {
            os.environ["AFRICINEMAS_FILES_KEY"] = sealing;
        }
        # Changed: one email, however many changes in the hour.
        assert _notices(app) == ["Kim's Cinema: your verification details changed"];
        assert upload_file(app, "id_back", "image/png", png_base64())["ok"];
        submitted(app);
        assert len(_notices(app)) == 1;
        # A reviewer opens two documents: one "viewed" email.
        super_admin(app, "boss", "boss@example.com");
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": "checker@example.com", "role": "reviewer"}
        );
        join_platform(app, "checker", invited["token"]);
        for item in ["id_front", "county_permit"] {
            seen = app.call(
                "checker", "platform_review_file", {"slug": "kims", "item": item}
            );
            assert seen["ok"] , seen;
        }
        assert base64.b64decode(
            app.call(
                "checker", "platform_review_file", {"slug": "kims", "item": "id_front"}
            )["file"]
        )[:4]
            == b"RIFF";
        subjects = _notices(app);
        assert subjects.count(
            "Kim's Cinema: AfriCinemas opened your verification documents"
        )
            == 1 , subjects;
    } finally {
        close_app(app);
    }
}
