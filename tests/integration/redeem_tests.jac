"""P6.2: redeeming a ticket at the door (architecture §47).

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa and a frozen
clock. Anna has paid for A1 and A2. Staff on shift with tickets.scan at the showtime's
venue redeem by its QR payload or its typed reference: the first scan marks the ticket
used, a second is told it was already redeemed and when. A code this server didn't
sign, an unknown or another cinema's reference, a ticket for another showtime, and a
voided or refunded ticket are refused, and so is a scan outside the door's time window
(from two hours before the start until the showtime ends). Box office agents, and
ushers limited to another venue, may not scan.
"""

import os;
import from tests.support.served { Served }
import from tests.support.storefront_setup { Cinema, add_screening, code_of }
import from tests.support.payment_setup { paying_cinema, paid }

glob CLOCK: str = "AFRICINEMAS_CLOCK_CONTROL";

obj Door {
    # A paid showtime with an usher on shift at its venue, the clock frozen 30 minutes
    # before the start.
    has app: Served,
        nova: Cinema,
        screening: str,
        codes: list[dict[str, str]];
}

def _hire(app: Served, who: str, role: str, venue_id: str) {
    invited = app.call(
        "owner", "invite_staff", {"tenant": "nova", "role": role, "venue_id": venue_id}
    );
    assert invited["ok"] , invited;
    joined = app.call(who, "accept_invite", {"token": invited["token"]});
    assert joined["ok"] , joined;
    assert app.call(who, "start_shift", {"tenant": "nova"})["ok"];
}

def _door(staff: list[str]) -> Door {
    os.environ[CLOCK] = "1";
    (app, nova, screening) = paying_cinema(["usher"] + staff);
    paid(app, screening);
    codes = app.call(
        "owner", "pay_ticket_codes", {"slug": "nova", "screening_id": screening}
    );
    _hire(app, "usher", "usher", nova.venue);
    _at(app, screening, -30);
    return Door(app=app, nova=nova, screening=screening, codes=codes);
}

def _at(app: Served, screening: str, minutes: int) {
    app.call(
        "owner",
        "rd_freeze",
        {"slug": "nova", "screening_id": screening, "minutes": minutes}
    );
}

def _close(door: Door) {
    door.app.call("owner", "rd_unfreeze");
    door.app.close();
}

def _redeem(door: Door, code: str, who: str = "usher", screening: str = "") -> any {  # jac:ignore[W1037]
    return door.app.call(
        who,
        "redeem_ticket",
        {"tenant": "nova", "screening_id": screening or door.screening, "code": code}
    );
}

def _stored(door: Door, reference: str) -> dict[str, str] {
    return door.app.call("owner", "rd_ticket", {"reference": reference});
}

test "a valid ticket is redeemed once; a second scan says it was already used, and when" {
    door = _door([]);
    try {
        (a1, a2) = (door.codes[0], door.codes[1]);
        first = _redeem(door, a1["qr"]);
        assert first["ok"] , first;
        assert first["ticket"]["seat_label"] == "A1";
        assert first["ticket"]["reference"] == a1["reference"];
        stored = _stored(door, a1["reference"]);
        assert stored["status"] == "used" and stored["used_at"] and stored["used_by"];
        again = _redeem(door, a1["qr"]);
        assert code_of(again) == "already_redeemed" , again;
        assert again["error"]["used_at"] == stored["used_at"];
        # The same ticket typed in is the same ticket.
        assert code_of(_redeem(door, a1["reference"])) == "already_redeemed";
        typed = _redeem(door, a2["reference"].lower().replace("-", " "));
        assert typed["ok"] and typed["ticket"]["seat_label"] == "A2" , typed;
    } finally {
        _close(door);
    }
}

test "codes that aren't one of this cinema's tickets are refused" {
    door = _door([]);
    try {
        qr = door.codes[0]["qr"];
        (version, compact, sig) = qr.split(".");
        forged = f"{version}.{compact}.{'A' if sig[0] != 'A' else 'B'}{sig[1:]}";
        assert code_of(_redeem(door, forged)) == "invalid_code";
        assert code_of(_redeem(door, "hello")) == "invalid_code";
        assert code_of(_redeem(door, "2222-3333-4444-5555")) == "unknown_ticket";
        door.app.call(
            "owner", "rd_foreign_reference", {"reference": "6666-7777-8888-9999"}
        );
        assert code_of(_redeem(door, "6666-7777-8888-9999")) == "unknown_ticket";
        assert _stored(door, door.codes[0]["reference"])["status"] == "issued";
    } finally {
        _close(door);
    }
}

test "a ticket for another showtime is refused, naming that showtime" {
    door = _door([]);
    try {
        later = add_screening(door.app, "owner", door.nova, "Rafiki", 4);
        wrong = _redeem(door, door.codes[0]["qr"], screening=later);
        assert code_of(wrong) == "wrong_showtime" , wrong;
        assert wrong["error"]["movie_title"] == "Rafiki";
        assert wrong["error"]["starts_at"];
        assert _stored(door, door.codes[0]["reference"])["status"] == "issued";
    } finally {
        _close(door);
    }
}

test "voided and refunded tickets are refused" {
    door = _door([]);
    try {
        (a1, a2) = (door.codes[0]["reference"], door.codes[1]["reference"]);
        door.app.call("owner", "rd_set_status", {"reference": a1, "status": "voided"});
        door.app.call(
            "owner", "rd_set_status", {"reference": a2, "status": "refunded"}
        );
        assert code_of(_redeem(door, a1)) == "ticket_voided";
        assert code_of(_redeem(door, a2)) == "ticket_refunded";
        assert _stored(door, a1)["status"] == "voided";
    } finally {
        _close(door);
    }
}

test "only staff who may scan can redeem, and only at their venues" {
    door = _door(["agent", "elsewhere"]);
    try {
        _hire(door.app, "agent", "box_office_agent", door.nova.venue);
        mall = door.app.call(
            "owner",
            "create_venue",
            {"tenant": "nova", "name": "Mall", "city": "", "address": ""}
        )["venue"]["venue_id"];
        _hire(door.app, "elsewhere", "usher", mall);
        qr = door.codes[0]["qr"];
        assert code_of(_redeem(door, qr, who="agent")) == "forbidden";
        assert code_of(_redeem(door, qr, who="elsewhere")) == "forbidden";
        assert _stored(door, door.codes[0]["reference"])["status"] == "issued";
        # The owner may scan anywhere.
        assert _redeem(door, qr, who="owner")["ok"];
    } finally {
        _close(door);
    }
}

test "the door opens two hours before the start and closes when the showtime ends" {
    door = _door([]);
    try {
        (a1, a2) = (door.codes[0]["qr"], door.codes[1]["qr"]);
        _at(door.app, door.screening, -121);
        early = _redeem(door, a1);
        assert code_of(early) == "too_early" , early;
        assert early["error"]["opens_at"];
        _at(door.app, door.screening, -120);
        assert _redeem(door, a1)["ok"];
        _at(door.app, door.screening, 24 * 60);
        assert code_of(_redeem(door, a2)) == "showtime_over";
        assert _stored(door, door.codes[1]["reference"])["status"] == "issued";
    } finally {
        _close(door);
    }
}
