"""A cinema's logo, made to sit on its storefront (ADR-0047), as pure logic.

- `clear_backdrop`: a logo uploaded on a plain backdrop (a white or coloured box) looked
  pasted onto the page. When the four corners share one colour and the logo has no
  transparency of its own, that colour is cleared where it touches the edges, with soft
  edges, and the margins are trimmed. Inside the logo, the same colour stays: only
  backdrop connected to the edges goes.
- `logo_ink` and `readable_scheme`: a pale logo vanished on a light page (Rupa's Mall's
  gold, contrast 1.39, 2026-10-20). The logo's average colour must stand out from the
  page in the mode visitors see; when it doesn't, the storefront shows the other mode.
"""

import io;
import from PIL { Image, ImageChops, ImageDraw, ImageFilter }
import from core.theming.tokens { contrast_ratio }

glob CORNER_SPREAD: int = 24,  # Corners further apart than this (0-255 per channel) are not one backdrop.
     # A pixel this close to the backdrop is backdrop; ramp more is a soft edge.
     NEAR: int = 16,
     RAMP: int = 60,
     # The logo's colour must stand out this much from the page (WCAG's 3:1 is for
     # controls; a logo is large and its own shape, so less is enough).
     LOGO_CONTRAST: float = 2.0;

def _webp(img: Image.Image) -> bytes {
    out = io.BytesIO();
    img.save(out, format="WEBP", quality=88);
    return out.getvalue();
}

def clear_backdrop(webp: bytes) -> bytes {
    # `webp` with its plain backdrop cleared and margins trimmed, or unchanged.
    img = Image.open(io.BytesIO(webp)).convert("RGBA");
    (w, h) = img.size;
    if w < 8 or h < 8 or img.getchannel("A").getextrema()[0] < 250 {
        return webp;  # tiny, or transparent already: the owner made it to sit on a page
    }
    corners = [
        img.getpixel((1, 1)),
        img.getpixel((w - 2, 1)),
        img.getpixel((1, h - 2)),
        img.getpixel((w - 2, h - 2))
    ];
    for i in range(3) {
        values = [c[i] for c in corners];
        if max(values) - min(values) > CORNER_SPREAD {
            return webp;
        }
    }
    backdrop = tuple([sum([c[i] for c in corners]) // 4 for i in range(3)]);
    rgb = img.convert("RGB");
    (r, g, b) = ImageChops.difference(rgb, Image.new("RGB", (w, h), backdrop)).split();
    distance = ImageChops.lighter(ImageChops.lighter(r, g), b);
    # Backdrop is what is near its colour and connected to an edge.
    near = distance.point(lambda (d: int) -> int { return 255 if d < NEAR else 0; });
    for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] {
        if near.getpixel(xy) == 255 {
            ImageDraw.floodfill(near, xy, 128);
        }
    }
    rim = near.point(lambda (v: int) -> int { return 255 if v == 128 else 0; });
    # Two pixels into the logo, so its anti-aliased rim fades instead of keeping a halo.
    rim = rim.filter(ImageFilter.MaxFilter(5));
    soft = distance.point(
        lambda (d: int) -> int { return 0
            if d < NEAR
            else min(255, (d - NEAR) * 255 // RAMP); }
    );
    alpha = Image.composite(soft, Image.new("L", (w, h), 255), rim);
    box = alpha.point(
        lambda (a: int) -> int { return 255 if a > 24 else 0; }
    ).getbbox();
    if box is None {
        return webp;  # all backdrop: nothing to show, keep what was uploaded
    }
    (left, top, right, bottom) = box;
    if (right - left) * (bottom - top) < w * h // 50 {
        return webp;  # a speck: more likely a misread than a logo
    }
    img.putalpha(alpha);
    return _webp(img.crop(box));
}

def logo_ink(webp: bytes) -> str {
    # The logo's average colour over its visible pixels, as #rrggbb ("" if none).
    img = Image.open(io.BytesIO(webp)).convert("RGBA");
    img.thumbnail((128, 128));
    (total, r, g, b) = (0, 0, 0, 0);
    for (pr, pg, pb, pa) in img.get_flattened_data() {
        if pa >= 128 {
            total += 1;
            r += pr;
            g += pg;
            b += pb;
        }
    }
    if total == 0 {
        return "";
    }
    return "#%02x%02x%02x" % (r // total, g // total, b // total);
}

def readable_scheme(theme: dict[str, any], ink: str) -> str {  # jac:ignore[W1037]
    # The scheme to show so the logo stands out: the theme's own when its mode (or, for
    # auto, both modes) does, otherwise the mode where the logo stands out more.
    scheme = str(theme.get("scheme", "auto"));
    if not ink {
        return scheme;
    }
    light = contrast_ratio(ink, theme["light"]["background"]);
    dark = contrast_ratio(ink, theme["dark"]["background"]);
    if scheme == "light"
        and light >= LOGO_CONTRAST
        or scheme == "dark"
        and dark >= LOGO_CONTRAST
        or scheme == "auto"
        and min(light, dark) >= LOGO_CONTRAST {
        return scheme;
    }
    return "light" if light >= dark else "dark";
}
