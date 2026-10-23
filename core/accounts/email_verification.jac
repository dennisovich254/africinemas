"""Confirming a staff account's email (P14.2, ADR-0065).

A one-time link proves the account holder reads the email they signed up with:
- **send_email_check(email)** (the caller's own sign-in email, checked by
  verified_sign_in) queues an email with a link to `/verify-email#<token>` on the main
  site. The token is made when the email is sent, single use, valid LINK_TTL_S, and
  kept only as a hash (the app's token store). A new link replaces the last. At most SENDS_PER_HOUR an hour per
  account.
- **confirm_email(token)** (public: the link may be opened signed out, on another
  device) spends the token and records the email as confirmed for that account
  (VERIFIED: its root -> the email). A reused, expired or altered token is refused.
- **email_status(email)**: whether the caller's email is confirmed, for the back
  office's banner.

What it unlocks: creating a cinema needs the owner's email confirmed
(core/tenancy/signup.jac), and submitting a cinema for review will (14.4). Customer
and platform accounts sign in with usernames and never need this. The email is queued
(VERIFY_MAIL) and sent by this module's job, never inside a request, as ticket emails
are.
"""

import os;
import html;
import math;
import from email.utils { formataddr }
import from jaclang.server.identity.app_tokens {
    token_create,
    token_peek,
    token_consume,
    token_revoke
}
import from core.claims { claim, holder, release, claims_in, take_claim }
import from core.catalog.answers { Refused, answer }
import from core.tenancy.identity { verified_sign_in }
import from core.tenancy.principal { node_id, same_id, fresh_node_id }
import from core.notify.mailer { OutgoingMail, send, from_address }
import from core.site { main_address }

glob PURPOSE: str = "email-check",
     VERIFIED: str = "email-verified",
     VERIFY_MAIL: str = "email-check-mail",
     SENDING: str = "email-check-sending",
     SENDS: str = "email-check-sends",
     LINK_TTL_S: int = 24 * 3600,
     SENDS_PER_HOUR: int = 5,
     HOUR_S: int = 3600,
     SENDING_S: int = 120,
     MAIL_SECONDS: int = int(os.environ.get("AFRICINEMAS_MAIL_SECONDS", "5")),
     INVALID: str = "This link has expired or was already used. Sign in and send a new one.";

def is_confirmed(root_id: str, email: str) -> bool {
    # Whether `email` is the confirmed email of the account with this root.
    if not root_id or not email {
        return False;
    }
    return holder(VERIFIED, same_id(root_id)) == email.strip().lower();
}

def _send_slot(root_id: str) -> int {
    # Takes one of the account's sends this hour: 0 if one was free, else the seconds
    # until the oldest frees up (as resending tickets does).
    space = f"{SENDS}:{same_id(root_id)}";
    mine = fresh_node_id();
    for slot in range(SENDS_PER_HOUR) {
        if claim(space, str(slot), mine, HOUR_S) == mine {
            return 0;
        }
    }
    ages = [
        age
        for (_, _, age) in claims_in(space)
        if age < HOUR_S
    ];
    return max(1, math.ceil(HOUR_S - max(ages))) if ages else 1;
}

def _mine(email: str) -> str {
    # The caller's own sign-in email, or refused.
    mine = verified_sign_in(email);
    if not mine or "@" not in mine {
        raise Refused("not_your_email", "Sign in again, then try once more.");
    }
    return mine;
}

def _send(email: str) -> dict[str, any] {  # jac:ignore[W1037]
    mine = _mine(email);
    me = node_id(root);
    if is_confirmed(me, mine) {
        return {"ok": True, "confirmed": True, "sent": False};
    }
    later = _send_slot(me);
    if later {
        raise Refused(
            "too_many",
            f"We've sent several links already. Try again in {math.ceil(
                later / 60
            )} minutes."
        );
    }
    # Queued with the account and address only: the job makes the link as it sends,
    # so the token itself is never stored, only its hash (the token store).
    claim(VERIFY_MAIL, fresh_node_id(), f"{same_id(me)}|{mine}");
    return {"ok": True, "confirmed": False, "sent": True};
}

def _confirm(token: str) -> dict[str, any] {  # jac:ignore[W1037]
    found = token_peek(PURPOSE, token) if isinstance(token, str) and token else None;
    if found is None {
        raise Refused("invalid_link", INVALID);
    }
    owner = str(found["payload"].get("root_id", ""));
    email = str(found["payload"].get("email", ""));
    if not owner or not email or token_consume(PURPOSE, token) is None {
        raise Refused("invalid_link", INVALID);
    }
    take_claim(VERIFIED, owner);
    claim(VERIFIED, owner, email);
    return {"ok": True, "email": email};
}

def _status(email: str) -> dict[str, any] {  # jac:ignore[W1037]
    mine = verified_sign_in(email);
    if not mine or "@" not in mine {
        # An account without an email (a username) has nothing to confirm here.
        return {"ok": True, "email": "", "confirmed": False};
    }
    return {"ok": True, "email": mine, "confirmed": is_confirmed(node_id(root), mine)};
}

def:protect send_email_check(email: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _send(email); });  # jac:ignore[W1037]
}

def:pub confirm_email(token: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _confirm(token); });  # jac:ignore[W1037]
}

def:protect email_status(email: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _status(email); });  # jac:ignore[W1037]
}

def _fresh_link(root_id: str, email: str) -> str {
    # A new link's token for the account; any earlier one stops working.
    token_revoke(PURPOSE, root_id);
    return token_create(
        PURPOSE,
        subject=root_id,
        ttl_seconds=LINK_TTL_S,
        payload={"root_id": root_id, "email": email}
    );
}

def check_mail(to: str, token: str) -> OutgoingMail {
    # The email with the link; it holds no other detail of the account.
    link = f"{main_address()}/verify-email#{token}";
    hours = LINK_TTL_S // 3600;
    text = (
        "Confirm your email for AfriCinemas by opening this link:\n\n"
        + f"{link}\n\n"
        + f"It works once, for {hours} hours. If you didn't sign up, ignore this email.\n"
    );
    link_html = html.escape(link);
    body = (
        "<p>Confirm your email for AfriCinemas:</p>"
        + f'<p><a href="{link_html}">Confirm my email</a></p>'
        + f"<p>It works once, for {hours} hours. If you didn't sign up, ignore this email.</p>"
    );
    return OutgoingMail(
        to=to,
        sender=formataddr(("AfriCinemas", from_address())),
        subject="Confirm your email for AfriCinemas",
        text=text,
        html=body
    );
}

def send_checks_due -> int {
    # Sends every queued link email; returns how many went.
    sent = 0;
    for (key, queued, _) in claims_in(VERIFY_MAIL) {
        mine = fresh_node_id();
        if claim(SENDING, key, mine, SENDING_S) != mine {
            continue;
        }
        try {
            (owner, address) = queued.split("|", 1);
            if send(check_mail(address, _fresh_link(owner, address))) {
                release(VERIFY_MAIL, key, queued);
                sent += 1;
            }
        } finally {
            release(SENDING, key, mine);
        }
    }
    return sent;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=MAIL_SECONDS)
def send_email_checks {
    # Runs as Jac's system identity on every server copy; SENDING keeps one per email.
    send_checks_due();
}
