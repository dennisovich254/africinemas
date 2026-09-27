"""Browser helpers for end-to-end tests (Playwright, driven from Jac).

Two projects, as the plan requires for every UI test: a phone (Pixel 7: touch, mobile
viewport, device pixel ratio) and a 1440x900 desktop. Each opens in a chosen colour scheme.
The server is started by scripts/e2e.sh, which exports E2E_BASE_URL.
"""

import os;
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
