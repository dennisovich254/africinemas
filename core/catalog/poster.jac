"""Checking and converting uploaded posters (P3.4) and logos (P3.8a), architecture §56,
as pure logic.

An upload arrives as base64. It is capped in size before decoding; its declared type must
be JPEG, PNG or WebP and match the file's signature bytes; its dimensions are read from
the header and capped (including total pixels, against decompression bombs) before the
image is decoded; a file that fails to decode is refused. The result is always a fresh
WebP, at most OUT_WIDTH x OUT_HEIGHT, re-encoded from the pixels alone, so no metadata
(a photo's GPS position, anything smuggled inside the file) is kept. It is stored under
a random name in the cinema's media folder (media_key); the name never comes from the
client.

Posters are always 2:3 (`fit_poster`), the shape every storefront design is drawn for: an
upload close to 2:3 is centre-cropped to it; any other shape (a square, a landscape still)
is shown whole, centred on a blurred, darkened copy of itself, so nothing is cut off.
Posters stored before this are fitted when they are served.
"""

import io;
import os;
import base64;
import binascii;
import from PIL { Image, ImageOps, ImageFilter, ImageEnhance }

glob MAX_UPLOAD_BYTES: int = 5 * 1024 * 1024,
     # A poster's shape, width over height (2:3), and how far from it is still cropped
     # rather than shown whole on a blurred fill.
     POSTER_RATIO: float = 2 / 3,
     CROP_TOLERANCE: float = 0.12,
     MIN_WIDTH: int = 200,
     MIN_HEIGHT: int = 300,
     MAX_SIDE: int = 8000,
     MAX_PIXELS: int = 40000000,
     OUT_WIDTH: int = 800,
     OUT_HEIGHT: int = 1200,
     WEBP_QUALITY: int = 85,
     LOGO_MIN: int = 64,
     LOGO_OUT: int = 512,
     # Home-page photos (P4.1b): landscape or portrait, fitted into PHOTO_OUT square.
     PHOTO_MIN_SIDE: int = 400,
     PHOTO_OUT: int = 1600,
     # Snack photos (P12.1): at least SNACK_MIN square-ish, fitted into SNACK_OUT.
     SNACK_MIN: int = 200,
     SNACK_OUT: int = 800,
     # Movie backdrops (P4.1c): landscape, at least BACKDROP_MIN, fitted into BACKDROP_OUT.
     BACKDROP_MIN: tuple[int, int] = (960, 540),
     BACKDROP_OUT: tuple[int, int] = (1920, 1080),
     # Declared content type -> the format its bytes must be.
     ALLOWED: dict[str, str] = {
         "image/jpeg": "JPEG",
         "image/png": "PNG",
         "image/webp": "WEBP"
     };

class PosterRejected(ValueError) {
    # An upload we won't store, with a code and a message the UI can show.
    def init(self: PosterRejected, code: str, message: str) {
        super.init(message);
        self.code = code;
        self.message = message;
    }
}

glob MEDIA_ENV: str = "AFRICINEMAS_MEDIA_DIR";

def media_store -> any {  # jac:ignore[W1037]
    # Where posters and other media live: local disk (AFRICINEMAS_MEDIA_DIR, default
    # ./storage) unless [scale.storage] configures object storage.
    return store(base_path=os.environ.get(MEDIA_ENV, "./storage"));
}

def read_media(key: str) -> bytes | None {
    # A stored file's bytes; None for no key, or for a file that's gone (deleted, or
    # left in another media folder), so a missing image reads as "none yet", not a crash.
    if not key {
        return None;
    }
    try {
        return media_store().download(key);
    } except FileNotFoundError {
        return None;
    }
}

def media_key(tenant_id: str, name: str) -> str {
    # Where a cinema's poster is stored: never a path from the client (§56).
    return f"tenant/{tenant_id}/media/{name}.webp";
}

def decode_upload(data_base64: str) -> bytes {
    # The uploaded bytes; the size is checked before anything is decoded.
    if len(data_base64) > int(MAX_UPLOAD_BYTES * 4 / 3) + 4 {
        raise PosterRejected("too_large", "Choose an image of up to 5 MB.");
    }
    if not data_base64 {
        raise PosterRejected(
            "invalid_image", "That file couldn't be read as an image."
        );
    }
    try {
        data = base64.b64decode(data_base64, validate=True);
    } except (binascii.Error, ValueError) {
        raise PosterRejected(
            "invalid_image", "That file couldn't be read as an image."
        );
    }
    if len(data) > MAX_UPLOAD_BYTES {
        raise PosterRejected("too_large", "Choose an image of up to 5 MB.");
    }
    return data;
}

def _sniff(data: bytes) -> str {
    # The format the file's signature bytes say it is, or "" for anything else.
    if data[:3] == b"\xff\xd8\xff" {
        return "JPEG";
    }
    if data[:8] == b"\x89PNG\r\n\x1a\n" {
        return "PNG";
    }
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP" {
        return "WEBP";
    }
    return "";
}

def process_poster(data: bytes, declared_type: str) -> bytes {
    # A checked poster, re-encoded as a clean 2:3 WebP. Raises PosterRejected.
    return fit_poster(
        _process(data, declared_type, (MIN_WIDTH, MIN_HEIGHT), (OUT_WIDTH, OUT_HEIGHT))
    );
}

def fit_poster(webp: bytes) -> bytes {
    # The poster as exactly 2:3: unchanged if it is already, centre-cropped if it is
    # close, otherwise whole and centred on a blurred, darkened copy of itself.
    img = Image.open(io.BytesIO(webp));
    (w, h) = img.size;
    if w < 2 or h < 2 {
        return webp;
    }
    if abs(w * 3 - h * 2) <= 2 {
        return webp;  # already 2:3, to the pixel
    }
    picture = img.convert("RGB");
    ratio = w / h;
    if abs(ratio - POSTER_RATIO) / POSTER_RATIO <= CROP_TOLERANCE {
        if ratio > POSTER_RATIO {
            width = h * 2 // 3;
            left = (w - width) // 2;
            fitted = picture.crop((left, 0, left + width, h));
        } else {
            height = w * 3 // 2;
            top = (h - height) // 2;
            fitted = picture.crop((0, top, w, top + height));
        }
    } else {
        # The canvas keeps the picture's own sharpness: as wide as it is, or tall enough.
        width = min(OUT_WIDTH, max(w, h * 2 // 3));
        height = width * 3 // 2;
        fill = ImageOps.fit(picture, (width, height), Image.Resampling.BILINEAR);
        fill = ImageEnhance.Brightness(
            fill.filter(ImageFilter.GaussianBlur(24))
        ).enhance(
            0.55
        );
        whole = picture.copy();
        whole.thumbnail((width, height), Image.Resampling.LANCZOS);
        fill.paste(whole, ((width - whole.width) // 2, (height - whole.height) // 2));
        fitted = fill;
    }
    out = io.BytesIO();
    fitted.save(out, format="WEBP", quality=WEBP_QUALITY);
    return out.getvalue();
}

def process_logo(data: bytes, declared_type: str) -> bytes {
    # A cinema's logo (P3.8a): the same checks, a smaller minimum, fitted into
    # LOGO_OUT x LOGO_OUT, and its transparency kept.
    return _process(data, declared_type, (LOGO_MIN, LOGO_MIN), (LOGO_OUT, LOGO_OUT));
}

def process_backdrop(data: bytes, declared_type: str) -> bytes {
    # A movie's landscape backdrop (P4.1c): the same checks, at least 960 x 540.
    return _process(data, declared_type, BACKDROP_MIN, BACKDROP_OUT);
}

def process_snack_photo(data: bytes, declared_type: str) -> bytes {
    # A snack's photo (P12.1): the same checks, at least 200 x 200 pixels, fitted into
    # SNACK_OUT x SNACK_OUT.
    return _process(
        data, declared_type, (SNACK_MIN, SNACK_MIN), (SNACK_OUT, SNACK_OUT)
    );
}

def process_photo(data: bytes, declared_type: str) -> bytes {
    # A photo for the cinema's home page (P4.1b): the same checks, at least
    # at least 400 x 300 pixels, fitted into PHOTO_OUT x PHOTO_OUT.
    return _process(
        data,
        declared_type,
        (PHOTO_MIN_SIDE, PHOTO_MIN_SIDE * 3 // 4),
        (PHOTO_OUT, PHOTO_OUT)
    );
}

def _process(
    data: bytes,
    declared_type: str,
    min_size: tuple[int, int],
    out_size: tuple[int, int]
) -> bytes {
    # A checked upload, re-encoded as a clean WebP. Raises PosterRejected.
    (min_width, min_height) = min_size;
    wrong_type = PosterRejected("wrong_type", "Choose a JPEG, PNG or WebP image.");
    expected = ALLOWED.get(declared_type, "");
    if not expected or _sniff(data) != expected {
        raise wrong_type;
    }
    if len(data) > MAX_UPLOAD_BYTES {
        raise PosterRejected("too_large", "Choose an image of up to 5 MB.");
    }
    try {
        img = Image.open(io.BytesIO(data));  # reads the header only
    } except Exception {
        raise PosterRejected(
            "invalid_image", "That file couldn't be read as an image."
        );
    }
    if img.format != expected {
        raise wrong_type;
    }
    (width, height) = img.size;
    if width * height > MAX_PIXELS or width > MAX_SIDE or height > MAX_SIDE {
        raise PosterRejected(
            "too_large", f"Choose an image of at most {MAX_SIDE} pixels on each side."
        );
    }
    if width < min_width or height < min_height {
        raise PosterRejected(
            "too_small",
            f"Choose an image of at least {min_width} x {min_height} pixels."
        );
    }
    try {
        img.load();
        # Honour the camera's orientation before the metadata that carries it is dropped.
        upright = ImageOps.exif_transpose(img);
    } except Exception {
        raise PosterRejected(
            "invalid_image", "That file couldn't be read as an image."
        );
    }
    mode = "RGBA"
        if upright.mode in ("RGBA", "LA", "P") and upright.has_transparency_data
        else "RGB";
    pixels = upright.convert(mode);
    pixels.thumbnail(out_size);
    # A new image from the pixels alone: nothing from the upload's metadata survives.
    clean = Image.frombytes(mode, pixels.size, pixels.tobytes());
    out = io.BytesIO();
    clean.save(out, format="WEBP", quality=WEBP_QUALITY);
    return out.getvalue();
}
