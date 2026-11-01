"""Notices in the back office (owner, 2026-11-01; core/notify/notices.jac).

In-process app (payment_app.jac). Nova sells a ticket; the next month's billing job
issues its statement, which posts a notice for who reads the reports: the owner and the
finance manager see it unread, with Billing's count; an usher doesn't see it at all.
Issuing again posts nothing more. Reading Billing's notices clears the count; Mark all as
read clears the rest.
"""

import from datetime { datetime }
import from zoneinfo { ZoneInfo }
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse }
import from tests.support.payment_setup { paying_cinema, hire, paid }

glob NAIROBI: ZoneInfo = ZoneInfo("Africa/Nairobi");

def _second_of_next_month -> datetime {
    today = datetime.now(NAIROBI);
    first = today.replace(day=1, hour=9, minute=0, second=0, microsecond=0);
    month = first.month % 12 + 1;
    year = first.year + (1 if first.month == 12 else 0);
    return first.replace(year=year, month=month, day=2);
}

def _notices(app: Served, who: str) -> any {  # jac:ignore[W1037]
    got = app.call(who, "my_notices", {"tenant": "nova"});
    assert got["ok"] , got;
    return got;
}

def _read(
    app: Served, who: str, ids: list[str], section: str, everything: bool
) -> any {  # jac:ignore[W1037]
    got = app.call(
        who,
        "read_notices",
        {"tenant": "nova", "ids": ids, "section": section, "everything": everything}
    );
    assert got["ok"] , got;
    return got;
}

test "a new statement is a notice for who reads the reports, read per section or all" {
    (app, nova, screening) = paying_cinema(["finance", "usher"]);
    try {
        hire(app, "finance", "finance_manager", "");
        hire(app, "usher", "usher", nova.venue);
        paid(app, screening);
        before = _notices(app, "owner");
        assert before["unread"] == 0 and before["notices"] == [] , before;
        made = browse(
            app, "t_issue_statements", {"at": _second_of_next_month().isoformat()}
        );
        assert len(made) == 1 , made;
        for who in ["owner", "finance"] {
            got = _notices(app, who);
            assert got["unread"] == 1 and got["sections"] == {"billing": 1} , (
                who,
                got
            );
            n = got["notices"][0];
            assert n["kind"] == "statement" and n["section"] == "billing";
            assert made[0] in n["title"] and "due by" in n["body"] and not n["read"];
        }
        assert _notices(app, "usher")["notices"] == [];
        # Issued again by another server copy: no second notice.
        assert browse(
            app, "t_issue_statements", {"at": _second_of_next_month().isoformat()}
        )
            == [];
        assert len(_notices(app, "owner")["notices"]) == 1;
        # The owner opens Billing: its notices are read, for the owner only.
        read = _read(app, "owner", [], "billing", False);
        assert read["unread"] == 0
            and read["sections"] == {}
            and read["notices"][0]["read"];
        assert _notices(app, "finance")["unread"] == 1;
        # The finance manager reads it from the bell, then all.
        one = _notices(app, "finance")["notices"][0]["id"];
        assert _read(app, "finance", [one], "", False)["unread"] == 0;
        assert _read(app, "finance", [], "", True)["unread"] == 0;
    } finally {
        app.close();
    }
}
