"""P6.1: ticket references and their signed QR payloads (core/booking/ticket_codes.jac).

The QR holds only "TKT1.<reference>.<signature>": a random reference and an HMAC over
it with the server's ticket key. No name, phone, movie or seat (architecture §46). A
payload whose reference, signature or version was changed, or that was signed with
another key, reads as nothing. The server stays the authority on what a reference is.
"""

import os;
import from core.booking.ticket_codes {
    KEY_ENV,
    TicketKeyMissing,
    new_reference,
    typed_reference,
    link_token,
    link_key,
    qr_payload,
    read_qr,
    ticket_key
}

glob KEY: str = "unit-test-ticket-key-0123456789abcdef",
     OTHER: str = "another-ticket-key-0123456789abcdef!";

def _with_key(key: str | None) -> str | None {
    # Sets the ticket key (None removes it); returns what was there.
    before = os.environ.pop(KEY_ENV, None);
    if key is not None {
        os.environ[KEY_ENV] = key;
    }
    return before;
}

def _restore(before: str | None) {
    os.environ.pop(KEY_ENV, None);
    if before is not None {
        os.environ[KEY_ENV] = before;
    }
}

test "a reference is 16 readable characters in four groups, different every time" {
    made = [new_reference() for _ in range(200)];
    assert len(set(made)) == 200;
    for r in made {
        parts = r.split("-");
        assert len(parts) == 4 and all([len(p) == 4 for p in parts]) , r;
        # No 0/O or 1/I to confuse at the door.
        assert all(
            [ch in "23456789ABCDEFGHJKLMNPQRSTUVWXYZ" for ch in r.replace("-", "")]
        ) , r;
    }
}

test "the QR payload is the version, the reference and a signature, nothing else" {
    before = _with_key(KEY);
    try {
        ref = "7K2M-9QXR-4HJN-P3WD";
        payload = qr_payload(ref);
        parts = payload.split(".");
        assert len(parts) == 3 , payload;
        assert parts[0] == "TKT1" and parts[1] == "7K2M9QXR4HJNP3WD";
        assert len(parts[2]) == 26 and parts[2].isalnum() , parts[2];
        assert qr_payload(ref) == payload;
        assert read_qr(payload) == ref;
    } finally {
        _restore(before);
    }
}

test "a changed reference, signature or version, or another key, reads as nothing" {
    before = _with_key(KEY);
    try {
        payload = qr_payload("7K2M-9QXR-4HJN-P3WD");
        (version, compact, sig) = payload.split(".");
        swapped = "A" if sig[0] != "A" else "B";
        assert read_qr(f"{version}.7K2M9QXR4HJNP3WE.{sig}") is None;
        assert read_qr(f"{version}.{compact}.{swapped}{sig[1:]}") is None;
        assert read_qr(f"TKT2.{compact}.{sig}") is None;
        assert read_qr(payload.lower()) is None;
        os.environ[KEY_ENV] = OTHER;
        assert read_qr(payload) is None;
    } finally {
        _restore(before);
    }
}

test "garbage, an empty payload or extra parts read as nothing" {
    before = _with_key(KEY);
    try {
        payload = qr_payload("7K2M-9QXR-4HJN-P3WD");
        for bad in [
            "",
            "TKT1",
            "TKT1..",
            payload + ".EXTRA",
            "https://example.com/?t=" + payload,
            "TKT1.7K2M9QXR.ABC",
            "TKT1.0O1I0O1I0O1I0O1I." + payload.split(".")[2]
        ] {
            assert read_qr(bad) is None , bad;
        }
    } finally {
        _restore(before);
    }
}

test "without a ticket key, or with a short one, signing refuses" {
    for key in [None, "", "   ", "too-short"] {
        before = _with_key(key);
        try {
            refused = False;
            try {
                ticket_key();
            } except TicketKeyMissing as e {
                refused = KEY_ENV in str(e);
            }
            assert refused , key;
            refused = False;
            try {
                qr_payload("7K2M-9QXR-4HJN-P3WD");
            } except TicketKeyMissing {
                refused = True;
            }
            assert refused , key;
        } finally {
            _restore(before);
        }
    }
}

test "a typed reference is tidied: case, spaces and dashes don't matter (P6.2)" {
    for typed in [
        "7K2M-9QXR-4HJN-P3WD",
        "7k2m9qxr4hjnp3wd",
        " 7K2M 9QXR 4HJN P3WD ",
        "7k2m-9qxr 4hjn-p3wd"
    ] {
        assert typed_reference(typed) == "7K2M-9QXR-4HJN-P3WD" , typed;
    }
}

test "a typed reference that can't be one reads as nothing" {
    for bad in [
        "",
        "7K2M-9QXR-4HJN",
        "7K2M-9QXR-4HJN-P3WD-AAAA",
        "0O1I-0O1I-0O1I-0O1I",
        "7K2M_9QXR_4HJN_P3WD"
    ] {
        assert typed_reference(bad) is None , bad;
    }
}

test "an order's link token is the same every time, different per order and per key (P6.3)" {
    before = _with_key(KEY);
    try {
        token = link_token("tenant-1", "order-1");
        assert token == link_token("tenant-1", "order-1");
        assert token != link_token("tenant-1", "order-2");
        assert token != link_token("tenant-2", "order-1");
        assert len(token) == 26 and token.isalnum() and token == token.lower() , token;
        os.environ[KEY_ENV] = OTHER;
        assert link_token("tenant-1", "order-1") != token;
    } finally {
        _restore(before);
    }
}

test "a link token is looked up by its hash, never stored as itself" {
    key = link_key("abc123");
    assert key != "abc123" and len(key) == 64;
    assert link_key("abc123") == key and link_key("abc124") != key;
}
