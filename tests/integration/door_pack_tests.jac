"""17.2b part 1: offline grants and the door copy (docs/specs/offline-scanner.md §6, §7).

In-process app (payment_app.jac) with a frozen clock, 30 minutes before a paid
showtime with an usher on shift. Until the cinema turns offline scanning on, no grant.
Then the usher's phone gets one for the venue, renewed while it's theirs, and the door
copy: the showtime, and its tickets by hash, never by reference. A scan shows up in the
changes; a cursor that isn't the server's is refused; an old one asks for a resync. A
revoked device stops; someone who can't scan, or another cinema's staff, get nothing.
"""

import os;
import from datetime { datetime, timedelta }
import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, open_cinema_for }
import from tests.support.payment_setup { paying_cinema, hire, paid }
import from core.door.pack { door_hash }

glob CLOCK: str = "AFRICINEMAS_CLOCK_CONTROL",
     PHONE: str = "phone-0001-main";

def _at(app: Served, screening: str, minutes: int) {
    app.call(
        "owner",
        "rd_freeze",
        {"slug": "nova", "screening_id": screening, "minutes": minutes}
    );
}

def _door(staff: list[str]) -> tuple[Served, any, str, list[dict[str, str]]] {  # jac:ignore[W1037]
    os.environ[CLOCK] = "1";
    (app, nova, screening) = paying_cinema(["usher"] + staff);
    paid(app, screening);
    codes = app.call(
        "owner", "pay_ticket_codes", {"slug": "nova", "screening_id": screening}
    );
    hire(app, "usher", "usher", nova.venue);
    _at(app, screening, -30);
    return (app, nova, screening, codes);
}

def _close(app: Served) {
    app.call("owner", "rd_unfreeze");
    app.close();
}

def _offline(app: Served, on: bool) {
    got = app.call("owner", "set_offline_scanning", {"tenant": "nova", "on": on});
    assert got["ok"] , got;
}

def _grant(app: Served, who: str = "usher", device: str = PHONE) -> any {  # jac:ignore[W1037]
    return app.call(
        who,
        "door_grant",
        {"tenant": "nova", "device_id": device, "device_name": "  Main   door "}
    );
}

def _pack(app: Served, grant_id: str, who: str = "usher") -> any {  # jac:ignore[W1037]
    return app.call(
        who, "door_pack", {"tenant": "nova", "device_id": PHONE, "grant_id": grant_id}
    );
}

def _changes(app: Served, cursor: str) -> any {  # jac:ignore[W1037]
    return app.call(
        "usher",
        "door_pack_changes",
        {"tenant": "nova", "device_id": PHONE, "cursor": cursor}
    );
}

test "the hash matches the spec's test vector" {
    assert door_hash(
        "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "7k2m-9qxr-4hjn-p3wd"
    )
        == "4e73291af7471910ef674eb1656b2a4d644badae5e333a879ddefdd028cfd08c";
}

test "a grant once the cinema scans offline, renewed while it's the same member's" {
    (app, nova, screening, codes) = _door([]);
    try {
        assert code_of(_grant(app)) == "offline_scanning_off";
        _offline(app, True);
        got = _grant(app);
        assert got["ok"] , got;
        grant = got["grant"];
        assert grant["device_name"] == "Main door";
        assert grant["venue_ids"] == [nova.venue];
        assert grant["policy"] == "door-policy/1";
        issued = datetime.fromisoformat(got["server_time"]);
        ends = datetime.fromisoformat(grant["expires_at"]);
        assert issued < ends <= issued + timedelta(hours=14) , grant;
        again = _grant(app);
        assert again["grant"]["grant_id"] == grant["grant_id"];
        assert code_of(
            app.call(
                "usher",
                "door_grant",
                {"tenant": "nova", "device_id": "x", "device_name": "Main door"}
            )
        )
            == "invalid_device";
        assert code_of(
            app.call(
                "usher",
                "door_grant",
                {"tenant": "nova", "device_id": PHONE, "device_name": "   "}
            )
        )
            == "invalid_name";
    } finally {
        _close(app);
    }
}

test "the door copy holds the showtime and its tickets by hash, not reference" {
    (app, nova, screening, codes) = _door([]);
    try {
        _offline(app, True);
        grant_id = _grant(app)["grant"]["grant_id"];
        pack = _pack(app, grant_id);
        assert pack["ok"] , pack;
        assert pack["pack_version"] == "door-pack/1";
        assert pack["grant_id"] == grant_id and pack["cursor"] and pack["salt"];
        assert pack["cinema"]["doors_open_minutes"] == 45;
        assert [s["screening_id"] for s in pack["showtimes"]] == [screening];
        assert pack["showtimes"][0]["state"] == "published";
        tickets = pack["tickets"];
        assert len(tickets) == len(codes) > 0 , tickets;
        hashes = sorted([t["h"] for t in tickets]);
        assert hashes
            == sorted([door_hash(pack["salt"], c["reference"]) for c in codes]);
        for t in tickets {
            assert "reference" not in t and t["status"] == "issued" and t["seat"];
        }
        text = str(pack);
        for c in codes {
            assert c["reference"] not in text
                and c["reference"].replace("-", "") not in text;
        }
        # Another grant's id, or none, gets nothing.
        assert code_of(_pack(app, "not-a-grant")) == "grant_revoked";
    } finally {
        _close(app);
    }
}

test "a scan shows in the changes; a forged cursor is refused, an old one resyncs" {
    (app, nova, screening, codes) = _door([]);
    try {
        _offline(app, True);
        grant_id = _grant(app)["grant"]["grant_id"];
        pack = _pack(app, grant_id);
        quiet = _changes(app, pack["cursor"]);
        assert quiet["ok"] and quiet["tickets"] == [] and not quiet["more"] , quiet;
        scanned = app.call(
            "usher",
            "redeem_ticket",
            {"tenant": "nova", "screening_id": screening, "code": codes[0]["reference"]}
        );
        assert scanned["ok"] , scanned;
        changed = _changes(app, quiet["cursor"]);
        assert changed["ok"] and changed["pack_id"] == pack["pack_id"] , changed;
        rows = changed["tickets"];
        assert [r["h"] for r in rows]
            == [door_hash(pack["salt"], codes[0]["reference"])];
        assert rows[0]["status"] == "used" and rows[0]["version"] == 2;
        assert rows[0]["used_at"];
        # Not this server's cursor, or another device's.
        (body, _, sig) = changed["cursor"].partition(".");
        assert code_of(_changes(app, f"{body}.{'0' * len(sig)}")) == "invalid_cursor";
        assert code_of(
            app.call(
                "usher",
                "door_pack_changes",
                {
                    "tenant": "nova",
                    "device_id": "phone-0002",
                    "cursor": changed["cursor"]
                }
            )
        )
            == "invalid_cursor";
        # Over 30 minutes since the last sync: fetch a new copy.
        _at(app, screening, 2);
        assert _changes(app, changed["cursor"])["resync"];
    } finally {
        _close(app);
    }
}

test "a revoked device stops; no grant without tickets.scan, or at another cinema" {
    (app, nova, screening, codes) = _door(["agent", "rival"]);
    try {
        _offline(app, True);
        hire(app, "agent", "box_office_agent", nova.venue);
        assert code_of(_grant(app, "agent", "phone-0003-agent")) == "forbidden";
        grant_id = _grant(app)["grant"]["grant_id"];
        revoked = app.call(
            "owner", "revoke_door_device", {"tenant": "nova", "device_id": PHONE}
        );
        assert revoked["ok"] and revoked["revoked_at"] , revoked;
        assert code_of(_pack(app, grant_id)) == "grant_revoked";
        assert code_of(_grant(app)) == "device_revoked";
        assert code_of(
            app.call(
                "usher", "revoke_door_device", {"tenant": "nova", "device_id": PHONE}
            )
        )
            == "forbidden";
        open_cinema_for(app, "rival", "rift", "Rift Cinemas");
        assert code_of(_grant(app, "rival", "phone-0004-rival")) == "not_found";
        # Turned off: the next sync stops too.
        _offline(app, False);
        assert code_of(_pack(app, grant_id)) == "offline_scanning_off";
    } finally {
        _close(app);
    }
}
