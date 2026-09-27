"""Guard (ADR-0006): app code must not define `_`-prefixed walkers.

The guides describe `_before_request` / `_authenticate` walkers as middleware hooks, but
on Jac 0.37.18 they never run, and they are exposed as ordinary public routes
(/walker/_before_request). A hook written from the docs would silently protect nothing.
"""

import re;
import from pathlib { Path }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     APP_SOURCES: list[str] = ["main.jac", "web", "core", "desktop", "mobile"],
     UNDERSCORE_WALKER: str = r"^\s*walker\s*(:\w+\s*)?_\w*";

test "no app module defines an underscore walker" {
    offenders: list[str] = [];
    for source in APP_SOURCES {
        target = REPO_ROOT / source;
        files = [target] if target.is_file() else sorted(target.rglob("*.jac"));
        for f in files {
            for (n, line) in enumerate(f.read_text().splitlines(), start=1) {
                if re.match(UNDERSCORE_WALKER, line) {
                    offenders.append(f"{f.relative_to(REPO_ROOT)}:{n}: {line.strip()}");
                }
            }
        }
    }
    assert offenders == [] , "underscore walkers are public routes, not hooks:\n"
        + "\n".join(offenders);
}

test "the guard's pattern catches the documented hook forms" {
    for line in [
        "walker _before_request {",
        "walker:pub _authenticate {",
        "walker :pub _authenticate {",
        "  walker _x {"
    ] {
        assert re.match(UNDERSCORE_WALKER, line) , line;
    }
    assert not re.match(UNDERSCORE_WALKER, "walker:pub ping {");
}
