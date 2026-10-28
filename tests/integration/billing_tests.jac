"""P15.4: monthly statements and invoices.

In-process app (payment_app.jac). This month Nova sells online by M-Pesa, and at the
box office for cash and by M-Pesa; a payment that fails sells nothing; part of the
online order is refunded by M-Pesa. Before anything is issued its Billing page is
empty. Run as of the 2nd
of next month, the billing job issues one statement for this month whose totals match
the orders exactly, with an AC invoice number, due 5 days after it's issued, and to
AfriCinemas' (placeholder) paybill. Running it again issues nothing. Next month a
refund credits more fee back: the statement after that has the credit, owes nothing,
carries the credit forward and takes the next number, while the first is unchanged.
A month with nothing on it gets no statement. The statement agrees with that month's
Reports. Only Nova's own finance readers see its statements (owner, general and finance
managers, auditors; not its box office, ushers or content managers, nor another cinema);
platform staff, reviewers too, see every cinema's and their PDFs, only a super admin
issues them by hand, and that's in the platform audit log. The PDF has the invoice's
number, figures, due date, how to pay and each order.

Once VAT is ticked on the registrations checklist, a statement adds 16% of the fees;
AfriCinemas' paybill and the business's registered name are on it. Unticking VAT and
changing the paybill afterwards don't change a statement already issued.
"""

import os;
import uuid;
import base64;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, open_cinema_for }
import from tests.support.payment_setup {
    paying_cinema,
    paid,
    settle,
    hire,
    fresh_phone
}
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }
import from tests.support.verification_setup { DETAILS }
import from core.money { div_half_up }
import from core.billing.billing_api { kes }

glob NAIROBI: ZoneInfo = ZoneInfo("Africa/Nairobi");

def _second_of(months_ahead: int) -> datetime {
    # 09:00 on the 2nd of the month `months_ahead` after this one, in Nairobi.
    day = datetime.now(NAIROBI).replace(
        day=1, hour=9, minute=0, second=0, microsecond=0
    );
    for _ in range(months_ahead) {
        day = (day + timedelta(days=32)).replace(day=1);
    }
    return day.replace(day=2);
}

def _orders(app: Served, screening: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return [
        o
        for o in browse(
            app, "t_order_fees", {"slug": "nova", "screening_id": screening}
        )
        if o["status"] == "confirmed"
    ];
}

def _cash_sale(app: Served, screening: str, seat: str) {
    holder = f"counter-{uuid.uuid4().hex}";
    _counter_order(app, screening, seat, holder);
    sold = app.call(
        "agent",
        "sell_for_cash",
        {"tenant": "nova", "screening_id": screening, "holder": holder, "email": ""}
    );
    assert sold["ok"] , sold;
}

def _counter_order(app: Served, screening: str, seat: str, holder: str) {
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
}

def _mpesa_sale(app: Served, screening: str, seat: str, phone: str) {
    # The box office sells `seat` by M-Pesa; Safaricom says how it went (`phone`
    # 254700000001 fails).
    holder = f"counter-{uuid.uuid4().hex}";
    _counter_order(app, screening, seat, holder);
    started = app.call(
        "agent",
        "sell_with_mpesa",
        {
            "tenant": "nova",
            "screening_id": screening,
            "holder": holder,
            "phone": phone,
            "email": ""
        }
    );
    assert started["ok"] , started;
    settle(app, screening, started["payment"]["reference"]);
}

def _pdf_text(app: Served, who: str, name: str, body: dict[str, str]) -> bytes {
    got = app.call(who, name, body);
    assert got["ok"] and got["filename"].endswith(".pdf") , got;
    raw = base64.b64decode(got["pdf"]);
    assert raw.startswith(b"%PDF-1.4") and raw.endswith(b"%%EOF\n");
    return raw;
}

def _refund(app: Served, screening: str, reference: str, cents: int) -> dict[str, any] {  # jac:ignore[W1037]
    return browse(
        app,
        "t_refund",
        {
            "slug": "nova",
            "screening_id": screening,
            "reference": reference,
            "amount_cents": cents,
            "method": "mpesa",
            "platform_failure": False
        }
    );
}

test "a month's orders give one statement and invoice that match them, issued once" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, screening) = paying_cinema(
        ["agent", "rival", "finance", "gm", "auditor", "usher", "content"]
    );
    try {
        super_admin(app, "boss", "boss@example.com");
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "finance", "finance_manager", "");
        hire(app, "gm", "general_manager", "");
        hire(app, "auditor", "auditor", "");
        hire(app, "usher", "usher", nova.venue);
        hire(app, "content", "content_manager", "");
        open_cinema_for(app, "rival", "rift", "Rift");
        # Before anything is issued: an empty Billing page, and its terms.
        empty = app.call("owner", "billing", {"tenant": "nova"});
        assert empty["ok"] and empty["statements"] == [] , empty;
        assert empty["due_days"] == 5 and empty["paybill"] == "000000";
        assert empty["paybill_is_placeholder"];
        paid(app, screening);
        _cash_sale(app, screening, "A3");
        _mpesa_sale(app, screening, "A4", fresh_phone());
        # A payment that fails sells nothing.
        _mpesa_sale(app, screening, "A5", "254700000001");
        orders = _orders(app, screening);
        assert len(orders) == 3 , orders;
        online = [
            o
            for o in orders
            if o["fee_detail"]["channel"] == "online"
        ][0];
        counters = [
            o
            for o in orders
            if o["fee_detail"]["channel"] == "counter"
        ];
        assert len(counters) == 2
            and counters[0]["total_cents"] == counters[1]["total_cents"];
        counter = counters[0];
        refunded = _refund(app, screening, online["reference"], 500);
        # Nothing is issued for a month still going.
        assert browse(
            app, "t_issue_statements", {"at": datetime.now(NAIROBI).isoformat()}
        )
            == [];
        made = browse(app, "t_issue_statements", {"at": _second_of(1).isoformat()});
        assert len(made) == 1 and made[0].startswith("AC") , made;
        number = made[0];
        # Again, by another server copy: nothing more.
        assert browse(app, "t_issue_statements", {"at": _second_of(1).isoformat()})
            == [];
        got = app.call("owner", "billing", {"tenant": "nova"});
        assert got["ok"] and len(got["statements"]) == 1 , got;
        assert got["paybill_is_placeholder"] and got["due_days"] == 5;
        s = got["statements"][0];
        f = s["figures"];
        fees = sum(
            [sum([a for (_, a) in o["entries"]]) for o in _orders(app, screening)]
        );
        assert s["number"] == number
            and s["month"] == datetime.now(NAIROBI).strftime("%Y-%m");
        assert s["issued_on"] == _second_of(1).date().isoformat();
        assert s["due_on"] == (_second_of(1) + timedelta(days=5)).date().isoformat();
        assert f["bookings"] == 3;
        assert f["online_cents"] == online["total_cents"];
        assert f["counter_cash_cents"] == counter["total_cents"];
        assert f["counter_mpesa_cents"] == counter["total_cents"];
        assert f["gross_cents"] == online["total_cents"] + 2 * counter["total_cents"];
        assert f["refunds_cents"] == 500;
        assert f["net_cents"] == f["gross_cents"] - 500;
        assert f["fees_charged_cents"]
            == online["fee_cents"] + 2 * counter["fee_cents"];
        assert f["fees_credited_cents"] == refunded["fee_credited_cents"];
        assert f["fees_cents"] == fees;
        # No VAT until AfriCinemas registers for it.
        assert s["vat_bp"] == 0 and f["vat_cents"] == 0;
        assert f["due_cents"] == fees and f["carried_forward_cents"] == 0;
        # Its lines are its orders (not the one that failed), and add up to it.
        lines = {l["reference"]: l for l in s["lines"]};
        assert set(lines.keys()) == {o["reference"] for o in orders};
        assert sum([l["paid_cents"] for l in s["lines"]]) == f["gross_cents"];
        assert sum([l["refunded_cents"] for l in s["lines"]]) == f["refunds_cents"];
        assert sum([l["fee_cents"] for l in s["lines"]]) == f["fees_cents"];
        assert lines[online["reference"]]["refunded_cents"] == 500;
        assert sorted([lines[c["reference"]]["channel"] for c in counters])
            == ["counter_cash", "counter_mpesa"];
        assert lines[online["reference"]]["channel"] == "online";
        # The same as the month's Reports.
        today = datetime.now(NAIROBI).date();
        shown = app.call(
            "owner",
            "sales_report",
            {
                "tenant": "nova",
                "date_from": today.replace(day=1).isoformat(),
                "date_to": today.isoformat()
            }
        )["report"];
        assert shown["takings"]["gross_cents"] == f["gross_cents"] , shown["takings"];
        assert shown["takings"]["refunds_cents"] == f["refunds_cents"];
        assert shown["takings"]["net_cents"] == f["net_cents"];
        assert shown["takings"]["counter_cents"]
            == f["counter_cash_cents"] + f["counter_mpesa_cents"];
        assert shown["takings"]["online_cents"] == f["online_cents"];
        assert shown["fees"]["fees_cents"] == f["fees_cents"] , shown["fees"];
        # The cinema's finance readers see it.
        for who in ["owner", "finance", "gm", "auditor"] {
            seen = app.call(who, "billing", {"tenant": "nova"});
            assert seen["ok"] and seen["statements"][0] == s , (who, seen);
            assert app.call(who, "billing_pdf", {"tenant": "nova", "number": number})[
                "ok"
            ] , who;
        }
        # Nobody else at the cinema, nor another cinema.
        for who in ["agent", "usher", "content", "rival"] {
            assert not app.call(who, "billing", {"tenant": "nova"})["ok"] , who;
            assert not app.call(
                who, "billing_pdf", {"tenant": "nova", "number": number}
            )["ok"] , who;
        }
        assert app.call("rival", "billing", {"tenant": "rift"})["statements"] == [];
        # A number that isn't Nova's.
        assert not app.call(
            "owner", "billing_pdf", {"tenant": "nova", "number": "AC999999"}
        )["ok"];
        # The PDF: the invoice, its figures, when and how to pay, and every order.
        raw = _pdf_text(
            app, "owner", "billing_pdf", {"tenant": "nova", "number": number}
        );
        due = datetime.fromisoformat(s["due_on"]);
        for text in [
            f"Statement and invoice {number}",
            "Nova Cinemas",
            kes(f["gross_cents"]),
            kes(f["fees_cents"]),
            kes(f["due_cents"]),
            "Box office, M-Pesa",
            "Box office, cash",
            f"By {due.day} {due.strftime('%b')} {due.year}, from your Billing page: Pay now sends an M-Pesa prompt for {kes(
                s['payable_cents']
            )}",
            f"to your phone, to Paybill 000000, account number {number}.",
            "No VAT: AfriCinemas isn't registered for VAT yet."
        ] {
            assert text.encode("cp1252") in raw , text;
        }
        for o in orders {
            assert o["reference"].encode() in raw , o["reference"];
        }
        # Platform staff see every cinema's, reviewers too; only a super admin issues
        # them by hand, and that's in the platform audit log.
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": "rev@example.com", "role": "reviewer"}
        );
        assert invited["ok"] , invited;
        join_platform(app, "rev", invited["token"]);
        for who in ["boss", "rev"] {
            listed = app.call(who, "platform_billing", {});
            assert listed["ok"] and listed["paybill_is_placeholder"] , listed;
            mine = [
                r
                for r in listed["statements"]
                if r["slug"] == "nova"
            ];
            assert [r["number"] for r in mine] == [number] , listed;
            assert mine[0]["figures"] == f and "lines" not in mine[0];
            assert _pdf_text(app, who, "platform_billing_pdf", {"number": number})
                == raw;
        }
        assert not app.call("boss", "platform_billing_pdf", {"number": "AC999999"})[
            "ok"
        ];
        for who in ["owner", "rival"] {
            assert not app.call(who, "platform_billing", {})["ok"] , who;
            assert not app.call(who, "platform_billing_pdf", {"number": number})["ok"];
            assert not app.call(who, "platform_issue_statements", {})["ok"] , who;
        }
        assert not app.call("rev", "platform_issue_statements", {})["ok"];
        assert app.call("boss", "platform_issue_statements", {})["issued"] == [];
        logged = app.call(
            "boss",
            "platform_audit_log",
            {"limit": 50, "action": "platform.statements_issued"}
        );
        assert len(logged["events"]) == 1 , logged;
        assert logged["events"][0]["resource_type"] == "billing";
        # Next month, another M-Pesa refund: its credit is on the next statement.
        hours = int((_second_of(1) - datetime.now(NAIROBI)).total_seconds() // 3600)
            + 1;
        assert app.call("owner", "t_clock_ahead", {"hours": hours});
        later = _refund(app, screening, online["reference"], 1000);
        assert later["fee_credited_cents"] > 0 , later;
        made = browse(app, "t_issue_statements", {"at": _second_of(2).isoformat()});
        assert made == [f"AC{int(number[2:]) + 1:06d}"] , (made, number);
        both = app.call("owner", "billing", {"tenant": "nova"})["statements"];
        assert [b["number"] for b in both] == [made[0], number];
        g = both[0]["figures"];
        assert g["bookings"] == 0 and g["refunds_cents"] == 1000;
        assert g["fees_cents"] == 0 - later["fee_credited_cents"];
        assert g["due_cents"] == 0;
        assert g["carried_forward_cents"] == g["fees_cents"];
        # The first never changes.
        assert both[1] == s;
        # A month with nothing on it gets nothing, the credit still to come.
        assert browse(app, "t_issue_statements", {"at": _second_of(3).isoformat()})
            == [];
    } finally {
        app.call("owner", "t_clock_reset");
        os.environ.pop(ADMINS_ENV, None);
        os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
        app.close();
    }
}

test "VAT once registered, the paybill and business name, kept as they were issued" {
    (app, nova, screening) = paying_cinema(["agent"]);
    try {
        super_admin(app, "boss", "boss@example.com");
        hire(app, "agent", "box_office_agent", nova.venue);
        assert app.call(
            "owner", "save_verification", {"tenant": "nova", "details": DETAILS}
        )["ok"];
        assert app.call(
            "boss",
            "tick_registration",
            {"key": "vat", "done": True, "reference": "VAT-0001"}
        )["ok"];
        os.environ["AFRICINEMAS_BILLING_PAYBILL"] = "123456";
        paid(app, screening);
        _cash_sale(app, screening, "A3");
        fees = sum(
            [sum([a for (_, a) in o["entries"]]) for o in _orders(app, screening)]
        );
        made = browse(app, "t_issue_statements", {"at": _second_of(1).isoformat()});
        assert len(made) == 1 , made;
        got = app.call("owner", "billing", {"tenant": "nova"});
        assert got["paybill"] == "123456" and not got["paybill_is_placeholder"];
        s = got["statements"][0];
        f = s["figures"];
        assert s["vat_bp"] == 1600 and f["fees_cents"] == fees;
        assert f["vat_cents"] == div_half_up(fees * 1600, 10000) , f;
        assert f["due_cents"] == fees + f["vat_cents"];
        assert s["paybill"] == "123456" and not s["paybill_is_placeholder"];
        assert s["business_name"] == DETAILS["registered_name"];
        raw = _pdf_text(
            app, "owner", "billing_pdf", {"tenant": "nova", "number": made[0]}
        );
        for text in [
            "VAT at 16%",
            kes(f["vat_cents"]),
            kes(f["due_cents"]),
            f"to Paybill 123456, account number {made[0]}",
            f"For: {DETAILS['registered_name']}",
            "Cinema: Nova Cinemas"
        ] {
            assert text.encode("cp1252") in raw , text;
        }
        assert b"No VAT" not in raw;
        # Unticked and changed later: the statement stays as it was issued.
        assert app.call(
            "boss", "tick_registration", {"key": "vat", "done": False, "reference": ""}
        )["ok"];
        os.environ.pop("AFRICINEMAS_BILLING_PAYBILL", None);
        again = app.call("owner", "billing", {"tenant": "nova"});
        assert again["paybill_is_placeholder"] and again["statements"][0] == s;
        assert _pdf_text(
            app, "owner", "billing_pdf", {"tenant": "nova", "number": made[0]}
        )
            == raw;
    } finally {
        os.environ.pop("AFRICINEMAS_BILLING_PAYBILL", None);
        os.environ.pop(ADMINS_ENV, None);
        app.close();
    }
}
