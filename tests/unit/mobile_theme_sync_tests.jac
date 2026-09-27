"""P0.8b: the mobile app's palette comes from the same tokens as web/desktop.

mobile/theme.jac is client code (React Native), so it can't import the server-side token
module at runtime; this test keeps its defaults in sync with DEFAULT_THEME.dark instead.
Per-tenant and light/dark theming on mobile arrive with the mobile screens in P10.
"""

import re;
import from pathlib { Path }
import from core.theming.tokens { DEFAULT_THEME }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     # mobile Palette field -> theme role (storefront, dark mode)
     MOBILE_MAP: dict[str, str] = {
         "bg": "background",
         "surface": "surface",
         "border": "border",
         "field": "raised",
         "text": "ink",
         "muted": "muted",
         "accent": "accent",
         "onAccent": "on_accent",
         "danger": "danger"
     };

test "mobile palette matches the default theme's dark tokens" {
    source = (REPO_ROOT / "mobile" / "theme.jac").read_text();
    palette = source[source.index("obj Palette"):source.index("obj Spacing")];
    defaults = {
        k: v.upper()
        for (k, v) in re.findall(r"(\w+): str = \"(#[0-9A-Fa-f]{6})\"", palette)
    };
    expected = DEFAULT_THEME.dark.as_dict();
    for (field, role) in MOBILE_MAP.items() {
        assert field in defaults , f"mobile Palette has no {field}";
        assert defaults[field] == expected[role] , f"mobile {field}={defaults[
            field
        ]} but dark {role}={expected[role]}";
    }
}
