"""P15.0b: AfriCinemas' legal pages and the registrations checklist.

In-process app (payment_app.jac). Anyone reads the four legal documents, each with its
version, the date it applies from and the review note, and none carries a draft's
notes. The settings' super admin (boss) ticks and unticks registrations, with who and
when kept and the platform log recording it; a reviewer and a cinema owner can't.
"""

import os;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { paying_cinema }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

glob BOSS: str = "boss@example.com",
     REV: str = "rev@example.com",
     DRAFT_MARKS: list[str] = [
         "Draft v0.1",
         "[Advocate",
         "[advocate",
         "(P1",
         "ADR-",
         "JI-0",
         "[number]"
     ];

test "the legal documents are public, versioned and free of the drafts' notes" {
    (app, _, _) = paying_cinema([]);
    try {
        for name in ["terms", "privacy", "cookies"] {
            got = browse(app, "legal_document", {"name": name});
            assert got["ok"] and got["version"] == "0.1" , got;
            assert got["applies_from"] and "reviewed by our lawyers" in got["note"];
            assert got["text"].startswith("# ") , name;
            for mark in DRAFT_MARKS {
                assert mark not in got["text"] , f"{name}: {mark}";
            }
        }
        # The cinema agreement is confidential: not public, only for a signed-in account.
        assert code_of(browse(app, "legal_document", {"name": "cinema-agreement"}))
            == "not_found";
        agreement = app.call("owner", "cinema_agreement_text", {"tenant": "nova"});
        assert agreement["ok"] and agreement["version"] == "0.1" , agreement;
        fee = agreement["text"];
        for mark in DRAFT_MARKS {
            assert mark not in fee , mark;
        }
        assert "**7%**" in fee and "**20%**" in fee and "**3%**" in fee;
        assert code_of(browse(app, "legal_document", {"name": "../secrets"}))
            == "not_found";
    } finally {
        app.close();
    }
}

test "only super admins tick registrations, with who and when kept and logged" {
    (app, _, _) = paying_cinema([]);
    try {
        super_admin(app, "boss", BOSS);
        listed = app.call("boss", "registrations_checklist", {});
        assert listed["ok"] and len(listed["items"]) == 16 , listed;
        assert not [
            i
            for i in listed["items"]
            if i["done"]
        ];
        ticked = app.call(
            "boss",
            "tick_registration",
            {
                "key": "domain",
                "done": True,
                "reference": "Registrar: KenyaWebs, renews 2027"
            }
        );
        assert ticked["ok"] , ticked;
        item = [
            i
            for i in app.call("boss", "registrations_checklist", {})["items"]
            if i["key"] == "domain"
        ][0];
        assert item["done"] and item["by"] == BOSS and item["at"];
        assert item["reference"] == "Registrar: KenyaWebs, renews 2027";
        assert code_of(
            app.call("boss", "tick_registration", {"key": "nope", "done": True})
        )
            == "not_found";
        assert code_of(
            app.call(
                "boss",
                "tick_registration",
                {"key": "vat", "done": True, "reference": "<b>x</b>"}
            )
        )
            == "invalid_reference";
        unticked = app.call(
            "boss", "tick_registration", {"key": "domain", "done": False}
        );
        assert unticked["ok"] and not unticked["item"]["done"] , unticked;
        # Others can't see or change it.
        invited = app.call(
            "boss", "invite_platform_member", {"email": REV, "role": "reviewer"}
        );
        join_platform(app, "rev", invited["token"]);
        for who in ["rev", "owner"] {
            assert not app.call(who, "registrations_checklist", {})["ok"];
            assert not app.call(who, "tick_registration", {"key": "vat", "done": True})[
                "ok"
            ];
        }
        logged = app.call(
            "boss",
            "platform_audit_log",
            {"limit": 50, "action": "platform.registration_ticked"}
        );
        assert [
            e
            for e in logged["events"]
            if e["resource_id"] == "domain"
        ] , logged;
    } finally {
        os.environ.pop(ADMINS_ENV, None);
        app.close();
    }
}
