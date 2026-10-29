"""Staff confirm their email before their role's work unlocks (owner, 2026-10-29).

verifying_app (tests/support/verification_setup.jac): Kim owns Kim's Cinema, with a
confirmed email; the usher joined without an email address.
- Sam joins as a box office agent with sam@example.com, not yet confirmed: Sam's
  cinema and overview open (my_access), but the shift doesn't start, so nothing that
  needs one (selling, scanning, managing) does; the refusal names the email.
- Once Sam follows the emailed link, the shift starts.
- Kim (confirmed) and the usher (no email address) start theirs as before.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { browse }
import from tests.support.verification_setup {
    verifying_app,
    close_app,
    sign_up_with_email
}

glob SAM: str = "sam@example.com";

def _confirm(app: Served, label: str, email: str) {
    assert app.call(label, "send_email_check", {"email": email})["ok"];
    app.call("owner", "t_send_email_checks");
    mails = [
        m
        for m in app.call("owner", "tm_outbox")
        if m["to"] == email
    ];
    token = mails[-1]["text"].split("/verify-email#", 1)[1].split()[0];
    assert browse(app, "confirm_email", {"token": token})["ok"];
}

test "a member's work is locked until they confirm their email" {
    app = verifying_app();
    try {
        sign_up_with_email(app, "sam", SAM);
        invited = app.call(
            "kim",
            "invite_staff",
            {"tenant": "kims", "role": "box_office_agent", "venue_id": ""}
        );
        assert invited["ok"] , invited;
        joined = app.call(
            "sam", "accept_invite", {"token": invited["token"], "email": SAM}
        );
        assert joined["ok"] , joined;
        # Their cinema opens, but no shift: so no work.
        assert app.call("sam", "my_access", {"tenant": "kims"})["ok"];
        locked = app.call("sam", "start_shift", {"tenant": "kims"});
        assert not locked["ok"] and locked["error"]["code"] == "confirm_email" , locked;
        assert SAM in locked["error"]["message"];
        assert app.call("sam", "my_access", {"tenant": "kims"})["shift_open"] is False;
        # Confirmed: it unlocks.
        _confirm(app, "sam", SAM);
        assert app.call("sam", "start_shift", {"tenant": "kims"})["ok"];
        assert app.call("sam", "my_access", {"tenant": "kims"})["shift_open"];
        # A confirmed owner, and a member without an email address, as before.
        assert app.call("kim", "start_shift", {"tenant": "kims"})["ok"];
        assert app.call("usher", "start_shift", {"tenant": "kims"})["ok"];
    } finally {
        close_app(app);
    }
}
