"""Sealing verification files at rest (P15.0, DPIA R1).

An owner's ID photos and the business's certificates are stored sealed: AES-256-GCM,
with a key derived (HKDF-SHA256) from AFRICINEMAS_FILES_KEY, a secret kept in the
server's environment and never in the database or the file store, and apart from the
M-Pesa keys' secret (core/payments/secret_box.jac). Someone who copies the file store
gets nothing they can read without it.

Each file is bound to what it is (`context`: the cinema, the document and its storage
key) as GCM's associated data, so a sealed file moved to another cinema or document
doesn't open. A sealed file is MAGIC, a fresh 12-byte nonce, then the ciphertext with
its tag.

Without the secret (unset, or shorter than 32 characters) nothing is sealed or opened:
uploading a document is refused, rather than storing it in the clear.
"""

import os;
import from cryptography.hazmat.primitives { hashes }
import from cryptography.hazmat.primitives.kdf.hkdf { HKDF }
import from cryptography.hazmat.primitives.ciphers.aead { AESGCM }
import from cryptography.exceptions { InvalidTag }

glob KEY_ENV: str = "AFRICINEMAS_FILES_KEY",
     KEY_MIN_LENGTH: int = 32,
     MAGIC: bytes = b"ACF1",
     NONCE_BYTES: int = 12;

class FilesKeyMissing(RuntimeError) {}

class CannotOpenFile(ValueError) {}

def _key -> bytes {
    secret = os.environ.get(KEY_ENV, "").strip();
    if len(secret) < KEY_MIN_LENGTH {
        raise FilesKeyMissing(
            f"Set {KEY_ENV} to a random secret of at least {KEY_MIN_LENGTH} characters "
                + "(for example: openssl rand -hex 32)."
        );
    }
    return HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=b"africinemas verification files v1"
    ).derive(
        secret.encode("utf-8")
    );
}

def files_key_ready -> bool {
    try {
        _key();
    } except FilesKeyMissing {
        return False;
    }
    return True;
}

def seal_file(data: bytes, context: str) -> bytes {
    nonce = os.urandom(NONCE_BYTES);
    return MAGIC + nonce + AESGCM(_key()).encrypt(nonce, data, context.encode("utf-8"));
}

def open_file(sealed: bytes, context: str) -> bytes {
    # The file sealed for `context`; CannotOpenFile if it was sealed for something
    # else, changed, or sealed with another secret.
    if not sealed.startswith(MAGIC) {
        raise CannotOpenFile("Not a sealed file.");
    }
    body = sealed[len(MAGIC):];
    try {
        return AESGCM(_key()).decrypt(
            body[:NONCE_BYTES], body[NONCE_BYTES:], context.encode("utf-8")
        );
    } except InvalidTag {
        raise CannotOpenFile(
            "This file doesn't open with this key, or for this document."
        );
    }
}
