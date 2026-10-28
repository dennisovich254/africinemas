"""A cinema's verification for the browser tests (P14.4, P14.5): every detail and file
submitted through the API, and, for tests that start after the review, approved by the
platform's super admin.
"""

import io;
import base64;
import from PIL { Image }
import from pypdf { PdfWriter }
import from e2e.support.api { platform_admin, platform_session, call }

glob DETAILS: dict[str, str] = {
         "legal_name": "Kimani Wanjiru",
         "id_number": "12345678",
         "phone": "0712 345 678",
         "registered_name": "Nova Cinemas Ltd",
         "business_type": "limited_company",
         "registration_number": "PVT-ABC123",
         "kra_pin": "P051234567Q",
         "permit_expiry": "2099-12-31",
         "premises_address": "Westgate Mall, Nairobi"
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

def submitted(owner: dict[str, str]) {
    # The owner's cinema, with every detail, file and required policy, submitted.
    tenant = owner["slug"];
    token = owner["token"];
    assert call(token, "save_verification", {"tenant": tenant, "details": DETAILS})[
        "ok"
    ];
    for (item, kind, data) in [
        ("id_front", "image/png", png_base64()),
        ("id_back", "image/png", png_base64()),
        ("registration_certificate", "application/pdf", pdf_base64()),
        ("kra_certificate", "application/pdf", pdf_base64()),
        ("county_permit", "application/pdf", pdf_base64())
    ] {
        sent = call(
            token,
            "upload_verification_file",
            {"tenant": tenant, "item": item, "content_type": kind, "data_base64": data}
        );
        assert sent["ok"] , sent;
    }
    for kind in ["terms", "privacy", "refunds"] {
        assert call(
            token,
            "save_policy",
            {
                "tenant": tenant,
                "kind": kind,
                "text": "Ours.",
                "published": True,
                "reviewed": True
            }
        )["ok"];
    }
    done = call(token, "submit_verification", {"tenant": tenant});
    assert done["ok"] , done;
}

def verified(owner: dict[str, str]) {
    # Submitted, then approved by the platform's super admin: verified and public.
    submitted(owner);
    (_, token) = platform_session(platform_admin());
    approved = call(
        token,
        "platform_decide",
        {"slug": owner["slug"], "decision": "approve", "reasons": []}
    );
    assert approved["ok"] , approved;
}
