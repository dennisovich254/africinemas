"""Verification test set-up (P14.4, P14.5): an owner with a confirmed email, and a cinema
not yet live that's ready to submit for review.

verifying_app() serves payment_app.jac with the development outbox: Kim (an email
account, confirmed) owns Kim's Cinema ("kims": a venue, a published screen, prices),
with an usher, and "rival" owns another cinema. submitted(app, slug) fills in every
detail and file, publishes the required policies and submits.
"""

import io;
import os;
import base64;
import tempfile;
import from PIL { Image }
import from pypdf { PdfWriter }
import from tests.support.served { Served, served }
import from tests.support.harness { Actor }
import from tests.support.storefront_setup { open_cinema_for, set_prices, browse }
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

def png_base64 -> str {
    out = io.BytesIO();
    Image.new("RGB", (900, 600), (40, 90, 160)).save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def pdf_base64 -> str {
    writer = PdfWriter();
    writer.add_blank_page(width=200, height=200);
    out = io.BytesIO();
    writer.write(out);
    return base64.b64encode(out.getvalue()).decode();
}

def sign_up_with_email(app: Served, label: str, email: str) {
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

def confirm_kim(app: Served) {
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

def verifying_app -> Served {
    # Verification files are sealed with it (P15.0).
    os.environ.setdefault(
        "AFRICINEMAS_FILES_KEY", "files-test-sealing-key-0123456789abcdef"
    );
    os.environ["AFRICINEMAS_OUTBOX_DIR"] = tempfile.mkdtemp(
        prefix="africinemas-outbox-"
    );
    os.environ.pop("AFRICINEMAS_SMTP_HOST", None);
    app = served(APP, ["owner", "usher", "rival"]);
    sign_up_with_email(app, "kim", KIM);
    confirm_kim(app);
    kims = open_cinema_for(app, "kim", "kims", "Kim's Cinema", live=False, email=KIM);
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

def close_app(app: Served) {
    os.environ.pop("AFRICINEMAS_OUTBOX_DIR", None);
    app.close();
}

def upload_file(
    app: Served, item: str, content_type: str, data: str, slug: str = "kims"
) -> any {  # jac:ignore[W1037]
    return app.call(
        "kim",
        "upload_verification_file",
        {
            "tenant": slug,
            "item": item,
            "content_type": content_type,
            "data_base64": data
        }
    );
}

def submitted(app: Served, slug: str = "kims") {
    # Kim's cinema `slug`, with every detail, file and required policy, submitted.
    assert app.call("kim", "save_verification", {"tenant": slug, "details": DETAILS})[
        "ok"
    ];
    for item in ["id_front", "id_back"] {
        assert upload_file(app, item, "image/png", png_base64(), slug)["ok"];
    }
    for item in ["registration_certificate", "kra_certificate", "county_permit"] {
        assert upload_file(app, item, "application/pdf", pdf_base64(), slug)["ok"];
    }
    for kind in ["terms", "privacy", "refunds"] {
        assert app.call(
            "kim",
            "save_policy",
            {
                "tenant": slug,
                "kind": kind,
                "text": "Ours.",
                "published": True,
                "reviewed": True
            }
        )["ok"];
    }
    accept_agreement(app, "kim", slug);
    done = app.call("kim", "submit_verification", {"tenant": slug});
    assert done["ok"] , done;
}

def accept_agreement(app: Served, who: str, slug: str) {
    # `who` accepts the current cinema agreement for `slug` (P15.1).
    current = app.call(who, "cinema_agreement_status", {"tenant": slug})["current"];
    assert app.call(
        who, "accept_cinema_agreement", {"tenant": slug, "version": current}
    )["ok"];
}
