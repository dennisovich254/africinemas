"""Browser helpers for end-to-end tests (Playwright, driven from Jac).

Two projects, as the plan requires for every UI test: a phone (Pixel 7: touch, mobile
viewport, device pixel ratio) and a 1440x900 desktop. Each opens in a chosen colour scheme.
The server is started by scripts/e2e.sh, which exports E2E_BASE_URL.
"""

import os;
import struct;
import zlib;
import from pathlib { Path }
import from playwright.sync_api { sync_playwright }

glob BASE_URL: str = os.environ.get("E2E_BASE_URL", "http://127.0.0.1:8870"),
     ARTIFACTS: Path = Path(__file__).resolve().parent.parent / "artifacts",
     PROJECTS: list[str] = ["mobile", "desktop"];

def context_options(pw: any, project: str, scheme: str) -> dict[str, any] {  # jac:ignore[W1037]
    if project == "mobile" {
        return {** pw.devices["Pixel 7"], "color_scheme": scheme};
    }
    return {"viewport": {"width": 1440, "height": 900}, "color_scheme": scheme};
}

def hex_to_rgb(hex_color: str) -> str {
    # Matches the format of getComputedStyle colours: "rgb(r, g, b)".
    r = int(hex_color[1:3], 16);
    g = int(hex_color[3:5], 16);
    b = int(hex_color[5:7], 16);
    return f"rgb({r}, {g}, {b})";
}

def computed(page: any, selector: str, prop: str) -> str {  # jac:ignore[W1037]
    return page.evaluate(
        "([s, p]) => getComputedStyle(document.querySelector(s)).getPropertyValue(p)",
        [selector, prop]
    ).strip();
}

def artifact(name: str) -> str {
    ARTIFACTS.mkdir(parents=True, exist_ok=True);
    return str(ARTIFACTS / name);
}


def _png_pixel(png: bytes) -> str {
    # Decode the first pixel of a small PNG (8-bit RGB/RGBA) with the standard library.
    pos = 8;
    idat = b"";
    channels = 4;
    while pos < len(png) {
        length = struct.unpack(">I", png[pos:pos + 4])[0];
        kind = png[pos + 4:pos + 8];
        body = png[pos + 8:pos + 8 + length];
        pos += 12 + length;
        if kind == b"IHDR" {
            channels = 4 if body[9] == 6 else 3;
        } elif kind == b"IDAT" {
            idat += body;
        }
    }
    raw = zlib.decompress(idat);
    # Row 0, filter byte then the first pixel; filters only reference earlier bytes,
    # and the first pixel of the first row has none, so its bytes are literal.
    return "#" + "".join(f"{b:02X}" for b in raw[1:4]);
}

def painted_color(page: any, selector: str) -> str {  # jac:ignore[W1037]
    # The colour actually painted just inside the element's left edge (clear of the text),
    # after compositing, read from a 1x1 screenshot.
    point = page.locator(selector).evaluate(
        "e => { const r = e.getBoundingClientRect(); return [Math.round(r.x + 6), Math.round(r.y + r.height / 2)]; }"
    );
    png = page.screenshot(clip={"x": point[0], "y": point[1], "width": 1, "height": 1});
    return _png_pixel(png);
}
