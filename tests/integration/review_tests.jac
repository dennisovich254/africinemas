"""P14.5: AfriCinemas reviews a submitted cinema, then approves, asks for changes or rejects.

In-process app (payment_app.jac) with the development outbox. Kim submits Kim's Cinema.
A reviewer finds it in the queue, reads the details, opens a file (logged), and asks
for changes with a reason: the cinema goes back to setting up, Kim's page reopens with
the reason, and Kim is emailed. Kim resubmits; the reviewer approves it: it's active and
public, with the date for its Verified badge. A second cinema is rejected and stays
private. Only reviewers and super admins may see or decide.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup {
    code_of,
    browse,
    open_cinema_for,
    set_prices
}
import from tests.support.platform_setup { super_admin, join_platform }
import from tests.support.verification_setup {
    verifying_app,
    close_app,
    submitted,
    KIM
}

def _team(app: Served) {
    super_admin(app, "boss", "boss@example.com");
    for (label, role) in [("checker", "reviewer"), ("helper", "support")] {
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": f"{label}@example.com", "role": role}
        );
        assert invited["ok"] , invited;
        join_platform(app, label, invited["token"]);
    }
}

def _mails(app: Served, to: str) -> list[dict[str, str]] {
    app.call("owner", "t_send_decision_mail");
    return [
        m
        for m in app.call("owner", "tm_outbox")
        if m["to"] == to
    ];
}

test "changes are asked, then the resubmitted cinema is approved and public" {
    app = verifying_app();
    try {
        _team(app);
        submitted(app);
        app.call("owner", "tm_clear_outbox");
        queue = app.call("checker", "platform_reviews")["reviews"];
        assert [r["slug"] for r in queue] == ["kims"] , queue;
        assert code_of(app.call("helper", "platform_reviews")) == "not_allowed";
        assert code_of(app.call("rival", "platform_review", {"slug": "kims"}))
            == "not_platform";
        page = app.call("checker", "platform_review", {"slug": "kims"});
        assert page["status"] == "submitted"
            and page["details"]["kra_pin"] == "P051234567Q";
        assert page["owners"] == [KIM] , page["owners"];
        assert [f["type"] for f in page["files"]]
            == ["image", "image", "pdf", "pdf", "pdf"];
        assert len(page["checklist"]) == 5;
        seen = app.call(
            "checker", "platform_review_file", {"slug": "kims", "item": "county_permit"}
        );
        assert seen["ok"] and seen["type"] == "pdf";
        assert code_of(
            app.call(
                "helper", "platform_review_file", {"slug": "kims", "item": "id_front"}
            )
        )
            == "not_allowed";
        # Asking for changes needs a reason.
        assert code_of(
            app.call(
                "checker",
                "platform_decide",
                {"slug": "kims", "decision": "changes", "reasons": []}
            )
        )
            == "reasons_needed";
        asked = app.call(
            "checker",
            "platform_decide",
            {
                "slug": "kims",
                "decision": "changes",
                "reasons": ["The KRA PIN certificate is for another business."]
            }
        );
        assert asked["ok"] and asked["status"] == "changes_requested" , asked;
        mine = app.call("kim", "verification", {"tenant": "kims"});
        assert mine["editable"] and mine["state"] == "configuring";
        assert mine["reasons"] == ["The KRA PIN certificate is for another business."];
        mails = _mails(app, KIM);
        assert len(mails) == 1 and "changes" in mails[0]["subject"] , mails;
        assert "another business" in mails[0]["text"];
        # Kim resubmits; the reviewer approves.
        assert app.call("kim", "submit_verification", {"tenant": "kims"})["ok"];
        waiting = app.call("boss", "platform_cinemas", {"search": "kims"})["cinemas"];
        assert waiting[0]["verification"] == "submitted"
            and not waiting[0]["verified_at"];
        assert not browse(app, "verified_cinema", {"slug": "kims"})["verified"];
        assert code_of(browse(app, "public_branding", {"slug": "kims"})) == "not_found";
        approved = app.call(
            "checker",
            "platform_decide",
            {"slug": "kims", "decision": "approve", "reasons": []}
        );
        assert approved["ok"] and approved["status"] == "approved" , approved;
        assert approved["reviewed_by"] == "checker@example.com";
        # The badge's check on our own site: verified, with its one true address.
        checked = browse(app, "verified_cinema", {"slug": "kims"});
        assert checked["verified"] and checked["name"] == "Kim's Cinema" , checked;
        assert "kims" in checked["address"];
        # Not verified, unknown, or private: one answer, naming nothing.
        for other in ["rift", "no-such-cinema"] {
            assert browse(app, "verified_cinema", {"slug": other})
                == {"ok": True, "verified": False};
        }
        # And in the console's list of cinemas.
        listed = app.call("boss", "platform_cinemas", {"search": "kims"})["cinemas"];
        assert listed[0]["verified_at"]
            and listed[0]["verification"] == "approved" , listed;
        shown = browse(app, "public_branding", {"slug": "kims"});
        assert shown["ok"] and shown["verified_at"] , shown;
        assert app.call("boss", "platform_cinema", {"slug": "kims"})["cinema"]["state"]
            == "active";
        assert "verified" in _mails(app, KIM)[-1]["subject"];
        assert code_of(
            app.call(
                "checker",
                "platform_decide",
                {"slug": "kims", "decision": "approve", "reasons": []}
            )
        )
            == "not_waiting";
        assert app.call("checker", "platform_reviews")["reviews"] == [];
        history = [
            h["what"]
            for h in app.call("boss", "platform_cinema", {"slug": "kims"})["cinema"][
                "history"
            ]
        ];
        for action in [
            "platform.verification_changes_requested",
            "platform.verification_approved",
            "platform.verification_file_viewed"
        ] {
            assert action in history , history;
        }
    } finally {
        close_app(app);
    }
}

test "a rejected cinema stays private, and the owner can't resubmit" {
    app = verifying_app();
    try {
        _team(app);
        submitted(app);
        refused = app.call(
            "boss",
            "platform_decide",
            {
                "slug": "kims",
                "decision": "reject",
                "reasons": ["The documents don't match."]
            }
        );
        assert refused["ok"] and refused["status"] == "rejected" , refused;
        assert code_of(browse(app, "public_branding", {"slug": "kims"})) == "not_found";
        mine = app.call("kim", "verification", {"tenant": "kims"});
        assert not mine["editable"] and mine["status"] == "rejected";
        assert code_of(app.call("kim", "submit_verification", {"tenant": "kims"}))
            == "under_review";
        assert code_of(
            app.call(
                "boss",
                "platform_decide",
                {"slug": "kims", "decision": "maybe", "reasons": []}
            )
        )
            == "unknown_decision";
    } finally {
        close_app(app);
    }
}
