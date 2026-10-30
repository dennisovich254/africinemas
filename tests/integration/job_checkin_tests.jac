"""P16.2: background jobs check in; a silent one shows on the overview and alerts.

In-process app (payment_app.jac), the clock frozen and moved (AFRICINEMAS_CLOCK_CONTROL),
with the development outbox. Jobs don't run here by themselves: t_job_ran checks one in.
- A job that hasn't checked in is "waiting", and raises no alert.
- Checked in, it's "running"; silent for more than three of its intervals, it's
  "silent" on the overview (and at least five minutes, so a short lag isn't), and the team is emailed once ("… has stopped").
- When it checks in again it's "running", and the team hears once that it is.
- The team: AFRICINEMAS_ALERT_EMAILS, or the super admins when unset. No customer's
  details in an alert.
"""

import os;
import tempfile;
import from datetime { datetime, timedelta }
import from tests.support.served { Served }
import from tests.support.payment_setup { paying_cinema }
import from tests.support.platform_setup { ADMINS_ENV, super_admin }

glob BOSS: str = "boss@example.com",
     START: datetime = datetime.fromisoformat("2026-11-02T09:00:00+03:00");

def _at(app: Served, seconds: int) {
    assert app.call(
        "owner", "t_clock_at", {"at": (START + timedelta(seconds=seconds)).isoformat()}
    );
}

def _jobs(app: Served) -> dict[str, str] {
    got = app.call("boss", "platform_overview", {});
    assert got["ok"] , got;
    return {j["name"]: j["state"] for j in got["jobs"]};
}

def _alerts(app: Served, to: str) -> list[str] {
    return [
        m["subject"]
        for m in app.call("owner", "tm_outbox")
        if m["to"] == to and m["subject"].startswith("AfriCinemas: ")
    ];
}

test "a silent job shows on the overview and alerts the team, once each way" {
    os.environ["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    os.environ["AFRICINEMAS_OUTBOX_DIR"] = tempfile.mkdtemp(
        prefix="africinemas-outbox-"
    );
    (app, _, _) = paying_cinema([]);
    try {
        super_admin(app, "boss", BOSS);
        app.call("owner", "tm_clear_outbox");
        _at(app, 0);
        # Not checked in yet: waiting, and nothing to say.
        assert _jobs(app)["send_ticket_mail"] == "waiting";
        assert app.call("owner", "t_check_jobs") == 0;
        # Checked in (every 5 seconds): running.
        assert app.call("owner", "t_job_ran", {"name": "send_ticket_mail", "every": 5});
        assert _jobs(app)["send_ticket_mail"] == "running";
        _at(app, 299);
        assert _jobs(app)["send_ticket_mail"] == "running";
        assert app.call("owner", "t_check_jobs") == 0;
        # More than three intervals, and five minutes: silent, and the team (the super
        # admins) hears once.
        _at(app, 301);
        assert _jobs(app)["send_ticket_mail"] == "silent";
        assert app.call("owner", "t_check_jobs") == 1;
        assert app.call("owner", "t_check_jobs") == 0;
        assert _alerts(app, BOSS) == ["AfriCinemas: Ticket emails has stopped"];
        # Running again: back to running, and the team hears that once.
        assert app.call("owner", "t_job_ran", {"name": "send_ticket_mail", "every": 5});
        assert _jobs(app)["send_ticket_mail"] == "running";
        assert app.call("owner", "t_check_jobs") == 1;
        assert app.call("owner", "t_check_jobs") == 0;
        assert _alerts(app, BOSS)[-1] == "AfriCinemas: Ticket emails is running again";
        # AFRICINEMAS_ALERT_EMAILS, when set, is the team instead.
        os.environ["AFRICINEMAS_ALERT_EMAILS"] = "oncall@example.com, Second@Example.com";
        _at(app, 700);
        assert app.call("owner", "t_check_jobs") == 2;
        assert _alerts(app, "oncall@example.com")
            == ["AfriCinemas: Ticket emails has stopped"];
        assert _alerts(app, "second@example.com")
            == ["AfriCinemas: Ticket emails has stopped"];
        # Only platform staff see the jobs.
        assert not app.call("owner", "platform_overview", {})["ok"];
    } finally {
        app.call("owner", "t_clock_reset");
        for name in [
            "AFRICINEMAS_CLOCK_CONTROL",
            "AFRICINEMAS_OUTBOX_DIR",
            "AFRICINEMAS_ALERT_EMAILS",
            ADMINS_ENV
        ] {
            os.environ.pop(name, None);
        }
        app.close();
    }
}
