"""A logo made to sit on its storefront (ADR-0047): its plain backdrop cleared and trimmed,
and a scheme that shows it.
"""

import io;
import from PIL { Image, ImageDraw }
import from core.theming.tokens { DEFAULT_THEME }
import from core.theming.logo { clear_backdrop, logo_ink, readable_scheme }

def _webp(img: any) -> bytes {  # jac:ignore[W1037]
    out = io.BytesIO();
    img.save(out, "WEBP", lossless=True);
    return out.getvalue();
}

def _ring_on_white -> bytes {
    # A gold ring on a white box, its middle white too (inside the logo, not backdrop).
    img = Image.new("RGB", (300, 200), (255, 255, 255));
    ImageDraw.Draw(img).ellipse((100, 50, 200, 150), outline=(201, 164, 58), width=14);
    return _webp(img);
}

test "a logo on a plain backdrop is cleared and trimmed; white inside it stays" {
    clean = Image.open(io.BytesIO(clear_backdrop(_ring_on_white())));
    assert clean.mode == "RGBA";
    (w, h) = clean.size;
    assert w <= 110 and h <= 110 , "the margins are trimmed";
    assert clean.getpixel((0, 0))[3] < 40 , "the backdrop is clear";
    assert clean.getpixel((w // 2, h // 2))[3] > 240 , "the white inside the ring stays";
    assert clean.getpixel((w // 2, 4))[3] > 200 , "the ring stays";
}

test "a logo with its own transparency, mixed corners or no logo is left as it was" {
    clear = Image.new("RGBA", (200, 200), (0, 0, 0, 0));
    ImageDraw.Draw(clear).ellipse((40, 40, 160, 160), fill=(20, 20, 20, 255));
    banner = Image.new("RGB", (200, 200), (255, 255, 255));
    ImageDraw.Draw(banner).rectangle((0, 100, 200, 200), fill=(170, 20, 30));
    blank = Image.new("RGB", (200, 200), (231, 176, 58));
    for img in [clear, banner, blank] {
        raw = _webp(img);
        assert clear_backdrop(raw) == raw;
    }
}

test "the mode visitors see always shows the logo" {
    theme = DEFAULT_THEME.as_dict();
    pale_gold = "#e6da6b";
    navy = "#1b2340";
    theme["scheme"] = "light";
    assert readable_scheme(theme, pale_gold) == "dark" , "pale gold vanishes on light";
    assert readable_scheme(theme, navy) == "light";
    theme["scheme"] = "dark";
    assert readable_scheme(theme, navy) == "light" , "navy vanishes on dark";
    theme["scheme"] = "auto";
    assert readable_scheme(theme, pale_gold) == "dark";
    assert readable_scheme(theme, "") == "auto" , "no logo, no change";
    gold = Image.new("RGBA", (40, 40), (0, 0, 0, 0));
    ImageDraw.Draw(gold).rectangle((10, 10, 30, 30), fill=(230, 218, 107, 255));
    assert logo_ink(_webp(gold)) == pale_gold , "transparent pixels are not the logo";
}

test "a logo whose artwork touches a corner still loses its backdrop" {
    # Most of the edge is white; the gold mark runs into one corner (Warui's logo).
    img = Image.new("RGB", (300, 160), (255, 255, 255));
    draw = ImageDraw.Draw(img);
    draw.rectangle((40, 40, 160, 120), outline=(201, 164, 58), width=10);
    draw.polygon([(230, 160), (300, 90), (300, 160)], fill=(230, 218, 107));
    clean = Image.open(io.BytesIO(clear_backdrop(_webp(img))));
    (w, h) = clean.size;
    # Trimmed to the artwork, from (40, 40): (200, 50) was white backdrop.
    assert (w, h) == (260, 120) , clean.size;
    assert clean.getpixel((160, 10))[3] < 40 , "the white backdrop is cleared";
    assert clean.getpixel((w - 2, h - 2))[3] > 200 , "the mark in the corner stays";
}
