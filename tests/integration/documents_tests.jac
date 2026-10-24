"""P14.3d: a cinema's public documents, and a policy as a PDF.

In-process app (payment_app.jac). Nova's owner uploads its KFCB licence: it's listed in
the back office and in every storefront footer, and a visitor gets the rebuilt PDF. It
can be removed. A file that isn't a PDF is refused with a reason. The terms can be
published as a PDF alone; its PDF can't then be removed. Only settings staff may upload;
another cinema's staff find nothing. Each upload and removal is audited.
"""

import io;
import base64;
import from pypdf { PdfWriter }
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, browse }
import from tests.support.payment_setup { paying_cinema, hire }

def _pdf -> str {
    writer = PdfWriter();
    writer.add_blank_page(width=200, height=200);
    out = io.BytesIO();
    writer.write(out);
    return base64.b64encode(out.getvalue()).decode();
}

def _app -> Served {
    (app, nova, _) = paying_cinema(["usher", "rival"]);
    hire(app, "usher", "usher", nova.venue);
    app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
    return app;
}

test "an uploaded licence is in every footer, opens for visitors, and can be removed" {
    app = _app();
    try {
        made = app.call(
            "owner",
            "upload_public_document",
            {
                "tenant": "nova",
                "title": "  KFCB film   exhibition licence ",
                "data_base64": _pdf()
            }
        );
        assert made["ok"] , made;
        assert [d["title"] for d in made["documents"]]
            == ["KFCB film exhibition licence"];
        doc_id = made["documents"][0]["id"];
        listed = browse(app, "public_branding", {"slug": "nova"})["documents"];
        assert listed
            == [{"id": doc_id, "title": "KFCB film exhibition licence"}] , listed;
        shown = browse(app, "public_document", {"slug": "nova", "document_id": doc_id});
        assert shown["ok"] and base64.b64decode(shown["pdf"]).startswith(b"%PDF-") , shown.get(
            "error"
        );
        assert code_of(
            browse(app, "public_document", {"slug": "nova", "document_id": "nope"})
        )
            == "not_found";
        refused = app.call(
            "owner",
            "upload_public_document",
            {
                "tenant": "nova",
                "title": "Permit",
                "data_base64": base64.b64encode(b"not a pdf").decode()
            }
        );
        assert code_of(refused) == "invalid_pdf" , refused;
        assert code_of(
            app.call(
                "owner",
                "upload_public_document",
                {"tenant": "nova", "title": " ", "data_base64": _pdf()}
            )
        )
            == "invalid_title";
        gone = app.call(
            "owner", "remove_public_document", {"tenant": "nova", "document_id": doc_id}
        );
        assert gone["ok"] and gone["documents"] == [];
        assert code_of(
            browse(app, "public_document", {"slug": "nova", "document_id": doc_id})
        )
            == "not_found";
        logged = [
            e["action"]
            for e in app.call("owner", "audit_log", {"tenant": "nova", "limit": 10})[
                "events"
            ]
        ];
        assert "document.uploaded" in logged and "document.removed" in logged , logged;
        # Only settings staff, and only at their own cinema.
        body = {"tenant": "nova", "title": "Permit", "data_base64": _pdf()};
        assert code_of(app.call("usher", "upload_public_document", body))
            == "forbidden";
        assert code_of(app.call("rival", "upload_public_document", body))
            == "not_found";
        assert code_of(app.call("rival", "public_documents_admin", {"tenant": "nova"}))
            == "not_found";
    } finally {
        app.close();
    }
}

test "the terms can be published as a PDF alone, and that PDF then stays" {
    app = _app();
    try {
        attached = app.call(
            "owner",
            "upload_policy_pdf",
            {"tenant": "nova", "kind": "terms", "data_base64": _pdf()}
        );
        assert attached["ok"] , attached;
        assert attached["policies"][0]["has_pdf"];
        published = app.call(
            "owner",
            "save_policy",
            {
                "tenant": "nova",
                "kind": "terms",
                "text": "",
                "published": True,
                "reviewed": True
            }
        );
        assert published["ok"] , published;
        shown = browse(app, "public_policy", {"slug": "nova", "kind": "terms"});
        assert shown["has_pdf"] and shown["text"] == "" , shown;
        pdf = browse(app, "public_policy_pdf", {"slug": "nova", "kind": "terms"});
        assert pdf["ok"] and pdf["title"] == "Terms of ticket sale";
        assert code_of(
            app.call("owner", "remove_policy_pdf", {"tenant": "nova", "kind": "terms"})
        )
            == "pdf_in_use";
        # A draft's PDF isn't public.
        assert app.call(
            "owner",
            "upload_policy_pdf",
            {"tenant": "nova", "kind": "privacy", "data_base64": _pdf()}
        )["ok"];
        assert code_of(
            browse(app, "public_policy_pdf", {"slug": "nova", "kind": "privacy"})
        )
            == "not_found";
        assert app.call(
            "owner", "remove_policy_pdf", {"tenant": "nova", "kind": "privacy"}
        )["ok"];
        assert code_of(
            app.call(
                "usher",
                "upload_policy_pdf",
                {"tenant": "nova", "kind": "terms", "data_base64": _pdf()}
            )
        )
            == "forbidden";
    } finally {
        app.close();
    }
}
