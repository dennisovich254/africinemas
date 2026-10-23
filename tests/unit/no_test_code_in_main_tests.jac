"""The production app never serves test-only code (P14.1).

core/testing/ holds endpoints that only tests may have, such as t_go_live, which makes a
cinema public without the platform's review. main.jac (and desktop/, mobile/) must
never import it, directly or through another module.
"""

import from pathlib { Path }

glob ROOT: Path = Path(__file__).resolve().parent.parent.parent;

test "main.jac and the modules it serves never import core.testing" {
    for path in [ROOT / "main.jac"]
        + sorted((ROOT / "core").rglob("*.jac"))
        + sorted((ROOT / "web").rglob("*.jac")) {
        if "core/testing" in str(path) {
            continue;
        }
        text = path.read_text();
        assert "core.testing" not in text , f"{path} imports test-only code";
    }
}
