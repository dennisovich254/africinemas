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

import io;
import os;
import base64;
import tempfile;
import from PIL { Image }
import from pypdf { PdfWriter }
import from tests.support.served { Served, served }
import from tests.support.harness { Actor }
import from tests.support.storefront_setup {
    code_of,
    open_cinema_for,
    set_prices,
    browse
}
import from tests.support.payment_setup { APP }

glob PASSWORD: str = "Kim-Passw0rd!",
     KIM: str = "kim@example.com",
     DETAILS: dict[str, str] = {
         "legal_name": "Kimani Wanjiru",
         "id_number": "12345678",
         "phone": "0712 345 678",
         "registered_name": "Kim's Cinema Ltd",
         "business_type": "limited_company",
         "registration_number": "PVT-ABC123",
         "kra_pin": "p051234567q",
         "permit_expiry": "2099-12-31",
         "premises_address": "Rupas Mall, Eldoret"
     };

def _png -> str {
    out = io.BytesIO();
    Image.new("RGB", (900, 600), (40, 90, 160)).save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _pdf -> str {
    writer = PdfWriter();
    writer.add_blank_page(width=200, height=200);
    out = io.BytesIO();
    writer.write(out);
    return base64.b64encode(out.getvalue()).decode();
}

def _sign_up(app: Served, label: str, email: str) {
    # Signs up with an email identity, as the web form does, then signs in.
    app.client.set_auth_token("");
    made = app.client.post(
        "/user/register",
        json={
            "identities": [{"type": "email", "value": email}],
            "credential": {"type": "password", "password": PASSWORD}
        }
    );
    assert made.status_code in (200, 201) , made.text;
    login = app.client.post(
        "/user/login",
        json={
            "identity": {"type": "email", "value": email},
            "credential": {"type": "password", "password": PASSWORD}
        }
    );
    assert login.status_code == 200 , login.text;
    data: dict[str, any] = login.data or {};  # jac:ignore[W1037]
    app.actors[label] = Actor(
        username=email,
        user_id=str(data.get("user_id", "")),
        root_id=str(data.get("root_id", "")),
        token=str(data["token"])
    );
}

def _confirmed(app: Served) {
    # Kim follows the emailed link (P14.2).
    assert app.call("kim", "send_email_check", {"email": KIM})["ok"];
    app.call("owner", "t_send_email_checks");
    mails = [
        m
        for m in app.call("owner", "tm_outbox")
        if m["to"] == KIM
    ];
    token = mails[-1]["text"].split("/verify-email#", 1)[1].split()[0];
    assert browse(app, "confirm_email", {"token": token})["ok"];
}

def _app -> Served {
    os.environ["AFRICINEMAS_OUTBOX_DIR"] = tempfile.mkdtemp(
        prefix="africinemas-outbox-"
    );
    os.environ.pop("AFRICINEMAS_SMTP_HOST", None);
    app = served(APP, ["owner", "usher", "rival"]);
    _sign_up(app, "kim", KIM);
    _confirmed(app);
    kims = open_cinema_for(app, "kim", "kims", "Kim's Cinema", live=False);
    set_prices(app, "kim", kims);
    hire_usher(app, kims.venue);
    app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
    return app;
}

def hire_usher(app: Served, venue: str) {
    invited = app.call(
        "kim", "invite_staff", {"tenant": "kims", "role": "usher", "venue_id": venue}
    );
    assert app.call("usher", "accept_invite", {"token": invited["token"]})["ok"];
    assert app.call("usher", "start_shift", {"tenant": "kims"})["ok"];
}

def _close(app: Served) {
    os.environ.pop("AFRICINEMAS_OUTBOX_DIR", None);
    app.close();
}

def _upload(app: Served, item: str, content_type: str, data: str) -> any {  # jac:ignore[W1037]
    return app.call(
        "kim",
        "upload_verification_file",
        {
            "tenant": "kims",
            "item": item,
            "content_type": content_type,
            "data_base64": data
        }
    );
}

test "the owner fills the details and uploads the documents, checked on the server" {
    app = _app();
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
            _upload(app, "id_front", "image/png", base64.b64encode(b"nope").decode())
        )
            == "wrong_type";
        assert code_of(_upload(app, "id_front", "text/plain", _png())) == "wrong_type";
        assert code_of(_upload(app, "nope", "image/png", _png())) == "unknown_item";
        shown = _upload(app, "id_front", "image/png", _png());
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
        logged = [
            e["action"]
            for e in app.call("kim", "audit_log", {"tenant": "kims", "limit": 10})[
                "events"
            ]
        ];
        assert "verification.saved" in logged
            and "verification.file_uploaded" in logged , logged;
    } finally {
        _close(app);
    }
}

test "submitting needs everything and the essentials, then waits for the review" {
    app = _app();
    try {
        app.call("kim", "save_verification", {"tenant": "kims", "details": DETAILS});
        for item in ["id_front", "id_back"] {
            assert _upload(app, item, "image/png", _png())["ok"];
        }
        early = app.call(
            "kim", "submit_verification", {"tenant": "kims", "email": KIM}
        );
        assert code_of(early) == "not_ready" , early;
        assert sorted([m["field"] for m in early["error"]["missing"]])
            == ["county_permit", "kra_certificate", "registration_certificate"];
        assert sorted([e["field"] for e in early["error"]["essentials"]])
            == ["policies", "policies", "policies"];
        for item in ["registration_certificate", "kra_certificate", "county_permit"] {
            assert _upload(app, item, "application/pdf", _pdf())["ok"];
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
        # Only with the owner's own, confirmed email.
        assert code_of(
            app.call(
                "kim",
                "submit_verification",
                {"tenant": "kims", "email": "x@example.com"}
            )
        )
            == "email_unverified";
        done = app.call("kim", "submit_verification", {"tenant": "kims", "email": KIM});
        assert done["ok"] , done;
        assert done["status"] == "submitted"
            and done["state"] == "ready_for_go_live"
            and not done["editable"];
        assert code_of(
            app.call("kim", "save_verification", {"tenant": "kims", "details": DETAILS})
        )
            == "under_review";
        assert code_of(_upload(app, "id_front", "image/png", _png())) == "under_review";
        # Still not public: submitted isn't approved.
        assert code_of(browse(app, "public_branding", {"slug": "kims"})) == "not_found";
        # A tenant admin sets the cinema up, but isn't its owner.
        assert code_of(app.call("owner", "verification", {"tenant": "kims"}))
            == "not_found";
    } finally {
        _close(app);
    }
}
