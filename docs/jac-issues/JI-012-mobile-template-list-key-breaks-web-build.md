# JI-012: The `jac create --kind mobile` template fails `jac build mobile --platform web`

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P0.5 (first CI run); reproduced locally on an unmodified scaffold
- **Status:** open

## Behaviour
A fresh `jac create --app mobile --kind mobile` scaffold (unmodified `mobile/theme.jac`) fails to build for the browser:
```text
$ jac build mobile --platform web
✖ Error: Build failed: Vite build failed
mobile/compiled/mobile/theme.js (76:13): Unexpected token `.`. Expected ... , *, (, [, :, , ?, = or an identifier
```
The reported position (76:13) maps back to `mobile/theme.jac` line 76.

## Root cause (as far as I can tell)
The template's `StyleSheet.create({...})` dict uses **unquoted keys** (`screen: {...}`, `list: {...}`, `row: {...}`). In Jac, an unquoted dict key is an *expression*, which is why `jac check` reports ~70× W2001 "Name may be undefined" (JI-009). For most keys the client codegen happens to emit a valid JS object key. But `list` resolves to the Python builtin, which the codegen maps to its runtime helper, so the generated JS contains:
```js
let styles = StyleSheet.create({ ..., _jac.types.list: {gap: S.sm}, ... });
```
That's not a valid object-literal key. (The generated `theme.js` is also ~84 KB, because the `_jac` runtime helpers are inlined into it.)

## Workaround (in place)
Quote the dict keys in the scaffolded mobile files (`"list": {...}`). That's correct Jac, and it also removes the W2001 warnings.

## Possible improvement (suggestion)
Quote keys in the template, and/or have the client codegen reject or quote a builtin used as an object key.
