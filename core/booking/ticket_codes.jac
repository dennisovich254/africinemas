"""Ticket references and their signed QR payloads (P6.1, architecture §46; ADR-0020).

A reference is 16 random characters from an alphabet without 0/O or 1/I, in four
groups ("7K2M-9QXR-4HJN-P3WD"): 80 random bits, easy to read out at the door. It is
claimed (namespace REFS, owner "<tenant id>|<ticket id>") before its ticket is stored,
so it is unique across every cinema and the scanner (6.2) finds the ticket from it.

The QR holds "TKT1.<reference without dashes>.<signature>": the signature is an
HMAC-SHA256 over "TKT1.<reference>" with the server's ticket key
(AFRICINEMAS_TICKET_KEY), cut to 128 bits and written in base32. Nothing personal or
descriptive is in it. "TKT1" is the format and key version, so the key can be rotated
later. read_qr only says the payload was made by this server; whether the ticket is
valid, for this showtime and unused is the server's answer at the door (6.2).
"""

import os;
import hmac;
import base64;
import hashlib;
import secrets;
import from core.claims { claim }

glob KEY_ENV: str = "AFRICINEMAS_TICKET_KEY",
     KEY_MIN_LENGTH: int = 32,
     VERSION: str = "TKT1",
     REFS: str = "ticket-ref",
     ALPHABET: str = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ",
     REFERENCE_LENGTH: int = 16,
     SIGNATURE_LENGTH: int = 26,
     DRAWS: int = 5;

class TicketKeyMissing(RuntimeError) {}

def ticket_key -> bytes {
    # The server's ticket signing key; refuses when it is unset or too short to be one.
    key = os.environ.get(KEY_ENV, "").strip();
    if len(key) < KEY_MIN_LENGTH {
        raise TicketKeyMissing(
            f"Set {KEY_ENV} to a random secret of at least {KEY_MIN_LENGTH} characters "
                + "(for example: openssl rand -hex 32)."
        );
    }
    return key.encode("utf-8");
}

def new_reference -> str {
    picked = "".join([secrets.choice(ALPHABET) for _ in range(REFERENCE_LENGTH)]);
    return "-".join([picked[i:i + 4] for i in range(0, REFERENCE_LENGTH, 4)]);
}

def _signature(compact: str) -> str {
    mac = hmac.new(
        ticket_key(), f"{VERSION}.{compact}".encode("utf-8"), hashlib.sha256
    ).digest();
    return base64.b32encode(mac[:16]).decode("ascii").rstrip("=");
}

def qr_payload(reference: str) -> str {
    compact = reference.replace("-", "");
    return f"{VERSION}.{compact}.{_signature(compact)}";
}

def read_qr(payload: str) -> str | None {
    # The reference a payload was signed for, or None if this server didn't sign it.
    parts = payload.split(".");
    if len(parts) != 3 or parts[0] != VERSION {
        return None;
    }
    (_, compact, given) = parts;
    if len(compact) != REFERENCE_LENGTH
        or len(given) != SIGNATURE_LENGTH
        or any([ch not in ALPHABET for ch in compact]) {
        return None;
    }
    if not hmac.compare_digest(_signature(compact), given) {
        return None;
    }
    return "-".join([compact[i:i + 4] for i in range(0, REFERENCE_LENGTH, 4)]);
}

def typed_reference(text: str) -> str | None {
    # A reference as staff type it (6.4's manual entry), tidied: case, spaces and
    # dashes don't matter. None if it can't be one.
    compact = text.upper().replace(" ", "").replace("-", "");
    if len(compact) != REFERENCE_LENGTH
        or any([ch not in ALPHABET for ch in compact]) {
        return None;
    }
    return "-".join([compact[i:i + 4] for i in range(0, REFERENCE_LENGTH, 4)]);
}

def link_token(tenant_id: str, order_id: str) -> str {
    # The secret in an order's ticket link (P6.3, ADR-0022): an HMAC over the order with
    # the ticket key, so it can be made again for the email and the paying visitor's
    # page and is never stored. 128 bits, lower-case base32.
    mac = hmac.new(
        ticket_key(),
        f"order-link|{tenant_id}|{order_id}".encode("utf-8"),
        hashlib.sha256
    ).digest();
    return base64.b32encode(mac[:16]).decode("ascii").rstrip("=").lower();
}

def link_key(token: str) -> str {
    # What a link token is looked up by (ADR-0010: the secret is stored only as a hash).
    return hashlib.sha256(token.encode("utf-8")).hexdigest();
}

def reserve_reference(
    owner: str, ttl_seconds: int, draw: Callable[[], str] = new_reference
) -> str {
    # A reference nobody else holds, claimed for `owner` ("<tenant id>|<ticket id>").
    # Claim it provisionally and make it permanent once the ticket is stored.
    for _ in range(DRAWS) {
        reference = draw();
        if claim(REFS, reference, owner, ttl_seconds) == owner {
            return reference;
        }
    }
    raise RuntimeError(f"no free ticket reference after {DRAWS} draws");
}
