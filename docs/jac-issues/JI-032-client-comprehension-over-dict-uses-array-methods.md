# JI-032: In client code, a comprehension over a dict compiles to array methods and crashes

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-29, P3.3 (the seat designer crashed on its first render; every designer e2e test timed out)
- **Status:** open (worked around with plain `for` loops)

## What we saw
Source (`web/backoffice/SeatDesigner.jac`, `cells: dict[str, str]`):
```jac
parts = sorted([f"{k}={cells[k]}" for k in cells]);
```
Compiled (`.jac/client/web/compiled/web/backoffice/SeatDesigner.js`):
```js
let parts = _jac.builtin.sorted(cells.map(k => `${k}=${cells[k]}`));
```
`cells` is a plain JS object, which has no `.map`, so this throws `TypeError: cells.map is not a function`. The same happened for a filtered list comprehension (`cells.filter(...)`) and a dict comprehension (`Object.fromEntries(prev.filter(...).map(...))`).

In the same build these compiled correctly:
- a plain `for key in cells { ... }` loop, as `for (const key of Object.keys(cells))`;
- `len(cells)`, as `Object.keys(cells).length`;
- `key in cells`, as `_jac.poly.contains(...)` or JS `in`.

The parameter was annotated `dict[str, str]`, and `jac check` passed.

## Why it matters
The component crashes on render with nothing at compile time; only a browser run shows it. Comprehensions are the idiomatic way to write these, so they're easy to reach for.

## Workaround (in place)
In client code, iterate dicts with plain `for` loops (`seat_grid.jac`: `sellable`, `seat_types_in`, `without`; `SeatDesigner.jac`: `snapshot`).
