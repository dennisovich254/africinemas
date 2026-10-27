"""P15.1: the fee rule and accepting the cinema agreement.

In-process app (payment_app.jac).
- The fee rule starts at model C (online 7% tickets, 20% snacks; box office 3%).
  Platform staff read it; only the settings' super admin (boss) adds a version, from
  today or later, never twice for one day, with rates between 0% and 50%; every change
  is in the platform log.
- Nova's owner accepts the current agreement (any member sees the status; only the
  owner accepts, and only the version they were shown). When a new version is
  published, Nova can't take orders until the owner accepts it.
"""

import os;
import uuid;
import from datetime { date, timedelta }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse, code_of }
import from tests.support.payment_setup { paying_cinema, hire, ANNA }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

glob BOSS: str = "boss@example.com",
     REV: str = "rev@example.com";

def _order(app: Served, screening: str, seat: str) -> any {  # jac:ignore[W1037]
    held = browse(
        app,
        "hold_seats",
        {"slug": "nova", "screening_id": screening, "holder": ANNA, "labels": [seat]}
    );
    assert held["ok"] , held;
    return browse(
        app,
        "place_order",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": seat, "ticket_type": "ADULT"}]
        }
    );
}

test "the fee rule starts at model C and only super admins add versions" {
    (app, _, _) = paying_cinema([]);
    try {
        super_admin(app, "boss", BOSS);
        rules = app.call("boss", "fee_rules", {});
        assert rules["ok"] , rules;
        first = rules["current"];
        assert (
            first["online_ticket_bp"],
            first["online_snack_bp"],
            first["counter_bp"]
        )
            == (700, 2000, 300);
        tomorrow = (date.fromisoformat(rules["today"]) + timedelta(days=1)).isoformat();
        yesterday = (
            date.fromisoformat(rules["today"]) - timedelta(days=1)
        ).isoformat();
        body = {
            "online_ticket_percent": 6.5,
            "online_snack_percent": 18,
            "counter_percent": 2.5,
            "applies_from": tomorrow
        };
        made = app.call("boss", "set_fee_rule", body);
        assert made["ok"] and made["rule"]["version"] == 2 , made;
        assert made["rule"]["online_ticket_bp"] == 650
            and made["rule"]["counter_bp"] == 250;
        after = app.call("boss", "fee_rules", {});
        # Tomorrow's version isn't in force yet.
        assert after["current"]["version"] == 1 and len(after["versions"]) == 2;
        assert code_of(app.call("boss", "set_fee_rule", body)) == "date_taken";
        assert code_of(
            app.call("boss", "set_fee_rule", {** body, "applies_from": yesterday})
        )
            == "date_in_past";
        assert code_of(
            app.call(
                "boss",
                "set_fee_rule",
                {** body, "applies_from": "2099-01-01", "online_snack_percent": 51}
            )
        )
            == "invalid_rate";
        # A reviewer reads the rule but can't change it; a cinema owner can do neither.
        invited = app.call(
            "boss", "invite_platform_member", {"email": REV, "role": "reviewer"}
        );
        join_platform(app, "rev", invited["token"]);
        assert app.call("rev", "fee_rules", {})["ok"];
        assert not app.call(
            "rev", "set_fee_rule", {** body, "applies_from": "2099-01-02"}
        )["ok"];
        assert not app.call("owner", "fee_rules", {})["ok"];
        logged = app.call(
            "boss",
            "platform_audit_log",
            {"limit": 50, "action": "platform.fee_rule_set"}
        );
        assert [
            e
            for e in logged["events"]
            if e["resource_id"] == tomorrow
        ] , logged;
    } finally {
        os.environ.pop(ADMINS_ENV, None);
        app.close();
    }
}

test "the owner accepts the agreement, and a new version stops sales until accepted" {
    (app, cinema, screening) = paying_cinema(["clara"]);
    try {
        hire(app, "clara", "box_office_agent", cinema.venue);
        status = app.call("owner", "cinema_agreement_status", {"tenant": "nova"});
        assert status["ok"]
            and status["needs_acceptance"]
            and status["may_sell"] , status;
        assert status["accepted"] is None and status["may_accept"];
        current = status["current"];
        # Staff see the status but can't accept; nobody accepts a version they didn't see.
        assert not app.call("clara", "cinema_agreement_status", {"tenant": "nova"})[
            "may_accept"
        ];
        assert not app.call(
            "clara", "accept_cinema_agreement", {"tenant": "nova", "version": current}
        )["ok"];
        assert code_of(
            app.call(
                "owner", "accept_cinema_agreement", {"tenant": "nova", "version": "9.9"}
            )
        )
            == "agreement_changed";
        assert app.call(
            "owner", "accept_cinema_agreement", {"tenant": "nova", "version": current}
        )["ok"];
        status = app.call("owner", "cinema_agreement_status", {"tenant": "nova"});
        assert not status["needs_acceptance"]
            and status["accepted"]["version"] == current;
        assert _order(app, screening, "A3")["ok"];
        # A new version is published: no new orders until the owner accepts it.
        browse(app, "t_agreement_version", {"version": "0.2"});
        status = app.call("owner", "cinema_agreement_status", {"tenant": "nova"});
        assert status["needs_acceptance"] and not status["may_sell"] , status;
        assert code_of(_order(app, screening, "A4")) == "agreement_needed";
        assert app.call(
            "owner", "accept_cinema_agreement", {"tenant": "nova", "version": "0.2"}
        )["ok"];
        assert _order(app, screening, "A5")["ok"];
        logged = app.call("owner", "audit_log", {"tenant": "nova", "limit": 50});
        accepted = [
            e["resource_id"]
            for e in logged["events"]
            if e["action"] == "cinema.agreement_accepted" and e["result"] == "ok"
        ];
        assert sorted(accepted) == sorted([current, "0.2"]) , logged["events"];
    } finally {
        browse(app, "t_agreement_version", {"version": ""});
        app.close();
    }
}
