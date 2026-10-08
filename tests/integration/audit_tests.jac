"""P7.2: the audit log records who did what, and nobody can rewrite it.

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa. Real actions at
Nova: creating the cinema, staff joining, a role change, a cash sale and a door scan,
each an event with its actor, resource and result; a refused attempt records its code.
Owners and auditors read the log, newest first, a page at a time; a box office agent
can't, and someone outside the cinema finds no cinema. Events hold no secrets (no invite
token, ticket code or customer email), and a finished event never changes. Events live
in Jac's shared store, outside the graph, where no staff request reaches them.
"""

import json;
import uuid;
import from uuid { UUID }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { paying_cinema, hire }

def _log(
    app: Served, who: str, action: str = "", before: str = "", limit: int = 50
) -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "audit_log",
        {"tenant": "nova", "before": before, "limit": limit, "action": action}
    );
}

def _events(app: Served, action: str = "") -> list[dict[str, any]] {  # jac:ignore[W1037]
    got = _log(app, "owner", action);
    assert got["ok"] , got;
    return got["events"];
}

def _same(a: str, b: str) -> bool {
    return UUID(a) == UUID(b);
}

def _cash_sale(app: Served, screening: str) -> str {
    # The agent sells A3 for cash; returns the counter holder id.
    holder = f"counter-{uuid.uuid4().hex}";
    where = {"slug": "nova", "screening_id": screening, "holder": holder};
    assert browse(app, "hold_seats", {** where, "labels": ["A3"]})["ok"];
    assert browse(
        app,
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": "A3", "ticket_type": "ADULT"}]
        }
    )["ok"];
    sold = app.call(
        "agent",
        "sell_for_cash",
        {
            "tenant": "nova",
            "screening_id": screening,
            "holder": holder,
            "email": "walkin@example.com"
        }
    );
    assert sold["ok"] , sold;
    return sold["payment"]["tickets"][0]["qr"];
}

test "creating the cinema and staff joining are recorded" {
    (app, nova, _) = paying_cinema(["agent"]);
    try {
        agent = hire(app, "agent", "box_office_agent", nova.venue);
        events = _events(app)[::-1];
        assert events[0]["action"] == "cinema.created" , events[0];
        assert events[0]["result"] == "ok";
        joined = [
            e
            for e in events
            if e["action"] == "staff.joined"
        ];
        assert len(joined) == 1 , joined;
        assert _same(joined[0]["actor_id"], agent);
        assert _same(joined[0]["resource_id"], agent);
        invited = [
            e
            for e in events
            if e["action"] == "staff.invited"
        ];
        assert len(invited) == 1 and invited[0]["result"] == "ok";
        assert "box_office_agent" in invited[0]["detail"];
    } finally {
        app.close();
    }
}

test "a role change, a cash sale and a door scan: actor, resource and result" {
    (app, nova, screening) = paying_cinema(["agent", "usher"]);
    try {
        agent = hire(app, "agent", "box_office_agent", nova.venue);
        usher = hire(app, "usher", "usher", nova.venue);
        changed = app.call(
            "owner",
            "change_staff_roles",
            {
                "tenant": "nova",
                "member_id": agent,
                "roles": ["box_office_agent", "usher"]
            }
        );
        assert changed["ok"] , changed;
        role = _events(app, "staff.roles_changed");
        assert len(role) == 1 , role;
        assert role[0]["resource_type"] == "member"
            and _same(role[0]["resource_id"], agent);
        assert role[0]["result"] == "ok" and "usher" in role[0]["detail"];
        assert role[0]["actor"] , "the owner is named";
        code = _cash_sale(app, screening);
        sale = _events(app, "sale.cash");
        assert len(sale) == 1 , sale;
        assert _same(sale[0]["actor_id"], agent);
        assert sale[0]["resource_type"] == "showtime"
            and sale[0]["resource_id"] == screening;
        assert sale[0]["result"] == "ok";
        # Two days before the showtime the door isn't open: the scan is refused, and
        # the refusal is recorded.
        scanned = app.call(
            "usher",
            "redeem_ticket",
            {"tenant": "nova", "screening_id": screening, "code": code}
        );
        assert not scanned["ok"];
        scan = _events(app, "ticket.scanned");
        assert len(scan) == 1 , scan;
        assert _same(scan[0]["actor_id"], usher);
        assert scan[0]["result"] == scanned["error"]["code"];
        # No secrets: not the ticket code, the customer's email or an invite token.
        everything = json.dumps(_events(app));
        assert code not in everything and code.split(".")[1] not in everything;
        assert "walkin@example.com" not in everything;
        invited = app.call(
            "owner", "invite_staff", {"tenant": "nova", "role": "usher", "venue_id": ""}
        );
        assert invited["token"] not in json.dumps(_events(app));
    } finally {
        app.close();
    }
}

test "a refused attempt is recorded with its code" {
    (app, nova, _) = paying_cinema(["agent"]);
    try {
        agent = hire(app, "agent", "box_office_agent", nova.venue);
        tried = app.call(
            "agent",
            "change_staff_roles",
            {"tenant": "nova", "member_id": agent, "roles": ["owner"]}
        );
        assert code_of(tried) == "forbidden";
        role = _events(app, "staff.roles_changed");
        assert len(role) == 1 , role;
        assert _same(role[0]["actor_id"], agent) and role[0]["result"] == "forbidden";
    } finally {
        app.close();
    }
}

test "owners and auditors read the log a page at a time; agents and outsiders can't" {
    (app, nova, _) = paying_cinema(["agent", "auditor", "outsider"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        hire(app, "auditor", "auditor", "");
        all_events = _events(app);
        assert len(all_events) >= 5;
        stamps = [e["at"] for e in all_events];
        assert stamps == sorted(stamps, reverse=True) , "newest first";
        read = _log(app, "auditor");
        assert read["ok"] and read["events"] == all_events , read;
        assert code_of(_log(app, "agent")) == "forbidden";
        assert code_of(_log(app, "outsider")) == "not_found";
        # Pages: two at a time, each picking up after the last, ending with no next.
        pages: list[dict[str, any]] = [];  # jac:ignore[W1037]
        before = "";
        for _ in range(20) {
            page = _log(app, "owner", "", before, 2);
            assert page["ok"] and len(page["events"]) <= 2 , page;
            pages.extend(page["events"]);
            before = page["next"];
            if not before {
                break;
            }
        }
        assert pages == all_events;
        # One action only.
        shifts = _events(app, "shift.started");
        assert shifts and all([e["action"] == "shift.started" for e in shifts]);
        assert code_of(_log(app, "owner", "", "", 0)) == "bad_limit";
        assert code_of(_log(app, "owner", "", "not-an-event")) == "not_found";
    } finally {
        app.close();
    }
}

test "a finished event never changes: it is finished once" {
    (app, nova, _) = paying_cinema(["agent"]);
    try {
        hire(app, "agent", "box_office_agent", nova.venue);
        tried = app.call(
            "agent",
            "change_staff_roles",
            {"tenant": "nova", "member_id": "x", "roles": ["owner"]}
        );
        assert code_of(tried) == "forbidden";
        refused = _events(app, "staff.roles_changed")[0];
        assert refused["result"] == "forbidden";
        assert app.call(
            "owner", "audit_refinish", {"slug": "nova", "event_id": refused["event_id"]}
        );
        assert _events(app, "staff.roles_changed")[0] == refused;
    } finally {
        app.close();
    }
}
