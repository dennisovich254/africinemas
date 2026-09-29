# JI-028: In client code, a one-statement block lambda compiles to an arrow that returns the statement's value

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-28, P2.7b (the cinema picker crashed with "re is not a function" when the user left it)
- **Status:** open (worked around; see below)

## Reproduction
```jac
def:pub CinemaPicker -> JsxElement {
    async def load { ... }
    useEffect(lambda { load(); }, []);
    ...
}
```
The compiled bundle (`.jac/client/web/compiled/web/backoffice/CinemaPicker.js`) has:
```js
useEffect(() => load(), []);
```
A lambda with two or more statements compiles to a block arrow with no `return` (`() => { a(); b(); }`), as expected.

## Why it matters
In Jac (as in Python) a block body with no `return` returns `None`. In the compiled JS, the single-statement form returns the call's value. For `useEffect` that value becomes the effect's cleanup: `load()` returns a promise, and React calls it when the component unmounts. The page then crashes with `TypeError: ... is not a function` on client-side navigation. A direct page load doesn't show it, and `jac check` is clean.

## Workaround (in place)
Pass a named nested function instead of a one-statement lambda (`def start_loading { load(); }` then `useEffect(start_loading, [])`), in `web/backoffice/CinemaPicker.jac`.
