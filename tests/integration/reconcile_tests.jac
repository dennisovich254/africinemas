"""P15.6: reconciliation and AfriCinemas' takings.

In-process app (payment_app.jac), the simulated M-Pesa told to change its mind.

- The daily check asks M-Pesa again about each payment, once: matching ones make no
  exception, nor does one M-Pesa no longer knows (it's asked again later); one M-Pesa now says wasn't paid, one for another amount, one it says was
  paid though nothing was sold, and a receipt on two payments each make one. Running
  again adds nothing.
- An M-Pesa statement is matched by receipt for the time it covers: money no order
  took, an amount that differs and a payment of ours that isn't on it make exceptions;
  test payments (account TEST) are skipped; uploading again adds nothing; a file that
  isn't a statement is refused.
- A cash-up compares the count with the cash that member sold since their last one;
  a difference is an exception.
- Only the cinema's finance readers see and resolve its exceptions (with a note, once),
  and upload statements; the box office counts its cash. Platform staff see every
  cinema's open exceptions.
- AfriCinemas' takings: fees earned, invoiced, paid and overdue per month and cinema;
  what's invoiced is the sum of the invoices.
"""

import os;
import uuid;
import from datetime { datetime, timedelta, date }
import from zoneinfo { ZoneInfo }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, open_cinema_for }
import from tests.support.payment_setup {
    paying_cinema,
    pay,
    settle,
    hire,
    fresh_phone
}
import from tests.support.platform_setup { ADMINS_ENV, super_admin }

glob NAIROBI: ZoneInfo = ZoneInfo("Africa/Nairobi");

def _code(got: dict[str, any]) -> str {  # jac:ignore[W1037]
    return got["error"]["code"] if not got["ok"] else "";
}

def _counter_order(app: Served, screening: str, seat: str) -> str {
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
    return holder;
}

def _mpesa_sale(app: Served, screening: str, seat: str, phone: str) -> str {
    # The box office sells `seat` by M-Pesa from `phone`; its payment's reference.
    holder = _counter_order(app, screening, seat);
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
    return started["payment"]["reference"];
}

def _cash_sale(app: Served, screening: str, seat: str) {
    holder = _counter_order(app, screening, seat);
    sold = app.call(
        "agent",
        "sell_for_cash",
        {"tenant": "nova", "screening_id": screening, "holder": holder, "email": ""}
    );
    assert sold["ok"] , sold;
}

def _exceptions(app: Served, who: str = "owner") -> list[dict[str, any]] {  # jac:ignore[W1037]
    got = app.call(who, "reconciliation", {"tenant": "nova"});
    assert got["ok"] , got;
    return got["exceptions"];
}

def _kinds(rows: list[dict[str, any]]) -> list[str] {  # jac:ignore[W1037]
    return sorted([r["kind"] for r in rows]);
}

def _receipts(app: Served, screening: str) -> dict[str, str] {
    # order reference -> its M-Pesa receipt.
    return {
        ref: receipt
        for (ref, receipt) in app.call(
            "owner", "t_receipts", {"slug": "nova", "screening_id": screening}
        )
    };
}

test "the daily check asks M-Pesa again, once, and lists what doesn't add up" {
    (app, nova, screening) = paying_cinema(["agent", "rival", "finance", "usher"]);
    try {
        super_admin(app, "boss", "boss@example.com");
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "finance", "finance_manager", "");
        hire(app, "usher", "usher", nova.venue);
        open_cinema_for(app, "rival", "rift", "Rift");
        # Anna pays online, and the box office sells three seats by M-Pesa.
        anna = fresh_phone();
        started = pay(app, screening, anna);
        settle(app, screening, started["payment"]["reference"]);
        (gone, short, failed) = (fresh_phone(), fresh_phone(), "254700000001");
        _mpesa_sale(app, screening, "A3", gone);
        _mpesa_sale(app, screening, "A4", short);
        # A payment that failed: nothing sold.
        holder = _counter_order(app, screening, "A5");
        attempt = app.call(
            "agent",
            "sell_with_mpesa",
            {
                "tenant": "nova",
                "screening_id": screening,
                "holder": holder,
                "phone": failed,
                "email": ""
            }
        );
        settle(app, screening, attempt["payment"]["reference"]);
        # Before M-Pesa changes its mind, a check would find nothing; it changes now.
        assert app.call(
            "owner",
            "t_sim_change",
            {"phone": gone, "outcome": "fail", "amount_cents": 0}
        )
            == 1;
        assert app.call(
            "owner",
            "t_sim_change",
            {"phone": short, "outcome": "success", "amount_cents": 100}
        )
            == 1;
        assert app.call(
            "owner",
            "t_sim_change",
            {"phone": failed, "outcome": "success", "amount_cents": 0}
        )
            == 1;
        receipts = _receipts(app, screening);
        refs = sorted(receipts.keys());
        assert len(refs) == 3 , receipts;
        # A receipt on two payments.
        assert app.call(
            "owner",
            "t_set_receipt",
            {
                "slug": "nova",
                "screening_id": screening,
                "reference": refs[0],
                "receipt": receipts[refs[1]]
            }
        );
        # M-Pesa no longer knows Anna's payment: unchecked, never "not paid".
        assert app.call(
            "owner",
            "t_sim_change",
            {"phone": anna, "outcome": "forget", "amount_cents": 0}
        )
            == 1;
        assert _exceptions(app) == [];
        assert app.call("owner", "t_reconcile") == 4;
        found = _exceptions(app);
        assert _kinds(found)
            == ["amount_differs", "no_order", "not_paid", "receipt_twice"] , found;
        short_one = [
            e
            for e in found
            if e["kind"] == "amount_differs"
        ][0];
        assert short_one["found_cents"] == 100 and short_one["expected_cents"] > 100;
        twice = [
            e
            for e in found
            if e["kind"] == "receipt_twice"
        ][0];
        assert twice["receipt"] == receipts[refs[1]];
        assert all([e["status"] == "open" and e["label"] for e in found]);
        # Again: nothing new; each payment was checked once.
        assert app.call("owner", "t_reconcile") == 0;
        assert len(_exceptions(app)) == 4;
        # The finance manager sees them; the box office, ushers and other cinemas don't.
        assert len(_exceptions(app, "finance")) == 4;
        for who in ["agent", "usher", "rival"] {
            assert not app.call(who, "reconciliation", {"tenant": "nova"})["ok"] , who;
        }
        assert app.call("rival", "reconciliation", {"tenant": "rift"})["exceptions"]
            == [];
        # Resolved with a note, once.
        target = found[0]["exception_id"];
        body = {"tenant": "nova", "exception_id": target, "note": ""};
        assert _code(app.call("owner", "resolve_exception", body)) == "invalid_note";
        assert not app.call("agent", "resolve_exception", {** body, "note": "Sorted"})[
            "ok"
        ];
        assert not app.call("rival", "resolve_exception", {** body, "note": "Sorted"})[
            "ok"
        ];
        done = app.call(
            "finance", "resolve_exception", {** body, "note": "Refunded on M-Pesa."}
        );
        assert done["ok"] and done["exception"]["status"] == "resolved" , done;
        assert done["exception"]["resolved_note"] == "Refunded on M-Pesa.";
        assert _code(app.call("owner", "resolve_exception", {** body, "note": "Again"}))
            == "already_resolved";
        assert app.call("owner", "reconciliation", {"tenant": "nova"})["open"] == 3;
        logged = [
            e["action"]
            for e in app.call("owner", "audit_log", {"tenant": "nova", "limit": 50})[
                "events"
            ]
        ];
        assert "reconcile.resolved" in logged , logged;
        # Platform staff see the open ones, with the cinema.
        listed = app.call("boss", "platform_reconciliation", {});
        mine = [
            e
            for e in listed["exceptions"]
            if e["slug"] == "nova"
        ];
        assert len(mine) == 3
            and target not in [e["exception_id"] for e in mine] , listed;
        assert not app.call("owner", "platform_reconciliation", {})["ok"];
    } finally {
        os.environ.pop(ADMINS_ENV, None);
        app.close();
    }
}

def _statement(rows: list[list[str]]) -> str {
    # The M-Pesa portal's CSV: a few lines about the account, then the table.
    lines = [
        "Organisation Name,Nova Cinemas Ltd",
        "Short Code,600100",
        "",
        "Receipt No.,Completion Time,Initiation Time,Details,Transaction Status,Paid In,Withdrawn,Balance,A/C No."
    ];
    for r in rows {
        lines.append(",".join(r));
    }
    return "\n".join(lines) + "\n";
}

test "an uploaded M-Pesa statement is matched by receipt, for the time it covers" {
    (app, nova, screening) = paying_cinema(["agent", "rival"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        open_cinema_for(app, "rival", "rift", "Rift");
        started = pay(app, screening, fresh_phone());
        settle(app, screening, started["payment"]["reference"]);
        _mpesa_sale(app, screening, "A3", fresh_phone());
        _mpesa_sale(app, screening, "A4", fresh_phone());
        fees = {
            o["reference"]: o["total_cents"]
            for o in browse(
                app, "t_order_fees", {"slug": "nova", "screening_id": screening}
            )
            if o["status"] == "confirmed"
        };
        receipts = _receipts(app, screening);
        (first, second, third) = sorted(receipts.keys());
        local = datetime.now(NAIROBI).replace(tzinfo=None);
        at = lambda (minutes: int) -> str { return (
            local + timedelta(minutes=minutes)
        ).strftime(
            "%Y-%m-%d %H:%M:%S"
        ); };
        shillings = lambda (cents: int) -> str { return f"{cents // 100:,}.{cents
            % 100:02d}"; };
        csv_text = _statement(
            [
                # Ours, the same amount.
                [
                    receipts[first],
                    at(-90),
                    at(-90),
                    "Pay Bill",
                    "Completed",
                    '"' + shillings(fees[first]) + '"',
                    "",
                    "",
                    first
                ],
                # Ours, another amount.
                [
                    receipts[second],
                    at(-80),
                    at(-80),
                    "Pay Bill",
                    "Completed",
                    "1.00",
                    "",
                    "",
                    second
                ],
                # Not ours: paid at the paybill by hand.
                [
                    "QHX0000001",
                    at(-70),
                    at(-70),
                    "Pay Bill",
                    "Completed",
                    "500.00",
                    "",
                    "",
                    "SEAT A9"
                ],
                # The KES 1 test payment: skipped.
                [
                    "QHX0000002",
                    at(-60),
                    at(-60),
                    "Pay Bill",
                    "Completed",
                    "1.00",
                    "",
                    "",
                    "TEST"
                ],
                # Not completed: skipped.
                [
                    "QHX0000003",
                    at(-50),
                    at(-50),
                    "Pay Bill",
                    "Failed",
                    "200.00",
                    "",
                    "",
                    "X"
                ],
                # A withdrawal: no money in.
                [
                    "QHX0000004",
                    at(-40),
                    at(-40),
                    "Withdraw",
                    "Completed",
                    "",
                    "100.00",
                    "",
                    ""
                ],
                [
                    "QHX0000005",
                    at(60),
                    at(60),
                    "Pay Bill",
                    "Completed",
                    "10.00",
                    "",
                    "",
                    "LATE"
                ]
            ]
        );
        # Ours not on it (the third) within the time it covers.
        assert not app.call(
            "agent", "upload_mpesa_statement", {"tenant": "nova", "csv_text": csv_text}
        )["ok"];
        assert not app.call(
            "rival", "upload_mpesa_statement", {"tenant": "nova", "csv_text": csv_text}
        )["ok"];
        got = app.call(
            "owner", "upload_mpesa_statement", {"tenant": "nova", "csv_text": csv_text}
        );
        assert got["ok"] , got;
        assert got["rows"] == 4
            and got["matched"] == 1
            and got["exceptions"] == 4 , got;
        found = _exceptions(app);
        assert _kinds(found)
            == [
                "amount_differs",
                "not_in_app",
                "not_in_app",
                "not_in_statement"
            ] , found;
        missing = [
            e
            for e in found
            if e["kind"] == "not_in_statement"
        ][0];
        assert missing["reference"] == third and missing["source"] == "statement";
        stranger = [
            e
            for e in found
            if e["receipt"] == "QHX0000001"
        ][0];
        assert stranger["found_cents"] == 50000;
        differs = [
            e
            for e in found
            if e["kind"] == "amount_differs"
        ][0];
        assert differs["expected_cents"] == fees[second]
            and differs["found_cents"] == 100;
        # Again: nothing new.
        again = app.call(
            "owner", "upload_mpesa_statement", {"tenant": "nova", "csv_text": csv_text}
        );
        assert again["exceptions"] == 0 and len(_exceptions(app)) == 4;
        # Not a statement, or nothing in it.
        assert _code(
            app.call(
                "owner",
                "upload_mpesa_statement",
                {"tenant": "nova", "csv_text": "a,b\n1,2\n"}
            )
        )
            == "not_a_statement";
        assert _code(
            app.call(
                "owner",
                "upload_mpesa_statement",
                {"tenant": "nova", "csv_text": _statement([])}
            )
        )
            == "empty_statement";
        assert _code(
            app.call(
                "owner", "upload_mpesa_statement", {"tenant": "nova", "csv_text": " "}
            )
        )
            == "empty_statement";
        logged = [
            e["action"]
            for e in app.call("owner", "audit_log", {"tenant": "nova", "limit": 50})[
                "events"
            ]
        ];
        assert "reconcile.statement_uploaded" in logged;
    } finally {
        app.close();
    }
}

test "a cash-up compares the count with the cash that member sold since their last" {
    (app, nova, screening) = paying_cinema(["agent", "usher"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "usher", "usher", nova.venue);
        _cash_sale(app, screening, "A3");
        sold = [
            o["total_cents"]
            for o in browse(
                app, "t_order_fees", {"slug": "nova", "screening_id": screening}
            )
            if o["status"] == "confirmed"
        ];
        price = sold[0];
        # Right: no exception.
        right = app.call(
            "agent", "count_cash", {"tenant": "nova", "counted_cents": price}
        );
        assert right["ok"] and right["cash_up"]["difference_cents"] == 0 , right;
        assert right["cash_up"]["expected_cents"] == price
            and right["cash_up"]["since"] == "";
        assert _exceptions(app) == [];
        # Another sale, and KES 100 short.
        _cash_sale(app, screening, "A4");
        short = app.call(
            "agent", "count_cash", {"tenant": "nova", "counted_cents": price - 10000}
        );
        assert short["cash_up"]["expected_cents"] == price , short;
        assert short["cash_up"]["difference_cents"] == -10000;
        assert short["cash_up"]["since"] == right["cash_up"]["at"];
        found = _exceptions(app);
        assert _kinds(found) == ["cash_short"] , found;
        assert found[0]["expected_cents"] == price
            and found[0]["found_cents"] == price - 10000;
        assert found[0]["source"] == "cash_up" and found[0]["detail"];
        # Nothing sold since: nothing expected; over is an exception too.
        over = app.call(
            "agent", "count_cash", {"tenant": "nova", "counted_cents": 5000}
        );
        assert over["cash_up"]["expected_cents"] == 0;
        assert _kinds(_exceptions(app)) == ["cash_over", "cash_short"];
        # Not an amount; not the usher (no sales).
        assert _code(
            app.call("agent", "count_cash", {"tenant": "nova", "counted_cents": -1})
        )
            == "invalid_amount";
        assert not app.call(
            "usher", "count_cash", {"tenant": "nova", "counted_cents": 0}
        )["ok"];
        ups = app.call("owner", "reconciliation", {"tenant": "nova"})["cash_ups"];
        assert len(ups) == 3 and ups[1]["difference_cents"] == -10000 , ups;
        assert ups[0]["member"];
    } finally {
        app.close();
    }
}

def _second_of(months_ahead: int) -> datetime {
    day = datetime.now(NAIROBI).replace(
        day=1, hour=9, minute=0, second=0, microsecond=0
    );
    for _ in range(months_ahead) {
        day = (day + timedelta(days=32)).replace(day=1);
    }
    return day.replace(day=2);
}

test "AfriCinemas' takings: fees earned, invoiced, paid and overdue, per month and cinema" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, screening) = paying_cinema(["agent"]);
    try {
        super_admin(app, "boss", "boss@example.com");
        hire(app, "agent", "box_office_agent", nova.venue);
        started = pay(app, screening, fresh_phone());
        settle(app, screening, started["payment"]["reference"]);
        _cash_sale(app, screening, "A3");
        fees = sum(
            [
                sum([a for (_, a) in o["entries"]])
                for o in browse(
                    app, "t_order_fees", {"slug": "nova", "screening_id": screening}
                )
            ]
        );
        month = datetime.now(NAIROBI).strftime("%Y-%m");
        before = app.call("boss", "platform_takings", {});
        assert before["ok"] , before;
        nova_row = [
            c
            for c in before["cinemas"]
            if c["slug"] == "nova"
        ][0];
        assert nova_row["earned_cents"] == fees and nova_row["invoiced_cents"] == 0;
        made = app.call(
            "owner", "t_issue_statements", {"at": _second_of(1).isoformat()}
        );
        assert len(made) == 1;
        statement = app.call("owner", "billing", {"tenant": "nova"})["statements"][0];
        due_on = date.fromisoformat(statement["due_on"]);
        at = datetime(due_on.year, due_on.month, due_on.day, 10, tzinfo=NAIROBI)
            + timedelta(days=1);
        assert app.call("owner", "t_clock_at", {"at": at.isoformat()});
        took = app.call("boss", "platform_takings", {});
        nova_row = [
            c
            for c in took["cinemas"]
            if c["slug"] == "nova"
        ][0];
        row = [
            m
            for m in nova_row["months"]
            if m["month"] == month
        ][0];
        assert row["earned_cents"] == fees
            and row["invoiced_cents"] == statement["payable_cents"];
        assert row["overdue_cents"] == statement["payable_cents"]
            and row["paid_cents"] == 0;
        # The platform's invoiced is the sum of every invoice.
        invoices = app.call("boss", "platform_billing", {})["statements"];
        assert took["totals"]["invoiced_cents"]
            == sum([s["payable_cents"] for s in invoices]);
        assert took["totals"]["earned_cents"]
            == sum([c["earned_cents"] for c in took["cinemas"]]);
        # Paid: from overdue to paid.
        paying = app.call(
            "owner",
            "pay_invoice",
            {"tenant": "nova", "number": made[0], "phone": fresh_phone()}
        );
        assert app.call(
            "owner",
            "invoice_payment",
            {"tenant": "nova", "reference": paying["payment"]["reference"]}
        )["status"]
            == "paid";
        paid = [
            c
            for c in app.call("boss", "platform_takings", {})["cinemas"]
            if c["slug"] == "nova"
        ][0];
        assert paid["paid_cents"] == statement["payable_cents"]
            and paid["overdue_cents"] == 0;
        assert not app.call("owner", "platform_takings", {})["ok"];
    } finally {
        app.call("owner", "t_clock_reset");
        os.environ.pop(ADMINS_ENV, None);
        os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
        app.close();
    }
}
