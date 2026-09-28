"""Guard (JI-025): endpoints must not rely on non-string parameter defaults.

On Jac 0.37.18 an omitted `def:pub`/`def:priv` parameter with a non-string default
arrives as a string: `x: int = 0` gives '0', and `flag: bool = False` gives 'False',
which is truthy. So endpoint parameters of type int, float or bool are declared without
a default and callers always send them.
"""

import re;
import from pathlib { Path }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     APP_SOURCES: list[str] = [
         "main.jac",
         "web",
         "core",
         "desktop",
         "mobile",
         "tests/apps"
     ],
     ENDPOINT: str = r"def\s*:\s*(pub|priv)\s+\w+\s*\((?P<params>[^)]*)\)",
     TYPED_DEFAULT: str = r"\w+\s*:\s*(int|float|bool)\b[^,=]*=";

def _offenders(source: str) -> list[str] {
    found: list[str] = [];
    for m in re.finditer(ENDPOINT, source, re.S) {
        # UI components (`-> JsxElement`) take props from JSX, not from HTTP.
        is_component = "JsxElement" in source[m.end():m.end() + 40];
        if not is_component and re.search(TYPED_DEFAULT, m.group("params")) {
            found.append(m.group(0).split("(")[0]);
        }
    }
    return found;
}

test "no endpoint gives an int, float or bool parameter a default" {
    offenders: list[str] = [];
    for src in APP_SOURCES {
        target = REPO_ROOT / src;
        files = [target]
            if target.is_file()
            else sorted(
                p
                for p in target.rglob("*.jac")
                if p.is_file() and ".jac" not in p.parts
            );
        for f in files {
            for name in _offenders(f.read_text()) {
                offenders.append(f"{f.relative_to(REPO_ROOT)}: {name}");
            }
        }
    }
    assert offenders == [] , "declare these parameters without defaults (JI-025):\n"
        + "\n".join(offenders);
}

test "the guard catches the risky forms and allows the safe ones" {
    assert _offenders("def:pub f(x: int = 0) -> str {") == ["def:pub f"];
    assert _offenders("def:priv g(a: str, on: bool = False) -> str {")
        == ["def:priv g"];
    assert _offenders("def:pub h(ratio: float = 1.5) -> str {") == ["def:pub h"];
    assert _offenders("def:pub ok(x: int, name: str = \"a\") -> str {") == [];
    assert _offenders("def helper(x: int = 0) -> int {") == [] , "plain helpers are not endpoints";
    assert _offenders("def:pub Button(disabled: bool = False) -> JsxElement {") == [] , "UI components are not endpoints";
}
