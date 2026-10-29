# JI-062: Two `_` targets in a client comprehension compile to invalid JavaScript

- **Version:** Jac 0.38.0
- **Found:** 2026-10-29, adding tabs to the Verification page (feat/verification-tabs).
- **Status:** open; worked around by indexing the tuple.

## Reproduction

In a client (`.jac` under `web/`) component:

```jac
glob ROWS: list[tuple[str, str, str]] = [("legal_name", "Your name", "As on your ID")];

def:pub Keys -> JsxElement {
    keys: list[str] = [k for (k, _, _) in ROWS];
    return <p>{", ".join(keys)}</p>;
}
```

`jac check` passes. `jac build web` fails when Vite parses the generated module:

```
error during build:
web/compiled/web/backoffice/VerificationSection.js (444:28): Duplicate argument name "_"
```

The comprehension becomes an arrow function that destructures its argument, and both
`_` targets are emitted as the same parameter name, which JavaScript forbids in an
arrow function's parameters.

## Expected versus actual

Expected: as in Python, `_` can be repeated in a target list to ignore several values.
Actual: the client codegen emits it twice as a parameter name. `jac check` doesn't flag
it, and the server build is unaffected; the failure only shows in the client bundle's
Vite step, as a parse error pointing at the generated JavaScript, not the `.jac` source.
A single `_` in a target is fine.

## Workaround

Index the tuple (`[row[0] for row in ROWS]`), or give each ignored value its own name.

## Suggested fix

In client codegen, emit an ignored target as an elision (`([k, , ]) => …`) or give
each `_` a unique name (`_1`, `_2`). Failing that, have `jac check` warn on a repeated
`_` in client code, as the build's free-name audit does for JI-061.
