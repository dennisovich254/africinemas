"""P13.5a: a cinema asks AfriCinemas for technical help, and we answer.

In-process app (payment_app.jac). Nova's owner asks about a payment. AfriCinemas' super
admin finds it in the inbox, replies (waiting for the cinema), and the owner answers
(open again); we close it, and a reply reopens it. Each side's actions are in its own
audit log, and ours show in the cinema's history. An usher may not ask; another cinema
neither sees Nova's requests nor answers them; a reviewer may not open the inbox, and
a cinema owner is refused it.
"""

import os;
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, open_cinema_for }
import from tests.support.payment_setup { paying_cinema, hire }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

glob BOSS: str = "boss@example.com";

def _app -> Served {
    (app, nova, _) = paying_cinema(["rival", "usher"]);
    hire(app, "usher", "usher", nova.venue);
    open_cinema_for(app, "rival", "rift", "Imax Rift");
    super_admin(app, "boss", BOSS);
    return app;
}

def _close(app: Served) {
    os.environ.pop(ADMINS_ENV, None);
    app.close();
}

def _ask(app: Served) -> str {
    asked = app.call(
        "owner",
        "ask_for_help",
        {
            "tenant": "nova",
            "category": "payments",
            "text": "  M-Pesa prompts never arrive.  "
        }
    );
    assert asked["ok"] , asked;
    return asked["request"]["request_id"];
}

test "a cinema asks, we answer, and the request goes back and forth until closed" {
    app = _app();
    try {
        request_id = _ask(app);
        mine = app.call("owner", "support_requests", {"tenant": "nova"});
        assert [r["request_id"] for r in mine["requests"]] == [request_id];
        first = mine["requests"][0];
        assert first["status"] == "open"
            and first["category_label"] == "Payments and M-Pesa";
        assert first["messages"][0]["text"] == "M-Pesa prompts never arrive." , first;
        assert first["messages"][0]["side"] == "cinema";
        # Our inbox: it's there, about Nova, waiting on us.
        inbox = app.call("boss", "platform_support_requests", {"status": "open"});
        assert [(r["request_id"], r["cinema_slug"]) for r in inbox["requests"]]
            == [(request_id, "nova")] , inbox;
        counts = {c["key"]: c["count"] for c in inbox["counts"]};
        assert counts == {"open": 1, "waiting": 0, "closed": 0} , counts;
        replied = app.call(
            "boss",
            "platform_support_reply",
            {"request_id": request_id, "text": "Which phone number did you try?"}
        );
        assert replied["ok"] and replied["request"]["status"] == "waiting" , replied;
        seen = app.call("owner", "support_requests", {"tenant": "nova"})["requests"][0];
        assert seen["status_label"] == "Waiting for the cinema";
        assert seen["messages"][-1]["side"] == "africinemas";
        assert seen["messages"][-1]["by"] == BOSS;
        back = app.call(
            "owner",
            "reply_to_support",
            {"tenant": "nova", "request_id": request_id, "text": "0712 345 678"}
        );
        assert back["request"]["status"] == "open" , back;
        closed = app.call(
            "boss",
            "platform_support_status",
            {"request_id": request_id, "status": "closed"}
        );
        assert closed["request"]["status"] == "closed";
        assert app.call("boss", "platform_support_requests", {"status": "closed"})[
            "requests"
        ][0]["request_id"]
            == request_id;
        again = app.call(
            "owner",
            "reply_to_support",
            {"tenant": "nova", "request_id": request_id, "text": "It happened again."}
        );
        assert again["request"]["status"] == "open"
            and len(again["request"]["messages"]) == 4;
        # Ours are in the platform's log, about Nova, so in its history; theirs in its own.
        history = app.call("boss", "platform_cinema", {"slug": "nova"})["cinema"][
            "history"
        ];
        assert [h["what"] for h in history][:2]
            == ["platform.support_closed", "platform.support_replied"] , history;
        logged = app.call("owner", "audit_log", {"tenant": "nova", "limit": 20});
        actions = [e["action"] for e in logged["events"]];
        assert actions.count("support.replied") == 2 and "support.requested" in actions;
    } finally {
        _close(app);
    }
}

test "only those who may ask, at their own cinema, and only support staff answer" {
    app = _app();
    try {
        request_id = _ask(app);
        assert code_of(
            app.call(
                "usher",
                "ask_for_help",
                {"tenant": "nova", "category": "other", "text": "Hi"}
            )
        )
            == "forbidden";
        for (body, code) in [
            (
                {"tenant": "nova", "category": "nonsense", "text": "Hi"},
                "invalid_category"
            ),
            ({"tenant": "nova", "category": "other", "text": "   "}, "empty_message"),
            (
                {"tenant": "nova", "category": "other", "text": "x" * 4001},
                "message_too_long"
            )
        ] {
            assert code_of(app.call("owner", "ask_for_help", body)) == code , code;
        }
        # Another cinema sees none of Nova's, and can't answer them.
        assert app.call("rival", "support_requests", {"tenant": "rift"})["requests"]
            == [];
        assert code_of(
            app.call(
                "rival",
                "reply_to_support",
                {"tenant": "rift", "request_id": request_id, "text": "Me too"}
            )
        )
            == "not_found";
        assert code_of(app.call("rival", "support_requests", {"tenant": "nova"}))
            == "not_found";
        # A reviewer has no support role; a cinema owner isn't platform staff.
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": "rev@example.com", "role": "reviewer"}
        );
        join_platform(app, "rev", invited["token"]);
        assert code_of(app.call("rev", "platform_support_requests", {}))
            == "not_allowed";
        assert code_of(
            app.call(
                "rev",
                "platform_support_reply",
                {"request_id": request_id, "text": "Hi"}
            )
        )
            == "not_allowed";
        assert code_of(app.call("owner", "platform_support_requests", {}))
            == "not_platform";
        assert code_of(
            app.call("boss", "platform_support_request", {"request_id": "no-such"})
        )
            == "not_found";
    } finally {
        _close(app);
    }
}
