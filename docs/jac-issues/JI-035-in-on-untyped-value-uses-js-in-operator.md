# JI-035: In client code, `x in y` on an untyped value compiles to JavaScript's `in`

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-02, P4.1d (the storefront's venue filter and genre filter matched nothing)
- **Status:** open (suspected from behaviour; worked around, see below). To confirm, read the compiled bundle under `.jac/client/`.

## Reproduction
```jac
movies = [m for m in s["movies"] if venue in (m.get("venues") or [])];   # never matches
```
`m` comes from a `dict[str, any]`, so `m.get("venues")` has no known type. With the list typed (`found: list[str] = ...; venue in found`), the same check works, as in every other membership test in the client code.

## Why it matters
JavaScript's `in` operator tests an object's keys. On an array the keys are its indexes, so `"CBD" in ["CBD", "Westgate"]` is false and `"0" in [...]` is true. The filters silently showed nothing. `jac check` is clean.

## Workaround (in place)
A typed helper, `listed(item: str, items: list[str] | None) -> bool` in `web/storefront/showtimes.jac`, used wherever the list comes from untyped data.

## Suggested fix
Compile `in` on a value of unknown type to a runtime helper that checks arrays and strings by value and objects by key, as Python's `in` does.
