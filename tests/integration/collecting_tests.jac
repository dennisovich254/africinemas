"""P15.5: collecting what's owed.

In-process app (payment_app.jac), the clock stopped on chosen days (test-only clock).
Nova's invoice for this month is issued on the 2nd of next month, due on the 7th.

- Paying: the box office and another cinema can't; a bad number is refused; a failed
  payment leaves it owed; the amount is always the invoice's, in whole shillings; one
  prompt at a time; once M-Pesa says paid it's paid, once, and can't be paid again.
- Reminders: 2 days before, on the day, 3 and 7 days after, each once; none while
  disputed or once paid; a missed day sends only the latest.
- Disputes: only finance readers, with a reason; it opens a Help request, pauses
  reminders and suspension; a super admin decides it stands or waives it.
- Unmatched: a payment for an invoice already settled waits to be matched by hand (to
  an invoice still owed, for its amount) or recorded as refunded.
- Overdue and suspension: overdue after the due day, with a banner for those who can
  pay; suspending needs a person with platform.suspend, more than 5 days overdue and
  no open dispute; suspended, the storefront says it's unavailable and nothing can be
  sold, the back office says why, the invoice can still be paid, and Reinstate undoes
  it; both are in the platform audit log and emailed.
"""

import os;
import uuid;
import from datetime { datetime, date, timedelta }
import from zoneinfo { ZoneInfo }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, add_screening }
import from tests.support.payment_setup { paying_cinema, paid, hire, fresh_phone }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

glob NAIROBI: ZoneInfo = ZoneInfo("Africa/Nairobi"),
     FAILS: str = "254700000001";

def _second_of(months_ahead: int) -> datetime {
    day = datetime.now(NAIROBI).replace(
        day=1, hour=9, minute=0, second=0, microsecond=0
    );
    for _ in range(months_ahead) {
        day = (day + timedelta(days=32)).replace(day=1);
    }
    return day.replace(day=2);
}

def _on(app: Served, day: date, hour: int = 10) {
    # Stops the clock at `hour` o'clock on `day` in Nairobi.
    at = datetime(day.year, day.month, day.day, hour, 0, tzinfo=NAIROBI);
    assert app.call("owner", "t_clock_at", {"at": at.isoformat()});
}

def _cash_sale(app: Served, screening: str, seat: str) {
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": "nova", "screening_id": screening, "holder": holder};
    assert browse(app, "hold_seats", {** where, "labels": [seat]})["ok"];
    assert browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": seat, "ticket_type": "ADULT"}],
            "snacks": []
        }
    )["ok"];
    sold = app.call(
        "agent",
        "sell_for_cash",
        {"tenant": "nova", "screening_id": screening, "holder": holder, "email": ""}
    );
    assert sold["ok"] , sold;
}

def _invoice(app: Served, who: str = "owner") -> dict[str, any] {  # jac:ignore[W1037]
    got = app.call(who, "billing", {"tenant": "nova"});
    assert got["ok"] , got;
    return got["statements"][0];
}

def _pay(app: Served, number: str, phone: str, who: str = "owner") -> dict[str, any] {  # jac:ignore[W1037]
    return app.call(
        who, "pay_invoice", {"tenant": "nova", "number": number, "phone": phone}
    );
}

def _settled(app: Served, reference: str) -> dict[str, any] {  # jac:ignore[W1037]
    got = app.call(
        "owner", "invoice_payment", {"tenant": "nova", "reference": reference}
    );
    assert got["ok"] , got;
    return got;
}

def _code(got: dict[str, any]) -> str {  # jac:ignore[W1037]
    return got["error"]["code"] if not got["ok"] else "";
}

def _mails(app: Served) -> list[str] {
    # The subjects sent since last asked.
    app.call("owner", "t_send_mpesa_mail");
    subjects = [m["subject"] for m in app.call("owner", "tm_outbox")];
    app.call("owner", "tm_clear_outbox");
    return subjects;
}

def _setup(staff: list[str]) -> tuple[Served, any, str, str] {  # jac:ignore[W1037]
    # Nova with this month's sales (online and cash) invoiced on the 2nd of next month.
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, screening) = paying_cinema(["agent"] + staff);
    super_admin(app, "boss", "boss@example.com");
    hire(app, "agent", "box_office_agent", nova.venue);
    assert app.call(
        "owner", "t_owner_email", {"slug": "nova", "email": "nova-owner@example.com"}
    );
    paid(app, screening);
    _cash_sale(app, screening, "A3");
    made = app.call("owner", "t_issue_statements", {"at": _second_of(1).isoformat()});
    assert len(made) == 1 , made;
    return (app, nova, screening, made[0]);
}

def _done(app: Served) {
    app.call("owner", "t_clock_reset");
    os.environ.pop(ADMINS_ENV, None);
    os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
    app.close();
}

test "an invoice is paid in full by M-Pesa, once, by its finance readers only" {
    (app, nova, screening, number) = _setup(["rival", "finance"]);
    try {
        hire(app, "finance", "finance_manager", "");
        app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        issued = _second_of(1).date();
        _on(app, issued);
        s = _invoice(app);
        assert s["status"] == "due" and s["days_overdue"] == 0 and not s["suspendable"];
        due = s["figures"]["due_cents"];
        # Whole shillings for M-Pesa, half up.
        assert s["payable_cents"] == (due + 50) // 100 * 100 , s;
        assert s["payable_cents"] - due == s["figures"]["rounding_cents"];
        # Not the box office, nor another cinema.
        assert _code(_pay(app, number, fresh_phone(), "agent")) == "forbidden";
        assert not _pay(app, number, fresh_phone(), "rival")["ok"];
        assert _code(_pay(app, number, "12345")) == "invalid_phone";
        assert _code(_pay(app, "AC999999", fresh_phone())) == "not_found";
        # A payment that fails leaves it owed.
        failed = _pay(app, number, FAILS);
        assert failed["ok"] and failed["payment"]["amount_cents"] == s["payable_cents"];
        assert _settled(app, failed["payment"]["reference"])["payment"]["state"]
            == "failed";
        assert _invoice(app)["status"] == "due";
        # The finance manager pays; the amount is the invoice's, whatever's sent.
        started = _pay(app, number, fresh_phone(), "finance");
        assert started["ok"]
            and started["payment"]["state"] == "stk_requested" , started;
        assert started["payment"]["amount_cents"] == s["payable_cents"];
        assert "***" in started["payment"]["phone"];
        # One prompt at a time.
        assert _code(_pay(app, number, fresh_phone())) == "payment_in_progress";
        assert app.call("owner", "t_settle_bills") == 1;
        assert app.call("owner", "t_settle_bills") == 0;
        done = _settled(app, started["payment"]["reference"]);
        assert done["payment"]["state"] == "paid" and done["status"] == "paid" , done;
        s = _invoice(app);
        assert s["status"] == "paid" and s["paid_receipt"] and s["paid_how"] == "mpesa";
        assert s["figures"] == _invoice(app, "finance")["figures"];
        assert _code(_pay(app, number, fresh_phone())) == "nothing_to_pay";
        # Not overdue once paid, however late.
        _on(app, issued + timedelta(days=30));
        assert _invoice(app)["status"] == "paid";
        assert app.call("owner", "billing_notice", {"tenant": "nova"})["overdue"] == [];
        logged = [
            e["action"]
            for e in app.call("owner", "audit_log", {"tenant": "nova", "limit": 50})[
                "events"
            ]
        ];
        assert logged.count("billing.payment_started") >= 3 , logged;
    } finally {
        _done(app);
    }
}

test "reminders go before, on and after the due day, each once, never once paid or disputed" {
    (app, nova, screening, number) = _setup([]);
    try {
        due_on = date.fromisoformat(_invoice(app)["due_on"]);
        _mails(app);
        _on(app, due_on - timedelta(days=3));
        assert app.call("owner", "t_remind_bills") == 0;
        _on(app, due_on - timedelta(days=2));
        assert app.call("owner", "t_remind_bills") == 1;
        assert app.call("owner", "t_remind_bills") == 0;
        sent = _mails(app);
        assert len(sent) >= 1
            and all([f"{number} is due on" in m for m in sent]) , sent;
        _on(app, due_on);
        assert app.call("owner", "t_remind_bills") == 1;
        assert all(["due today" in m for m in _mails(app)]);
        # Overdue from the next day: those who can pay get a banner.
        _on(app, due_on + timedelta(days=1));
        notice = app.call("owner", "billing_notice", {"tenant": "nova"});
        assert notice["may_pay"]
            and [n["number"] for n in notice["overdue"]] == [number];
        assert notice["overdue"][0]["days"] == 1 and not notice["suspended"];
        agent = app.call("agent", "billing_notice", {"tenant": "nova"});
        assert agent["ok"] and not agent["may_pay"];
        assert app.call("owner", "t_remind_bills") == 0;
        _on(app, due_on + timedelta(days=3));
        assert app.call("owner", "t_remind_bills") == 1;
        assert all(["overdue" in m for m in _mails(app)]);
        # A missed week: only the latest, once.
        _on(app, due_on + timedelta(days=10));
        assert app.call("owner", "t_remind_bills") == 1;
        assert app.call("owner", "t_remind_bills") == 0;
        _mails(app);
        # Disputed: no reminders for it.
        assert app.call(
            "owner",
            "dispute_invoice",
            {
                "tenant": "nova",
                "number": number,
                "text": "The cash sale on the 3rd was refunded."
            }
        )["ok"];
        assert _invoice(app)["dispute"]["open"];
    } finally {
        _done(app);
    }
}

test "a dispute opens a Help request, pauses suspension, and a super admin decides it" {
    (app, nova, screening, number) = _setup(["finance"]);
    try {
        hire(app, "finance", "finance_manager", "");
        due_on = date.fromisoformat(_invoice(app)["due_on"]);
        _on(app, due_on + timedelta(days=6));
        assert _invoice(app)["suspendable"];
        body = {
            "tenant": "nova",
            "number": number,
            "text": "We were charged for a refunded sale."
        };
        assert _code(app.call("agent", "dispute_invoice", body)) == "forbidden";
        assert _code(app.call("owner", "dispute_invoice", {** body, "text": "wrong"}))
            == "invalid_text";
        assert app.call("finance", "dispute_invoice", body)["ok"];
        assert _code(app.call("owner", "dispute_invoice", body)) == "already_disputed";
        s = _invoice(app);
        assert s["dispute"]["open"] and s["dispute"]["text"] == body["text"];
        assert not s["suspendable"] , s;
        # It's in Help, as a request about the invoice.
        asked = app.call("owner", "support_requests", {"tenant": "nova"})["requests"];
        mine = [
            r
            for r in asked
            if r["request_id"] == s["dispute"]["request_id"]
        ];
        assert mine and mine[0]["category"] == "invoice_dispute" , asked;
        assert number in mine[0]["messages"][0]["text"];
        # Not suspended while disputed.
        assert _code(
            app.call(
                "boss",
                "platform_suspend_cinema",
                {"slug": "nova", "reason": "Unpaid invoice"}
            )
        )
            == "not_overdue";
        assert app.call("owner", "t_remind_bills") == 0;
        # Only a super admin decides, with a reason.
        decide = {
            "number": number,
            "outcome": "stands",
            "note": "The refund came after the month."
        };
        assert not app.call("owner", "platform_decide_dispute", decide)["ok"];
        assert _code(
            app.call("boss", "platform_decide_dispute", {** decide, "outcome": "maybe"})
        )
            == "invalid_outcome";
        assert _code(
            app.call("boss", "platform_decide_dispute", {** decide, "note": ""})
        )
            == "invalid_note";
        assert app.call("boss", "platform_decide_dispute", decide)["ok"];
        assert _code(app.call("boss", "platform_decide_dispute", decide))
            == "not_disputed";
        s = _invoice(app);
        assert not s["dispute"]["open"] and s["dispute"]["outcome"] == "stands";
        assert s["dispute"]["note"] == decide["note"] and s["status"] == "overdue";
        # Decided: suspendable again, and reminded again.
        assert s["suspendable"];
        assert app.call("owner", "t_remind_bills") == 1;
        events = app.call(
            "boss",
            "platform_audit_log",
            {"limit": 20, "action": "platform.dispute_decided"}
        )["events"];
        # Refused attempts are logged too; one decision went through.
        assert [e["result"] for e in events].count("ok") == 1 , events;
    } finally {
        _done(app);
    }
}

test "a payment for an invoice already settled is matched by hand or refunded" {
    (app, nova, screening, number) = _setup(["rev"]);
    try {
        later = add_screening(app, "owner", nova, "Rafiki", 24 * 50);
        _on(app, _second_of(1).date());
        # Two prompts: the first unanswered for 15 minutes, then a second one paid.
        first = _pay(app, number, fresh_phone());
        assert first["ok"];
        assert app.call(
            "owner",
            "t_clock_at",
            {"at": (_second_of(1) + timedelta(hours=1, minutes=20)).isoformat()}
        );
        second = _pay(app, number, fresh_phone());
        assert second["ok"] , second;
        assert _settled(app, second["payment"]["reference"])["payment"]["state"]
            == "paid";
        # The first comes through after: the invoice is paid, so it waits to be matched.
        extra = _settled(app, first["payment"]["reference"])["payment"];
        assert extra["state"] == "unmatched"
            and extra["unmatched_reason"] == "already_settled";
        waiting = app.call("boss", "platform_billing", {})["unmatched"];
        assert [w["reference"] for w in waiting] == [extra["reference"]] , waiting;
        assert waiting[0]["slug"] == "nova"
            and waiting[0]["paid_cents"] == extra["amount_cents"];
        # Next month's invoice, the same amount, is still owed.
        _cash_sale(app, later, "A4");
        _cash_sale(app, later, "A5");
        made = app.call(
            "owner", "t_issue_statements", {"at": _second_of(2).isoformat()}
        );
        assert len(made) == 1 , made;
        _on(app, _second_of(2).date());
        resolve = {
            "slug": "nova",
            "reference": extra["reference"],
            "action": "match",
            "number": number,
            "note": ""
        };
        # Only a super admin; not to an invoice that's paid.
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": "rev@example.com", "role": "reviewer"}
        );
        join_platform(app, "rev", invited["token"]);
        assert not app.call("rev", "platform_resolve_payment", resolve)["ok"];
        assert not app.call("owner", "platform_resolve_payment", resolve)["ok"];
        assert _code(app.call("boss", "platform_resolve_payment", resolve))
            == "nothing_to_pay";
        nxt = _invoice(app);
        assert nxt["number"] == made[0] and nxt["status"] == "due";
        if nxt["payable_cents"] != extra["paid_cents"] {
            assert _code(
                app.call(
                    "boss", "platform_resolve_payment", {** resolve, "number": made[0]}
                )
            )
                == "amount_differs";
            assert _code(
                app.call(
                    "boss",
                    "platform_resolve_payment",
                    {** resolve, "action": "refund", "note": ""}
                )
            )
                == "note_needed";
            assert app.call(
                "boss",
                "platform_resolve_payment",
                {
                    ** resolve,
                    "action": "refund",
                    "note": "Sent back by M-Pesa, ref QWE123"
                }
            )["ok"];
        } else {
            assert app.call(
                "boss", "platform_resolve_payment", {** resolve, "number": made[0]}
            )["ok"];
            assert _invoice(app)["paid_how"] == "matched";
        }
        assert app.call("boss", "platform_billing", {})["unmatched"] == [];
        assert _code(app.call("boss", "platform_resolve_payment", resolve))
            == "not_unmatched";
    } finally {
        _done(app);
    }
}

test "a cinema more than 5 days overdue may be suspended by a person, and reinstated" {
    (app, nova, screening, number) = _setup(["rev"]);
    try {
        due_on = date.fromisoformat(_invoice(app)["due_on"]);
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": "rev@example.com", "role": "reviewer"}
        );
        join_platform(app, "rev", invited["token"]);
        reason = {"slug": "nova", "reason": "Invoice unpaid after reminders."};
        # Overdue, but within the grace period.
        _on(app, due_on + timedelta(days=5));
        s = _invoice(app);
        assert s["status"] == "overdue"
            and s["days_overdue"] == 5
            and not s["suspendable"];
        assert _code(app.call("boss", "platform_suspend_cinema", reason))
            == "not_overdue";
        _on(app, due_on + timedelta(days=6));
        assert _invoice(app)["suspendable"];
        _mails(app);
        # Never the cinema itself; a reason is needed.
        assert not app.call("owner", "platform_suspend_cinema", reason)["ok"];
        assert _code(
            app.call("rev", "platform_suspend_cinema", {** reason, "reason": "no"})
        )
            == "invalid_reason";
        assert app.call("rev", "platform_suspend_cinema", reason)["ok"];
        assert _code(app.call("boss", "platform_suspend_cinema", reason))
            == "not_active";
        assert any(["is suspended" in m for m in _mails(app)]);
        # The storefront says it's unavailable, and nothing is sold.
        shown = browse(app, "public_branding", {"slug": "nova"});
        assert _code(shown) == "unavailable" , shown;
        assert not browse(app, "public_home", {"slug": "nova"})["ok"];
        holder = f"counter-{uuid.uuid4().hex}";
        held = browse(
            app,
            "hold_seats",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": holder,
                "labels": ["A4"]
            }
        );
        assert not held["ok"] , held;
        # The back office says why, to everyone; it can still pay.
        for who in ["owner", "agent"] {
            notice = app.call(who, "billing_notice", {"tenant": "nova"});
            assert notice["suspended"]
                and notice["suspended_reason"] == reason["reason"] , notice;
        }
        listed = app.call("boss", "platform_billing", {})["statements"];
        assert [
            r["cinema_state"]
            for r in listed
            if r["slug"] == "nova"
        ]
            == ["suspended"];
        started = _pay(app, number, fresh_phone());
        assert started["ok"] , started;
        assert _settled(app, started["payment"]["reference"])["status"] == "paid";
        # Reinstated: back on sale.
        assert not app.call("owner", "platform_reinstate_cinema", {"slug": "nova"})[
            "ok"
        ];
        assert app.call("boss", "platform_reinstate_cinema", {"slug": "nova"})["ok"];
        assert _code(app.call("boss", "platform_reinstate_cinema", {"slug": "nova"}))
            == "not_suspended";
        assert browse(app, "public_branding", {"slug": "nova"})["ok"];
        assert not app.call("owner", "billing_notice", {"tenant": "nova"})["suspended"];
        assert any(["is back on AfriCinemas" in m for m in _mails(app)]);
        for action in ["platform.cinema_suspended", "platform.cinema_reinstated"] {
            events = app.call(
                "boss", "platform_audit_log", {"limit": 20, "action": action}
            )["events"];
            assert [e["result"] for e in events].count("ok") == 1 , (action, events);
        }
    } finally {
        _done(app);
    }
}
