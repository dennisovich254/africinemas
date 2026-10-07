"""P6.1: tickets issued when a payment is confirmed carry a unique reference and a
signed QR payload (architecture §46).

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa. Each reference is
claimed (core/claims.jac, namespace "ticket-ref") for its cinema and ticket, so it is
unique across every cinema and the scanner (6.2) can find the ticket from it. The QR
payload verifies with the server's key and holds nothing personal.
"""

import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup { browse }
import from tests.support.payment_setup { ANNA, paying_setup, paid }
import from core.booking.ticket_codes { read_qr }

def _codes(app: Served, screening: str) -> list[dict[str, str]] {
    return app.call(
        "owner", "pay_ticket_codes", {"slug": "nova", "screening_id": screening}
    );
}

test "a paid order's tickets have unique, claimed references and QR payloads that verify" {
    (app, screening) = paying_setup();
    try {
        paid(app, screening);
        codes = _codes(app, screening);
        assert [c["seat_label"] for c in codes] == ["A1", "A2"] , codes;
        assert codes[0]["reference"] != codes[1]["reference"];
        for c in codes {
            assert c["claimed_by"] == f"{c['tenant_id']}|{c['ticket_id']}" , c;
            assert read_qr(c["qr"]) == c["reference"] , c;
            # Nothing personal or descriptive in the QR (§46): only the version, the
            # reference and a 26-character signature. (Searching it for words like "A2"
            # can't work: the base32 signature contains such pairs by chance.)
            (version, compact, signature) = c["qr"].split(".");
            assert version == "TKT1" and compact == c["reference"].replace("-", "");
            assert len(signature) == 26 and signature.isalnum() , c["qr"];
        }
        mine = browse(
            app,
            "my_payment",
            {"slug": "nova", "screening_id": screening, "holder": ANNA}
        )["payment"];
        assert [[t["reference"], t["qr"]] for t in mine["tickets"]]
            == [[c["reference"], c["qr"]] for c in codes] , mine;
    } finally {
        app.close();
    }
}

test "a reference someone already holds is never reused: another one is drawn" {
    (app, _) = paying_setup();
    try {
        taken = f"TAKEN-{uuid.uuid4().hex[:8]}";
        fresh = f"FRESH-{uuid.uuid4().hex[:8]}";
        got = app.call(
            "owner", "pay_reserve_collision", {"taken": taken, "fresh": fresh}
        );
        assert got == [fresh, "someone-else", "me"] , got;
    } finally {
        app.close();
    }
}
