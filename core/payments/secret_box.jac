"""Sealing each cinema's M-Pesa keys (P15.3, ADR-0082).

A cinema's Daraja consumer key, consumer secret and passkey are kept only sealed: AES-256-
GCM, with a key derived (HKDF-SHA256) from AFRICINEMAS_MPESA_KEY, a secret kept in the
server's environment and never in the database. Someone who copies the database gets
nothing they can use without it.

Each sealed value is bound to what it is for (`context`: the cinema, the account's
version and the field) as GCM's associated data, so a sealed value moved to another
cinema, version or field doesn't open. A sealed value is "v1." and base64 of a fresh
12-byte nonce and the ciphertext with its tag.

Without the secret (unset, or shorter than 32 characters) nothing is sealed or opened:
connecting M-Pesa is refused, rather than keeping keys in the clear.
"""

import os;
import base64;
import from cryptography.hazmat.primitives { hashes }
import from cryptography.hazmat.primitives.kdf.hkdf { HKDF }
import from cryptography.hazmat.primitives.ciphers.aead { AESGCM }
import from cryptography.exceptions { InvalidTag }

glob KEY_ENV: str = "AFRICINEMAS_MPESA_KEY",
     KEY_MIN_LENGTH: int = 32,
     VERSION: str = "v1",
     NONCE_BYTES: int = 12;

class SealingKeyMissing(RuntimeError) {}

class CannotOpen(ValueError) {}

def _key -> bytes {
    secret = os.environ.get(KEY_ENV, "").strip();
    if len(secret) < KEY_MIN_LENGTH {
        raise SealingKeyMissing(
            f"Set {KEY_ENV} to a random secret of at least {KEY_MIN_LENGTH} characters "
                + "(for example: openssl rand -hex 32)."
        );
    }
    return HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=b"africinemas mpesa keys v1"
    ).derive(
        secret.encode("utf-8")
    );
}

def sealing_ready -> bool {
    try {
        _key();
    } except SealingKeyMissing {
        return False;
    }
    return True;
}

def seal(plain: str, context: str) -> str {
    nonce = os.urandom(NONCE_BYTES);
    sealed = AESGCM(_key()).encrypt(
        nonce, plain.encode("utf-8"), context.encode("utf-8")
    );
    return f"{VERSION}." + base64.urlsafe_b64encode(nonce + sealed).decode("ascii");
}

def open_sealed(token: str, context: str) -> str {
    # The value sealed for `context`; CannotOpen if it was sealed for something else,
    # changed, or sealed with another secret.
    (version, _, body) = token.partition(".");
    if version != VERSION or not body {
        raise CannotOpen("Not a sealed value.");
    }
    try {
        raw = base64.urlsafe_b64decode(body.encode("ascii"));
        plain = AESGCM(_key()).decrypt(
            raw[:NONCE_BYTES], raw[NONCE_BYTES:], context.encode("utf-8")
        );
    } except (InvalidTag, ValueError) as e {
        raise CannotOpen("The sealed value doesn't open.") from e;
    }
    return plain.decode("utf-8");
}
