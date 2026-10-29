"""P15.0: verification files sealed at rest (core/tenancy/file_box.jac, DPIA R1).

A file opens with the same secret and for the same document only; without the secret
nothing is sealed or opened; something not sealed is refused.
"""

import os;
import from core.tenancy.file_box {
    KEY_ENV,
    MAGIC,
    seal_file,
    open_file,
    files_key_ready,
    CannotOpenFile,
    FilesKeyMissing
}

glob SECRET: str = "unit-files-sealing-key-0123456789abcdef";

def _with(secret: str | None) -> str | None {
    # Sets the secret (None: unset); returns what it was.
    before = os.environ.get(KEY_ENV);
    if secret is None {
        os.environ.pop(KEY_ENV, None);
    } else {
        os.environ[KEY_ENV] = secret;
    }
    return before;
}

test "a sealed file opens for its own document with its own secret only" {
    before = _with(SECRET);
    try {
        photo = b"\xff\xd8\xff photo of an ID";
        sealed = seal_file(photo, "verification:t1:id_front:k1");
        assert sealed.startswith(MAGIC) and photo not in sealed;
        assert seal_file(photo, "verification:t1:id_front:k1") != sealed , "a fresh nonce each time";
        assert open_file(sealed, "verification:t1:id_front:k1") == photo;
        # Another cinema, document or key: it doesn't open.
        for other in [
            "verification:t2:id_front:k1",
            "verification:t1:id_back:k1",
            "verification:t1:id_front:k2"
        ] {
            try {
                open_file(sealed, other);
                assert False , other;
            } except CannotOpenFile {}
        }
        # Changed by one byte: it doesn't open.
        try {
            open_file(
                sealed[:-1] + bytes([sealed[-1] ^ 1]), "verification:t1:id_front:k1"
            );
            assert False , "a changed file opened";
        } except CannotOpenFile {}
        # Not sealed at all.
        try {
            open_file(photo, "verification:t1:id_front:k1");
            assert False , "an unsealed file opened";
        } except CannotOpenFile {}
        # Another secret.
        _with("another-files-sealing-key-0123456789abcdef");
        try {
            open_file(sealed, "verification:t1:id_front:k1");
            assert False , "opened with another secret";
        } except CannotOpenFile {}
    } finally {
        _with(before);
    }
}

test "without the secret, nothing is sealed or opened" {
    before = _with(None);
    try {
        assert not files_key_ready();
        for short in [None, "too-short"] {
            _with(short);
            try {
                seal_file(b"x", "c");
                assert False , short;
            } except FilesKeyMissing {}
        }
        _with(SECRET);
        assert files_key_ready();
    } finally {
        _with(before);
    }
}
