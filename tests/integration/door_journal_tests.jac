"""17.2b part 2: the door journal and uploads (docs/specs/offline-scanner.md §9.1, §11).

In-process app (payment_app.jac) with a frozen clock, 30 minutes before a paid showtime
with an usher on shift. Online, a scan with a scan id is answered once: a repeat gets the
first answer, without redeeming again, and the id can't be reused for another ticket.
Offline, a phone uploads what it decided: an admission redeems its ticket (offline, at
the event's time), and a repeat gets the same answer; a refusal and a let-in are
recorded; a ticket another scan redeemed first is a double entry; an admission after the
device was stopped isn't redeemed; a bad entry is rejected, an unknown protocol retried.
"""

import os;
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of }
import from tests.support.payment_setup { paying_cinema, hire, paid }

glob CLOCK: str = "AFRICINEMAS_CLOCK_CONTROL",
     PHONE: str = "phone-0001-main",
     PROTOCOL: str = "door-upload/1";

def _door -> tuple[Served, str, list[dict[str, str]]] {  # jac:ignore[W1037]
    os.environ[CLOCK] = "1";
    (app, nova, screening) = paying_cinema(["usher"]);
    paid(app, screening);
    codes = app.call(
        "owner", "pay_ticket_codes", {"slug": "nova", "screening_id": screening}
    );
    assert len(codes) >= 2 , codes;
    hire(app, "usher", "usher", nova.venue);
    app.call(
        "owner",
        "rd_freeze",
        {"slug": "nova", "screening_id": screening, "minutes": -30}
    );
    return (app, screening, codes);
}

def _close(app: Served) {
    app.call("owner", "rd_unfreeze");
    app.close();
}

def _scan(app: Served, screening: str, code: str, scan_id: str) -> any {  # jac:ignore[W1037]
    return app.call(
        "usher",
        "redeem_ticket",
        {
            "tenant": "nova",
            "screening_id": screening,
            "code": code,
            "scan_id": scan_id,
            "device_id": PHONE
        }
    );
}

def _grant(app: Served) -> dict[str, str] {
    got = app.call("owner", "set_offline_scanning", {"tenant": "nova", "on": True});
    assert got["ok"] , got;
    granted = app.call(
        "usher",
        "door_grant",
        {"tenant": "nova", "device_id": PHONE, "device_name": "Main door"}
    );
    assert granted["ok"] , granted;
    return {
        "grant_id": granted["grant"]["grant_id"],
        "event_at": granted["server_time"]
    };
}

def _upload(app: Served, entries: list[any], protocol: str = PROTOCOL) -> list[any] {  # jac:ignore[W1037]
    got = app.call(
        "usher",
        "upload_door_scans",
        {"tenant": "nova", "device_id": PHONE, "protocol": protocol, "entries": entries}
    );
    assert got["ok"] , got;
    return got["results"];
}

def _entry(
    door: dict[str, str],
    screening: str,
    scan_id: str,
    reference: str,
    decision: str = "admit"
) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "scan_id": scan_id,
        "seq": 1,
        "kind": "scan",
        "decision": decision,
        "code": "" if decision == "admit" else "not_on_list",
        "grant_id": door["grant_id"],
        "screening_id": screening,
        "reference": reference,
        "event_at": door["event_at"],
        "uncertainty_ms": 2000,
        "pack_id": "pack-1",
        "data_age_s": 60
    };
}

test "an online scan with a scan id is answered once, and its id can't be reused" {
    (app, screening, codes) = _door();
    try {
        first = _scan(app, screening, codes[0]["reference"], "scan-0001-aaaa");
        assert first["ok"] , first;
        again = _scan(app, screening, codes[0]["reference"], "scan-0001-aaaa");
        assert again == first , again;
        # Another scan of it is the usual already_redeemed.
        assert code_of(_scan(app, screening, codes[0]["reference"], "scan-0002-aaaa"))
            == "already_redeemed";
        assert code_of(_scan(app, screening, codes[1]["reference"], "scan-0001-aaaa"))
            == "scan_id_conflict";
        # A refusal is answered once too.
        wrong = _scan(app, screening, "not a code", "scan-0003-aaaa");
        assert code_of(wrong) == "invalid_code";
        assert _scan(app, screening, "not a code", "scan-0003-aaaa") == wrong;
        assert code_of(_scan(app, screening, codes[1]["reference"], "x"))
            == "invalid_scan_id";
        # Without a scan id, as before.
        plain = app.call(
            "usher",
            "redeem_ticket",
            {"tenant": "nova", "screening_id": screening, "code": codes[1]["reference"]}
        );
        assert plain["ok"] , plain;
    } finally {
        _close(app);
    }
}

test "an uploaded admission redeems its ticket once; refusals and let-ins are recorded" {
    (app, screening, codes) = _door();
    try {
        door = _grant(app);
        admit = _entry(door, screening, "scan-0101-bbbb", codes[0]["reference"]);
        refuse = _entry(
            door, screening, "scan-0102-bbbb", "7K2M9QXR4HJNP3WD", "refuse"
        );
        let_in = {
            ** _entry(door, screening, "scan-0103-bbbb", "", "let_in"),
            "kind": "let_in",
            "mpesa_code": "sx12ab34cd",
            "people": 2,
            "seats": ["f7", "F8"]
        };
        got = _upload(app, [admit, refuse, let_in]);
        assert got
            == [
                {
                    "scan_id": "scan-0101-bbbb",
                    "answer": "recorded",
                    "outcome": "redeemed"
                },
                {
                    "scan_id": "scan-0102-bbbb",
                    "answer": "recorded",
                    "outcome": "refused"
                },
                {
                    "scan_id": "scan-0103-bbbb",
                    "answer": "recorded",
                    "outcome": "let_in_pending"
                }
            ] , got;
        # Sent again (a lost response): the same answers, nothing redeemed twice.
        assert _upload(app, [admit, refuse, let_in]) == got;
        used = _scan(app, screening, codes[0]["reference"], "scan-0104-bbbb");
        assert code_of(used) == "already_redeemed" , used;
        # Its id reused for another ticket.
        assert _upload(
            app, [_entry(door, screening, "scan-0101-bbbb", codes[1]["reference"])]
        )
            == [
                {
                    "scan_id": "scan-0101-bbbb",
                    "answer": "rejected",
                    "reason": "scan_id_conflict"
                }
            ];
    } finally {
        _close(app);
    }
}

test "a double entry, an admission after revocation, bad entries, an unknown protocol" {
    (app, screening, codes) = _door();
    try {
        door = _grant(app);
        online = _scan(app, screening, codes[0]["reference"], "scan-0201-cccc");
        assert online["ok"] , online;
        twice = _upload(
            app, [_entry(door, screening, "scan-0202-cccc", codes[0]["reference"])]
        );
        assert twice[0]["answer"] == "exception"
            and twice[0]["kind"] == "double_entry" , twice;
        # The online scan that timed out, decided offline under the same id: one
        # redemption.
        same = _upload(
            app, [_entry(door, screening, "scan-0201-cccc", codes[0]["reference"])]
        );
        assert same[0]["answer"] == "recorded"
            and same[0]["outcome"] == "redeemed" , same;
        bad = _upload(
            app,
            [
                "nonsense",
                {** _entry(door, screening, "scan-0203-cccc", "x"), "event_at": "soon"},
                {** _entry(door, screening, "scan-0204-cccc", "x"), "grant_id": "nope"}
            ]
        );
        assert [b.get("reason") for b in bad]
            == ["invalid_entry", "invalid_event_at", "unknown_grant"] , bad;
        later = _upload(
            app,
            [_entry(door, screening, "scan-0205-cccc", codes[1]["reference"])],
            "door-upload/9"
        );
        assert later[0]["answer"] == "retry"
            and later[0]["reason"] == "update_required" , later;
        stopped = app.call(
            "owner", "revoke_door_device", {"tenant": "nova", "device_id": PHONE}
        );
        assert stopped["ok"] , stopped;
        after = _upload(
            app,
            [
                {
                    ** _entry(door, screening, "scan-0206-cccc", codes[1]["reference"]),
                    "event_at": stopped["revoked_at"]
                }
            ]
        );
        assert after[0]["kind"] == "admitted_after_revocation" , after;
        assert _scan(app, screening, codes[1]["reference"], "scan-0207-cccc")["ok"];
    } finally {
        _close(app);
    }
}
