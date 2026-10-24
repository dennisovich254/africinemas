"""P14.4: the owner's and the business's details, checked, then submitted for review.

In-process app (payment_app.jac) with the development outbox. Kim, whose email is
confirmed, owns Kim's Cinema (not yet live). Kim fills the details (every problem
reported at once, the KRA PIN's format checked), uploads the ID photos and the
certificates (each checked and rebuilt), and sees what's still missing. Submitting
needs everything, the go-live essentials and the required policies; it moves the
cinema to ready_for_go_live, and nothing can be changed until a reviewer answers.
Staff and other cinemas can't see any of it, and no file is reachable without signing
in as the owner.
"""

import base64;
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, browse }
import from tests.support.verification_setup {
    DETAILS,
    KIM,
    verifying_app,
    close_app,
    upload_file,
    png_base64,
    pdf_base64,
    sign_up_with_email
}

test "the owner fills the details and uploads the documents, checked on the server" {
    app = verifying_app();
    try {
        fresh = app.call("kim", "verification", {"tenant": "kims"});
        assert fresh["status"] == "draft" and fresh["editable"] , fresh;
        assert len(fresh["missing"]) == 14 , fresh["missing"];
        refused = app.call(
            "kim",
            "save_verification",
            {
                "tenant": "kims",
                "details": {
                    ** DETAILS,
                    "kra_pin": "123",
                    "phone": "12",
                    "id_number": "x"
                }
            }
        );
        assert code_of(refused) == "invalid_details" , refused;
        fields = sorted([p["field"] for p in refused["error"]["problems"]]);
        assert fields == ["id_number", "kra_pin", "phone"] , fields;
        saved = app.call(
            "kim", "save_verification", {"tenant": "kims", "details": DETAILS}
        );
        assert saved["ok"] , saved;
        assert saved["details"]["kra_pin"] == "P051234567Q";
        assert saved["details"]["phone"] == "+254712345678";
        assert code_of(
            upload_file(
                app, "id_front", "image/png", base64.b64encode(b"nope").decode()
            )
        )
            == "wrong_type";
        assert code_of(upload_file(app, "id_front", "text/plain", png_base64()))
            == "wrong_type";
        assert code_of(upload_file(app, "nope", "image/png", png_base64()))
            == "unknown_item";
        shown = upload_file(app, "id_front", "image/png", png_base64());
        assert shown["ok"] and shown["files"]["id_front"]["type"] == "image" , shown;
        mine = app.call(
            "kim", "verification_file", {"tenant": "kims", "item": "id_front"}
        );
        assert mine["type"] == "image"
            and base64.b64decode(mine["file"])[:4] == b"RIFF";
        # Staff and other cinemas see none of it.
        for who in ["usher", "rival"] {
            for (name, body) in [
                ("verification", {"tenant": "kims"}),
                ("verification_file", {"tenant": "kims", "item": "id_front"}),
                ("save_verification", {"tenant": "kims", "details": DETAILS})
            ] {
                assert code_of(app.call(who, name, body))
                    in ["forbidden", "not_found"] , f"{who} {name}";
            }
        }
        # An owner whose email isn't confirmed can't submit, whatever the page sends.
        sign_up_with_email(app, "lee", "lee@example.com");
        app.call("lee", "create_cinema", {"name": "Lee's", "slug": "lees"});
        app.call("lee", "start_shift", {"tenant": "lees"});
        assert not app.call("lee", "verification", {"tenant": "lees"})[
            "email_confirmed"
        ];
        assert code_of(app.call("lee", "submit_verification", {"tenant": "lees"}))
            == "email_unverified";
        assert app.call("kim", "verification", {"tenant": "kims"})["email_confirmed"];
        logged = [
            e["action"]
            for e in app.call("kim", "audit_log", {"tenant": "kims", "limit": 10})[
                "events"
            ]
        ];
        assert "verification.saved" in logged
            and "verification.file_uploaded" in logged , logged;
    } finally {
        close_app(app);
    }
}

test "submitting needs everything and the essentials, then waits for the review" {
    app = verifying_app();
    try {
        app.call("kim", "save_verification", {"tenant": "kims", "details": DETAILS});
        for item in ["id_front", "id_back"] {
            assert upload_file(app, item, "image/png", png_base64())["ok"];
        }
        early = app.call("kim", "submit_verification", {"tenant": "kims"});
        assert code_of(early) == "not_ready" , early;
        assert sorted([m["field"] for m in early["error"]["missing"]])
            == ["county_permit", "kra_certificate", "registration_certificate"];
        assert sorted([e["field"] for e in early["error"]["essentials"]])
            == ["policies", "policies", "policies"];
        for item in ["registration_certificate", "kra_certificate", "county_permit"] {
            assert upload_file(app, item, "application/pdf", pdf_base64())["ok"];
        }
        for kind in ["terms", "privacy", "refunds"] {
            assert app.call(
                "kim",
                "save_policy",
                {
                    "tenant": "kims",
                    "kind": kind,
                    "text": "Ours.",
                    "published": True,
                    "reviewed": True
                }
            )["ok"];
        }
        done = app.call("kim", "submit_verification", {"tenant": "kims"});
        assert done["ok"] , done;
        assert done["status"] == "submitted"
            and done["state"] == "ready_for_go_live"
            and not done["editable"];
        assert code_of(
            app.call("kim", "save_verification", {"tenant": "kims", "details": DETAILS})
        )
            == "under_review";
        assert code_of(upload_file(app, "id_front", "image/png", png_base64()))
            == "under_review";
        # Still not public: submitted isn't approved.
        assert code_of(browse(app, "public_branding", {"slug": "kims"})) == "not_found";
        # A tenant admin sets the cinema up, but isn't its owner.
        assert code_of(app.call("owner", "verification", {"tenant": "kims"}))
            == "not_found";
    } finally {
        close_app(app);
    }
}
