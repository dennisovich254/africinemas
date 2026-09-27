# JI-018: `jac check` rejects every key of a Python-defined TypedDict (E1043)

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P0.8b (Playwright's `Locator.bounding_box()` returns `FloatRect | None`)
- **Status:** open (type-checker bug; it is an **error**, so `jac check` fails)

## Repro
`pyrect.py`:
```python
from typing import TypedDict
class FloatRect(TypedDict):
    x: float
    y: float
    width: float
    height: float
class Two(TypedDict):
    alpha: int
    beta: int
```
`use.jac`:
```jac
import from pyrect { FloatRect, Two }
def kh(r: FloatRect) -> float { return r["height"]; }   # E1043: TypedDict "FloatRect" has no key "height"
def ka(t: Two) -> int { return t["alpha"]; }            # E1043: TypedDict "Two" has no key "alpha"
```
**Every** key is rejected (`x`, `y`, `width`, `height`, `alpha`, `beta`), and each access is then typed
`<Unknown>` (E1002 on return). Adding two values was even inferred as `str`. A TypedDict **defined in Jac**
(`class Rect(TypedDict) { has height: float; }`) checks fine, as does Playwright's actual class at runtime:
`typing.get_type_hints(FloatRect)` gives `['x', 'y', 'width', 'height']`.

## Impact
Any Python library API that returns a TypedDict (Playwright, many SDKs) can't be indexed in Jac
without a checker error, which fails CI.

## Workaround (in place)
Avoid indexing the returned TypedDict: `e2e/theme_tests.jac` reads sizes in the browser via
`locator.evaluate("e => e.getBoundingClientRect().height")`.

## Possible improvement (suggestion)
Read TypedDict fields from Python class annotations the same way as for Jac-defined TypedDicts.
