"""P15.0: the data protection registers in the console, requests and breaches.

In-process app (payment_app.jac), the clock moved on (AFRICINEMAS_CLOCK_CONTROL).

- Requests: numbered in order, due by their kind (access 7 days, portability 30); a
  cinema's customer's passed on within 2 working days; steps kept with who and when;
  answering needs what was done and closes it; overdue once its day has passed.
- Breaches: the clocks from our role (48 hours to tell cinemas, 72 to notify the
  Commissioner); the assessment says why it's notifiable; a step late past its clock;
  closed, it can't change.
- Super admins only; every change is in the platform audit log; nothing is deleted.
"""

import os;
import from datetime { datetime, timedelta }
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of }
import from tests.support.payment_setup { paying_cinema }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

glob BOSS: str = "boss@example.com",
     REV: str = "rev@example.com";

def _registers(app: Served) -> dict[str, any] {  # jac:ignore[W1037]
    got = app.call("boss", "dp_registers", {});
    assert got["ok"] , got;
    return got;
}

test "requests and breaches are logged, timed and kept, by super admins only" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, _, _) = paying_cinema([]);
    try {
        super_admin(app, "boss", BOSS);
        start = datetime.fromisoformat("2026-11-02T09:00:00+03:00");
        assert app.call("owner", "t_clock_at", {"at": start.isoformat()});
        # A request: an access request from a cinema's customer, due in 7 days.
        made = app.call(
            "boss",
            "log_data_request",
            {
                "fields": {
                    "kind": "access",
                    "person": "Wanjiru K.",
                    "contact": "wanjiru@example.com",
                    "cinema": "nova",
                    "asked": "A copy of everything you hold about me."
                }
            }
        );
        assert made["ok"] , made;
        first = made["request"];
        assert first["id"] == "R-001" and first["status"] == "open";
        assert datetime.fromisoformat(first["due"]) - start == timedelta(days=7);
        assert first["pass_by"] and first["open"] and not first["overdue"];
        assert first["events"][0]["step"] == "logged"
            and first["events"][0]["by"] == BOSS;
        # Portability: 30 days; numbered next.
        port = app.call(
            "boss",
            "log_data_request",
            {
                "fields": {
                    "kind": "portability",
                    "person": "Otieno",
                    "asked": "My data, to move."
                }
            }
        )["request"];
        assert port["id"] == "R-002" and port["pass_by"] == "";
        assert datetime.fromisoformat(port["due"]) - start == timedelta(days=30);
        # What's missing is refused.
        for fields in [
            {"kind": "nope", "person": "A", "asked": "B"},
            {"kind": "access", "person": "", "asked": "B"},
            {"kind": "access", "person": "A", "asked": ""}
        ] {
            assert not app.call("boss", "log_data_request", {"fields": fields})["ok"];
        }
        # Steps: identity checked, then passed to the cinema; answering needs a note.
        step = {"request_id": "R-001", "step": "identity_checked", "note": ""};
        assert app.call("boss", "data_request_step", step)["ok"];
        assert app.call(
            "boss",
            "data_request_step",
            {** step, "step": "passed_to_cinema", "note": "Emailed Nova."}
        )["request"]["status"]
            == "passed_to_cinema";
        assert code_of(
            app.call("boss", "data_request_step", {** step, "step": "answered"})
        )
            == "invalid_note";
        # Eight days on, R-002 is still open but not overdue; R-001 is overdue.
        assert app.call("owner", "t_clock_ahead", {"hours": 24 * 8});
        shown = {r["id"]: r for r in _registers(app)["requests"]};
        assert shown["R-001"]["overdue"] and not shown["R-002"]["overdue"];
        answered = app.call(
            "boss",
            "data_request_step",
            {** step, "step": "answered", "note": "Nova sent the export on 9 Nov."}
        );
        assert answered["ok"] and not answered["request"]["open"];
        assert [e["step"] for e in answered["request"]["events"]]
            == ["logged", "identity_checked", "passed_to_cinema", "answered"];
        assert code_of(
            app.call(
                "boss", "data_request_step", {** step, "step": "note", "note": "More"}
            )
        )
            == "closed";
        # Open ones first.
        assert [r["id"] for r in _registers(app)["requests"]] == ["R-002", "R-001"];
        # A breach of both kinds of data: both clocks.
        aware = datetime.fromisoformat("2026-11-10T08:00:00+03:00");
        breach = app.call(
            "boss",
            "log_breach",
            {
                "fields": {
                    "role": "both",
                    "aware_at": aware.isoformat(),
                    "what": "A support screenshot link was public for a day."
                }
            }
        )["breach"];
        assert breach["id"] == "B-001" and breach["open"];
        assert datetime.fromisoformat(breach["cinemas_by"]) - aware
            == timedelta(hours=48);
        assert datetime.fromisoformat(breach["commissioner_by"]) - aware
            == timedelta(hours=72);
        # Assessed: notifiable needs a why.
        assess = {
            "breach_id": "B-001",
            "fields": {"notifiable": "yes", "why": "", "people": "12"}
        };
        assert code_of(app.call("boss", "assess_breach", assess)) == "invalid_note";
        assessed = app.call(
            "boss",
            "assess_breach",
            {
                ** assess,
                "fields": {
                    "notifiable": "yes",
                    "why": "Phone numbers with M-Pesa receipts (reg 37).",
                    "people": "12",
                    "data": "Support screenshots",
                    "cinemas": "nova"
                }
            }
        )["breach"];
        assert assessed["notifiable"] == "yes" and assessed["people"] == "12";
        assert app.call(
            "boss",
            "breach_step",
            {
                "breach_id": "B-001",
                "step": "cinemas_told",
                "note": "Emailed Nova's owner."
            }
        )["ok"];
        # Four days on: the Commissioner's clock has run out, the cinemas' hasn't.
        assert app.call(
            "owner", "t_clock_at", {"at": (aware + timedelta(days=4)).isoformat()}
        );
        late = _registers(app)["breaches"][0];
        assert late["late"] == ["commissioner_notified"] , late;
        # Closed: nothing more.
        assert app.call(
            "boss",
            "breach_step",
            {"breach_id": "B-001", "step": "closed", "note": "Fixed and reported."}
        )["ok"];
        assert code_of(
            app.call(
                "boss",
                "breach_step",
                {"breach_id": "B-001", "step": "note", "note": "x"}
            )
        )
            == "closed";
        assert not _registers(app)["breaches"][0]["open"];
        # Others can't see or change them.
        invited = app.call(
            "boss", "invite_platform_member", {"email": REV, "role": "reviewer"}
        );
        join_platform(app, "rev", invited["token"]);
        for who in ["rev", "owner"] {
            assert not app.call(who, "dp_registers", {})["ok"];
            assert not app.call(
                who, "log_breach", {"fields": {"role": "controller", "what": "x"}}
            )["ok"];
        }
        # Every change is in the platform audit log.
        logged = [
            e["action"]
            for e in app.call(
                "boss", "platform_audit_log", {"limit": 100, "action": ""}
            )["events"]
            if e["result"] == "ok"
        ];
        for action in [
            "platform.data_request_logged",
            "platform.data_request_updated",
            "platform.breach_logged",
            "platform.breach_assessed",
            "platform.breach_updated"
        ] {
            assert action in logged , (action, logged);
        }
    } finally {
        app.call("owner", "t_clock_reset");
        os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
        os.environ.pop(ADMINS_ENV, None);
        app.close();
    }
}
