# JI-016: `obj` instances don't compare by value, but the docs say `__eq__` is generated

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P0.8a (a test comparing two identical `Theme` objects failed)
- **Status:** open (docs vs behaviour; identity equality may well be intentional)

## Docs
- `reference/language/syntax-cheatsheet.md` (line ~310): `obj` "auto-generates __init__, __eq__, __repr__, etc."
- The MCP pitfalls guide (`jaclang/cli/mcp/content/pitfalls.md`, line ~67, served as `jac://guide/pitfalls`, which agents are told to read first): "`obj` (dataclass-like, auto-generates `__init__`, `__eq__`, `__repr__`)".

## Behaviour (`jac run`)
```jac
obj Plain { has x: int; }
with entry {
    print(Plain(x=1) == Plain(x=1));                 # False
    print("__eq__" in type(Plain(x=1)).__dict__);    # False
    print(repr(Plain(x=1)));                         # Plain(x=1): __repr__ IS generated
}
```
The same holds with a `postinit` and for nested objs (`Outer(inner=Plain(x=1)) == Outer(inner=Plain(x=1))` → `False`).

## Impact
Code and tests written from the docs (e.g. `assert repair(x) == x`, or de-duplicating value objects) silently compare **identity**, not values.

## Workaround (in place)
Compare explicit value views: `Theme.as_dict()` / `ThemeTokens.as_dict()` in `core/theming/tokens.jac`.

## Possible improvement (suggestion)
Either generate `__eq__` for `obj` as documented, or correct the cheatsheet and pitfalls guide to say `obj` equality is identity-based.
