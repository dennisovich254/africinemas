# JI-055: In client code, a dict literal's variable key compiles to its name: `{key: value}` sets "key"

- **Version:** jaclang 0.38.0
- **Found:** 2026-10-24, P14.3a (e2e in CI; `jac check` and server tests pass)
- **Status:** open (we copy, then assign: `with_field` in `web/backoffice/snack_view.jac`)

## What we saw
The Website information form updated one field of its state with:

```jac
def put(field: str, value: any) {
    set_info({** info, field: value});
}
```

The compiled JavaScript (`.jac/client/.../SiteInfoSection.js`) is:

```js
function put(field, value) {
    set_info({...info, field: value});
}
```

In a JavaScript object literal, `field: value` is the key `"field"`. The computed form `[field]: value` would use the variable. So typing into any field set `info.field` and left the real field empty: the form saved nothing and showed no problems. The same happened without a spread: `set_errors({target: message})` in the movie editor set `errors.target`, so a refusal meant for one field (an invalid title, say) never reached that field.

On the server, the same code uses the variable's value, as in Python.

## Expected
A dict literal's key is an expression: a variable key compiles to a computed key (`{[field]: value}`), and a string literal stays a plain key.

## Workaround (in place)
Copy, then assign. `copy[key] = value` compiles to an indexed assignment, which uses the variable:

```jac
def:pub with_field(row: dict[str, any], key: str, value: any) -> dict[str, any] {
    copy: dict[str, any] = dict(row);
    copy[key] = value;
    return copy;
}
```

Used in `web/backoffice/SiteInfoSection.jac`; `web/backoffice/MovieEditor.jac` builds its errors dict the same way.

Related: [JI-049](JI-049-client-dict-kwargs-dropped.md) (another client dict form that compiles to something else, silently).
