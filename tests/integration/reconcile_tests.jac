"""P15.6: reconciliation and AfriCinemas' takings.

In-process app (payment_app.jac), the simulated M-Pesa told to change its mind.

- The daily check asks M-Pesa again about each payment, once: matching ones make no
  exception, nor does one M-Pesa no longer knows (it's asked again later); one M-Pesa now says wasn't paid, one for another amount, one it says was
  paid though nothing was sold, and a receipt on two payments each make one. Running
  again adds nothing.
- A cash-up compares the count with the cash that member sold since their last one;
  a difference is an exception. A count can be corrected once within 10 minutes (both
  figures kept, P15.6b); more than the cinema's limit is refused. Cash left by someone
  who didn't sign out is offered to the next agent at the venue while they're still on
  shift; once it's over it's "Cash not counted", and the next agent counts it on their
  behalf before selling for cash. Their own earlier shift's cash too. Shift length and the limit are the cinema's, set by its
  owner or admin.
- Only the cinema's finance readers see and resolve its exceptions (with a note, once),
  and the sidebar's count is theirs (0 for the rest of its staff); the box office
  counts its cash. Times come with the cinema's time zone. Platform staff see every
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
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }
import from tests.support.storefront_setup { add_screening }

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

def _new_shift(app: Served, who: str) {
    assert app.call(who, "start_shift", {"tenant": "nova"})["ok"];
}

def _sale_by(app: Served, who: str, screening: str, seat: str) {
    holder = _counter_order(app, screening, seat);
    sold = app.call(
        who,
        "sell_for_cash",
        {"tenant": "nova", "screening_id": screening, "holder": holder, "email": ""}
    );
    assert sold["ok"] , sold;
}

def _platform_member(app: Served, label: str, role: str) {
    invited = app.call(
        "boss",
        "invite_platform_member",
        {"email": f"{label}@example.com", "role": role}
    );
    assert invited["ok"] , invited;
    join_platform(app, label, invited["token"]);
}

def _actions(app: Served) -> list[str] {
    return [
        e["action"]
        for e in app.call("owner", "audit_log", {"tenant": "nova", "limit": 100})[
            "events"
        ]
    ];
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
    (app, nova, screening) = paying_cinema(
        ["agent", "rival", "finance", "usher", "auditor", "rev", "helper"]
    );
    try {
        super_admin(app, "boss", "boss@example.com");
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "finance", "finance_manager", "");
        hire(app, "usher", "usher", nova.venue);
        hire(app, "auditor", "auditor", "");
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
        assert len(_exceptions(app, "auditor")) == 4;
        for who in ["agent", "usher", "rival"] {
            assert not app.call(who, "reconciliation", {"tenant": "nova"})["ok"] , who;
        }
        assert app.call("owner", "reconciliation", {"tenant": "nova"})["timezone"]
            == "Africa/Nairobi";
        # The sidebar's count: what's open, for those who read them; 0 for the rest of
        # the staff; another cinema's owner is refused.
        for who in ["owner", "finance", "auditor"] {
            got = app.call(who, "reconciliation_open", {"tenant": "nova"});
            assert got == {"ok": True, "open": 4} , (who, got);
        }
        for who in ["agent", "usher"] {
            assert app.call(who, "reconciliation_open", {"tenant": "nova"})["open"]
                == 0;
        }
        assert not app.call("rival", "reconciliation_open", {"tenant": "nova"})["ok"];
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
        assert app.call("owner", "reconciliation_open", {"tenant": "nova"})["open"]
            == 3;
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
        assert all([e["timezone"] == "Africa/Nairobi" for e in mine]);
        assert not app.call("owner", "platform_reconciliation", {})["ok"];
        # Reviewers and support staff see it too.
        _platform_member(app, "rev", "reviewer");
        _platform_member(app, "helper", "support");
        for who in ["rev", "helper"] {
            seen = app.call(who, "platform_reconciliation", {});
            assert len(
                [
                    e
                    for e in seen["exceptions"]
                    if e["slug"] == "nova"
                ]
            )
                == 3 , (who, seen);
        }
    } finally {
        os.environ.pop(ADMINS_ENV, None);
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
        # Counting doesn't end the shift.
        assert "shift_ended" not in right;
        # Another sale, and KES 100 short.
        _cash_sale(app, screening, "A4");
        short = app.call(
            "agent", "count_cash", {"tenant": "nova", "counted_cents": price - 10000}
        );
        assert short["cash_up"]["expected_cents"] == price , short;
        assert short["cash_up"]["difference_cents"] == -10000;
        assert short["cash_up"]["since"] == right["cash_up"]["at"];
        _new_shift(app, "agent");
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
        assert over["cash_up"]["difference_cents"] == 5000;
        assert _kinds(_exceptions(app)) == ["cash_over", "cash_short"];
        _new_shift(app, "agent");
        # Nothing sold, nothing counted: it matches, and adds nothing.
        even = app.call("agent", "count_cash", {"tenant": "nova", "counted_cents": 0});
        assert even["cash_up"]["difference_cents"] == 0
            and even["cash_up"]["expected_cents"] == 0;
        assert len(_exceptions(app)) == 2;
        _new_shift(app, "agent");
        # The owner sells too, so counts their own cash (the agent's isn't theirs).
        mine = app.call("owner", "count_cash", {"tenant": "nova", "counted_cents": 0});
        assert mine["ok"] and mine["cash_up"]["expected_cents"] == 0 , mine;
        _new_shift(app, "owner");
        done = [
            e["action"]
            for e in app.call("owner", "audit_log", {"tenant": "nova", "limit": 100})[
                "events"
            ]
            if e["result"] == "ok"
        ];
        assert done.count("cash.counted") == 5 , done;
        # Not an amount; not the usher (no sales).
        assert _code(
            app.call("agent", "count_cash", {"tenant": "nova", "counted_cents": -1})
        )
            == "invalid_amount";
        assert not app.call(
            "usher", "count_cash", {"tenant": "nova", "counted_cents": 0}
        )["ok"];
        ups = app.call("owner", "reconciliation", {"tenant": "nova"})["cash_ups"];
        assert len(ups) == 5 and ups[3]["difference_cents"] == -10000 , ups;
        assert ups[0]["member"];
    } finally {
        app.close();
    }
}

test "a count ends the shift, can be corrected once, has a limit, and is missed when skipped" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    (app, nova, screening) = paying_cinema(
        ["agent", "agent2", "finance", "cinemaadmin"]
    );
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "finance", "finance_manager", "");
        hire(app, "cinemaadmin", "tenant_admin", "");
        # The rules: 8 hours and KES 500,000 unless changed; the owner and the cinema
        # admin change them; finance and the box office can only read them.
        rules = {"tenant": "nova"};
        assert app.call("agent", "box_office_rules", rules)
            == {
                "ok": True,
                "shift_hours": 8,
                "cash_count_max_cents": 50000000,
                "counter_release_hours": 2
            };
        change = {** rules, "shift_hours": 6, "cash_count_max_cents": 2000000};
        for who in ["agent", "finance"] {
            assert _code(app.call(who, "set_box_office_rules", change)) == "forbidden";
        }
        for (hours, most, code) in [
            (0, 2000000, "invalid_hours"),
            (13, 2000000, "invalid_hours"),
            (6, 99999, "invalid_limit"),
            (6, 1000000001, "invalid_limit")
        ] {
            assert _code(
                app.call(
                    "owner",
                    "set_box_office_rules",
                    {** rules, "shift_hours": hours, "cash_count_max_cents": most}
                )
            )
                == code , (hours, most);
        }
        assert app.call("cinemaadmin", "set_box_office_rules", change)["shift_hours"]
            == 6;
        # Settings saves the counter release next; it keeps the rules just saved.
        assert app.call(
            "cinemaadmin", "set_counter_release_hours", {** rules, "hours": 3}
        )["ok"];
        assert app.call("agent", "box_office_rules", rules)
            == {
                "ok": True,
                "shift_hours": 6,
                "cash_count_max_cents": 2000000,
                "counter_release_hours": 3
            };
        assert "cinema.box_office_rules_changed" in _actions(app);
        # The five-seat screen: a second showtime for more sales.
        more = add_screening(app, "owner", nova, "Rafiki", 24 * 3);
        # A new shift lasts the cinema's 6 hours.
        started = app.call("agent", "start_shift", rules);
        left = datetime.fromisoformat(started["expires_at"])
            - datetime.now(ZoneInfo("UTC"));
        assert timedelta(hours=5, minutes=50) < left <= timedelta(hours=6) , left;
        # More than KES 20,000 is refused, and saves nothing.
        _cash_sale(app, screening, "A3");
        status = app.call("agent", "cash_status", rules);
        assert status["ok"] and status["uncounted"] and not status["count_first"];
        assert status["max_cents"] == 2000000 and "expected_cents" not in status;
        too_much = app.call(
            "agent", "count_cash", {** rules, "counted_cents": 2000001}
        );
        assert _code(too_much) == "too_much" , too_much;
        assert "KES 20,000" in too_much["error"]["message"];
        assert app.call("owner", "reconciliation", rules)["cash_ups"] == [];
        # KES 100 short; corrected within 10 minutes, once: both figures kept, the
        # first count's exception settled.
        price = app.call(
            "owner", "t_order_fees", {"slug": "nova", "screening_id": screening}
        );
        price = [
            o["total_cents"]
            for o in price
            if o["status"] == "confirmed"
        ][0];
        first = app.call(
            "agent", "count_cash", {** rules, "counted_cents": price - 10000}
        );
        assert first["cash_up"]["recount_until"] , first;
        assert _kinds(_exceptions(app)) == ["cash_short"];
        fixed = app.call("agent", "recount_cash", {** rules, "counted_cents": price});
        assert fixed["ok"] , fixed;
        assert fixed["cash_up"]["counted_cents"] == price
            and fixed["cash_up"]["first_counted_cents"] == price - 10000;
        assert fixed["cash_up"]["recount_until"] == "";
        found = _exceptions(app);
        assert [(e["kind"], e["status"]) for e in found]
            == [("cash_short", "resolved")];
        assert found[0]["resolved_by"] == "the count"
            and "first counted" in found[0]["resolved_note"];
        assert _code(
            app.call("agent", "recount_cash", {** rules, "counted_cents": price})
        )
            == "too_late";
        assert "cash.recounted" in _actions(app);
        # A correction that's still off is kept; too late after 10 minutes.
        _new_shift(app, "agent");
        _cash_sale(app, screening, "A4");
        assert app.call("agent", "count_cash", {** rules, "counted_cents": price})[
            "ok"
        ];
        wrong = app.call(
            "agent", "recount_cash", {** rules, "counted_cents": price + 500}
        );
        assert wrong["ok"]
            and _kinds(
                [
                    e
                    for e in _exceptions(app)
                    if e["status"] == "open"
                ]
            )
                == ["cash_over"];
        _new_shift(app, "agent");
        _cash_sale(app, screening, "A5");
        assert app.call("agent", "count_cash", {** rules, "counted_cents": price})[
            "ok"
        ];
        app.call(
            "owner",
            "t_clock_at",
            {"at": (datetime.now(ZoneInfo("UTC")) + timedelta(minutes=11)).isoformat()}
        );
        assert _code(app.call("agent", "recount_cash", {** rules, "counted_cents": 0}))
            == "too_late";
        app.call("owner", "t_clock_reset");
        # Forgot to sign out: while they're still on shift, the next agent at the
        # venue is offered their cash, and may still sell; once their shift is over,
        # the manager sees "Cash not counted" (once) and the next agent must count it.
        _new_shift(app, "agent");
        _cash_sale(app, more, "A1");
        assert app.call("owner", "t_cash_check") == 0;
        hire(app, "agent2", "box_office_agent", nova.venue);
        offered = app.call("agent2", "cash_status", rules)["left_behind"];
        assert len(offered) == 1 and offered[0]["on_shift"] , offered;
        assert offered[0]["member"];
        gone_id = offered[0]["member_id"];
        _sale_by(app, "agent2", more, "A2");
        assert app.call("agent", "end_shift", rules)["ok"];
        assert app.call("owner", "t_cash_check") == 1;
        assert app.call("owner", "t_cash_check") == 0;
        missed = [
            e
            for e in _exceptions(app)
            if e["kind"] == "cash_not_counted"
        ];
        assert len(missed) == 1 and missed[0]["expected_cents"] == price , missed;
        assert missed[0]["detail"] and missed[0]["status"] == "open";
        assert missed[0]["label"] == "Cash not counted at the end of a shift";
        status = app.call("agent2", "cash_status", rules);
        behind = [(l["member_id"], l["on_shift"]) for l in status["left_behind"]];
        assert behind == [(gone_id, False)] , behind;
        holder = _counter_order(app, more, "A3");
        sell = {"tenant": "nova", "screening_id": more, "holder": holder, "email": ""};
        assert _code(app.call("agent2", "sell_for_cash", sell)) == "count_left";
        # The next agent counts it on their behalf: theirs, counted by agent2.
        counted = app.call(
            "agent2",
            "count_left_cash",
            {** rules, "member_id": gone_id, "counted_cents": price}
        );
        assert counted["ok"] , counted;
        assert counted["cash_up"]["expected_cents"] == price
            and counted["cash_up"]["counted_by"]
            and counted["cash_up"]["member"] == offered[0]["member"];
        missed = [
            e
            for e in _exceptions(app)
            if e["kind"] == "cash_not_counted"
        ];
        assert missed[0]["status"] == "resolved"
            and "Counted later by" in missed[0]["resolved_note"] , missed;
        assert "cash.counted_for" in _actions(app);
        assert _code(
            app.call(
                "agent2",
                "count_left_cash",
                {** rules, "member_id": gone_id, "counted_cents": 0}
            )
        )
            == "nothing_left";
        assert app.call("agent2", "sell_for_cash", sell)["ok"];
        # Their own cash from an earlier shift: counted before the next cash sale, and
        # counting it doesn't end the new shift.
        assert app.call("agent2", "end_shift", rules)["ok"];
        _new_shift(app, "agent2");
        status = app.call("agent2", "cash_status", rules);
        assert status["uncounted"] and status["count_first"] , status;
        holder = _counter_order(app, more, "A4");
        sell = {"tenant": "nova", "screening_id": more, "holder": holder, "email": ""};
        assert _code(app.call("agent2", "sell_for_cash", sell)) == "count_first";
        theirs = app.call(
            "agent2", "count_cash", {** rules, "counted_cents": 2 * price}
        );
        assert theirs["ok"] and theirs["cash_up"]["difference_cents"] == 0 , theirs;
        assert not app.call("agent2", "cash_status", rules)["count_first"];
        assert app.call("agent2", "sell_for_cash", sell)["ok"];
        assert app.call("agent2", "cash_status", rules)["uncounted"];
        # Counting for someone still signed in ends their shift.
        _new_shift(app, "agent");
        _cash_sale(app, more, "A5");
        assert app.call(
            "agent2",
            "count_left_cash",
            {** rules, "member_id": gone_id, "counted_cents": price}
        )["ok"];
        assert _code(app.call("agent", "count_cash", {** rules, "counted_cents": 0}))
            == "no_shift";
        # A counted-for count can't be corrected by its member.
        assert _code(app.call("agent", "recount_cash", {** rules, "counted_cents": 0}))
            == "too_late";
        # The list says so too.
        ups = app.call("owner", "reconciliation", rules)["cash_ups"];
        assert len(
            [
                u
                for u in ups
                if u["first_counted_cents"] >= 0
            ]
        )
            == 2 , ups;
    } finally {
        os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
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
    (app, nova, screening) = paying_cinema(["agent", "rev", "helper"]);
    try {
        super_admin(app, "boss", "boss@example.com");
        hire(app, "agent", "box_office_agent", nova.venue);
        later = add_screening(app, "owner", nova, "Rafiki", 24 * 50);
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
        # Next month's invoice, disputed and waived: waived, not overdue.
        _cash_sale(app, later, "A4");
        second = app.call(
            "owner", "t_issue_statements", {"at": _second_of(2).isoformat()}
        );
        assert len(second) == 1 , second;
        assert app.call(
            "owner",
            "dispute_invoice",
            {
                "tenant": "nova",
                "number": second[0],
                "text": "That sale was a mistake, refunded."
            }
        )["ok"];
        assert app.call(
            "boss",
            "platform_decide_dispute",
            {"number": second[0], "outcome": "waived", "note": "Waived."}
        )["ok"];
        waived = [
            s
            for s in app.call("owner", "billing", {"tenant": "nova"})["statements"]
            if s["number"] == second[0]
        ][0];
        later_month = waived["month"];
        _platform_member(app, "rev", "reviewer");
        _platform_member(app, "helper", "support");
        for who in ["boss", "rev", "helper"] {
            seen = app.call(who, "platform_takings", {});
            assert seen["ok"] , (who, seen);
            row = [
                m
                for m in seen["months"]
                if m["month"] == later_month
            ][0];
            assert row["waived_cents"] == waived["payable_cents"]
                and row["overdue_cents"] == 0 , row;
            assert row["invoiced_cents"] == waived["payable_cents"];
        }
    } finally {
        app.call("owner", "t_clock_reset");
        os.environ.pop(ADMINS_ENV, None);
        os.environ.pop("AFRICINEMAS_CLOCK_CONTROL", None);
        app.close();
    }
}
