"""P15.4: monthly statements and invoices.

In-process app (payment_app.jac). This month Nova sells online by M-Pesa and for cash
at the box office, and refunds part of the online order by M-Pesa. Run as of the 2nd
of next month, the billing job issues one statement for this month whose totals match
the orders exactly, with an AC invoice number, due 5 days after it's issued, and to
AfriCinemas' (placeholder) paybill. Running it again issues nothing. Next month a
refund credits more fee back: the statement after that has the credit, owes nothing,
carries the credit forward and takes the next number, while the first is unchanged.
A month with nothing on it gets no statement. Only Nova's own finance staff see its
statements (not its box office, not another cinema); platform staff see every cinema's,
and only a super admin issues them by hand. The PDF is a PDF with the invoice's number.
"""

import os;
import uuid;
import base64;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, open_cinema_for }
import from tests.support.payment_setup { paying_cinema, paid, hire, ANNA }
import from tests.support.platform_setup { ADMINS_ENV, super_admin }

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
    (app, nova, screening) = paying_cinema(["agent", "rival", "finance"]);
    try {
        super_admin(app, "boss", "boss@example.com");
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "finance", "finance_manager", "");
        open_cinema_for(app, "rival", "rift", "Rift");
        paid(app, screening);
        _cash_sale(app, screening, "A3");
        orders = _orders(app, screening);
        assert len(orders) == 2 , orders;
        online = [
            o
            for o in orders
            if o["fee_detail"]["channel"] == "online"
        ][0];
        counter = [
            o
            for o in orders
            if o["fee_detail"]["channel"] == "counter"
        ][0];
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
        assert f["bookings"] == 2;
        assert f["online_cents"] == online["total_cents"];
        assert f["counter_cash_cents"] == counter["total_cents"];
        assert f["counter_mpesa_cents"] == 0;
        assert f["gross_cents"] == online["total_cents"] + counter["total_cents"];
        assert f["refunds_cents"] == 500;
        assert f["net_cents"] == f["gross_cents"] - 500;
        assert f["fees_charged_cents"] == online["fee_cents"] + counter["fee_cents"];
        assert f["fees_credited_cents"] == refunded["fee_credited_cents"];
        assert f["fees_cents"] == fees;
        # No VAT until AfriCinemas registers for it.
        assert s["vat_bp"] == 0 and f["vat_cents"] == 0;
        assert f["due_cents"] == fees and f["carried_forward_cents"] == 0;
        # Its lines are its orders, and add up to it.
        lines = {l["reference"]: l for l in s["lines"]};
        assert set(lines.keys()) == {online["reference"], counter["reference"]};
        assert sum([l["paid_cents"] for l in s["lines"]]) == f["gross_cents"];
        assert sum([l["fee_cents"] for l in s["lines"]]) == f["fees_cents"];
        assert lines[online["reference"]]["refunded_cents"] == 500;
        assert lines[counter["reference"]]["channel"] == "counter_cash";
        # The finance manager sees it; the box office and another cinema don't.
        assert app.call("finance", "billing", {"tenant": "nova"})["statements"][0][
            "number"
        ]
            == number;
        assert not app.call("agent", "billing", {"tenant": "nova"})["ok"];
        assert not app.call("rival", "billing", {"tenant": "nova"})["ok"];
        assert not app.call(
            "rival", "billing_pdf", {"tenant": "nova", "number": number}
        )["ok"];
        assert app.call("rival", "billing", {"tenant": "rift"})["statements"] == [];
        # The PDF.
        pdf = app.call("owner", "billing_pdf", {"tenant": "nova", "number": number});
        assert pdf["ok"] and pdf["filename"].endswith(".pdf") , pdf;
        raw = base64.b64decode(pdf["pdf"]);
        assert raw.startswith(b"%PDF-1.4") and number.encode() in raw;
        assert online["reference"].encode() in raw;
        # Platform staff see every cinema's; only a super admin issues by hand.
        listed = app.call("boss", "platform_billing", {});
        assert [
            r["number"]
            for r in listed["statements"]
            if r["slug"] == "nova"
        ]
            == [number] , listed;
        assert app.call("boss", "platform_billing_pdf", {"number": number})["ok"];
        assert not app.call("owner", "platform_billing", {})["ok"];
        assert not app.call("owner", "platform_issue_statements", {})["ok"];
        assert app.call("boss", "platform_issue_statements", {})["issued"] == [];
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
