"""Spike S6 fallback (plan P1.4): server-side staff sessions are short and revocable.

Jac's own tokens last at least a day and can't be revoked (s3_s6_real_server_tests),
so staff actions also require a live shift session kept on the server (s6_app.jac).
The clock is controlled through core.clock (the in-process app shares this process).
"""

import os;
import from datetime { datetime, timezone }
import from os { path }
import core.clock as clock;
import from tests.support.served { served }

glob S6_ENTRY: str = path.join(path.dirname(path.abspath(__file__)), "s6_app.jac");

def _with_clock {
    os.environ[clock.CONTROL_ENV] = "1";
    clock.freeze(datetime(2026, 10, 3, 8, 0, tzinfo=timezone.utc));
}

test "a shift session allows staff actions until it expires after 8 hours" {
    _with_clock();
    app = served(S6_ENTRY, ["staff_a"]);
    try {
        assert not app.call("staff_a", "s6_staff_action")["allowed"] , "no session yet";
        app.call("staff_a", "s6_start_shift");
        assert app.call("staff_a", "s6_staff_action")["allowed"];
        clock.advance(7.5 * 3600);
        assert app.call("staff_a", "s6_staff_action")["allowed"] , "still inside the shift";
        clock.advance(1 * 3600);
        assert not app.call("staff_a", "s6_staff_action")["allowed"] , "expired after 8 h, token or not";
    } finally {
        app.close();
        clock.reset();
    }
}

test "ending the shift revokes access immediately, though the token is still valid" {
    _with_clock();
    app = served(S6_ENTRY, ["staff_a"]);
    try {
        app.call("staff_a", "s6_start_shift");
        assert app.call("staff_a", "s6_end_shift") == {"ended": 1};
        assert not app.call("staff_a", "s6_staff_action")["allowed"];
    } finally {
        app.close();
        clock.reset();
    }
}
