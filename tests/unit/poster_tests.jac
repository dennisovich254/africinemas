"""P3.4: checking and converting uploaded posters (pure logic, core/catalog/poster.jac).

Architecture §56: validate the declared type and the file's signature, cap the size, the
dimensions and the decoded pixels, and store a clean re-encoding under a random key. The
output is always WebP, at most 800 x 1200, with no metadata carried over.
"""

import io;
import base64;
import from PIL { Image }
import from core.catalog.poster {
    PosterRejected,
    MAX_UPLOAD_BYTES,
    OUT_WIDTH,
    OUT_HEIGHT,
    decode_upload,
    process_poster,
    media_key
}

def _image(
    fmt: str, size: tuple[int, int], mode: str = "RGB", exif: bytes = b""
) -> bytes {
    out = io.BytesIO();
    img = Image.new(mode, size, "#3F34C6" if mode == "RGB" else 128);
    if exif {
        img.save(out, format=fmt, exif=exif);
    } else {
        img.save(out, format=fmt);
    }
    return out.getvalue();
}

def _code(data: bytes, declared: str) -> str {
    try {
        process_poster(data, declared);
    } except PosterRejected as e {
        return e.code;
    }
    return "";
}

def _opened(data: bytes) -> any {  # jac:ignore[W1037]
    return Image.open(io.BytesIO(data));
}

test "a PNG poster is re-encoded as WebP and scaled down to fit 800 x 1200" {
    out = process_poster(_image("PNG", (1000, 1500)), "image/png");
    assert out[:4] == b"RIFF" and out[8:12] == b"WEBP";
    img = _opened(out);
    assert img.format == "WEBP";
    assert img.size == (OUT_WIDTH, OUT_HEIGHT) , img.size;
}

test "a smaller poster keeps its size" {
    img = _opened(process_poster(_image("JPEG", (400, 600)), "image/jpeg"));
    assert img.size == (400, 600);
}

test "metadata such as a photo's GPS position isn't carried over" {
    exif = Image.Exif();
    exif[0x010F] = "PhoneMaker";  # Make
    exif[0x8825] = {1: "S", 2: (1.0, 17.0, 0.0)};  # GPS IFD
    source = _image("JPEG", (400, 600), exif=exif.tobytes());
    assert len(_opened(source).getexif()) > 0 , "the source really has EXIF";
    cleaned = _opened(process_poster(source, "image/jpeg"));
    assert len(cleaned.getexif()) == 0;
    assert "exif" not in cleaned.info;
}

test "only JPEG, PNG and WebP are accepted, and the bytes must match the declared type" {
    png = _image("PNG", (400, 600));
    assert _code(png, "image/gif") == "wrong_type";
    assert _code(png, "application/pdf") == "wrong_type";
    assert _code(png, "image/jpeg") == "wrong_type" , "a PNG sent as a JPEG";
    assert _code(_image("GIF", (400, 600), mode="P"), "image/png") == "wrong_type";
    assert _code(b"%PDF-1.7 not an image at all", "image/png") == "wrong_type";
    assert _code(b"<svg onload=alert(1)></svg>", "image/png") == "wrong_type";
    assert _code(_image("WEBP", (400, 600)), "image/webp") == "";
}

test "posters that are too small, too large or broken are refused" {
    assert _code(_image("PNG", (100, 150)), "image/png") == "too_small";
    # 9000 x 9000 compresses to very little but would take ~81 MP to decode.
    huge = _image("PNG", (9000, 9000), mode="L");
    assert len(huge) < MAX_UPLOAD_BYTES , "small on disk";
    assert _code(huge, "image/png") == "too_large";
    good = _image("PNG", (400, 600));
    assert _code(good[:len(good) - 40], "image/png") == "invalid_image";
    assert _code(b"", "image/png") == "wrong_type";
}

test "uploads are base64 and capped before decoding" {
    png = _image("PNG", (400, 600));
    assert decode_upload(base64.b64encode(png).decode()) == png;
    for bad in ["not base64!!", "abc", ""] {
        try {
            decode_upload(bad);
            assert False , f"{bad!r} was accepted";
        } except PosterRejected as e {
            assert e.code == "invalid_image" , e.code;
        }
    }
    oversized = base64.b64encode(b"\x00" * (MAX_UPLOAD_BYTES + 1)).decode();
    try {
        decode_upload(oversized);
        assert False , "an oversized upload was accepted";
    } except PosterRejected as e {
        assert e.code == "too_large";
    }
}

test "posters are stored under the cinema's media folder with a random name" {
    assert media_key("t-123", "0f8e") == "tenant/t-123/media/0f8e.webp";
}
