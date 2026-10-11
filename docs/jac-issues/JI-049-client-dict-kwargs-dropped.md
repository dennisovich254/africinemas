# JI-049: In client code, `dict(row, **{key: value})` compiles to `dict(row)`: the `**` part is dropped

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-11, P12.1 (e2e in CI; `jac check` and server tests pass)
- **Status:** open (we copy, then assign: `with_field` in `web/backoffice/snack_view.jac`)

## What we saw
The product editor updated one field of a variant row with:

```jac
[dict(r, **{key: value}) if n == i else r for (n, r) in enumerate(rows)]
```

Typed SKUs and prices never reached the form's state, so a saved product had none, and publishing listed every variant's SKU and price as missing. The compiled client code (`.jac/client/web/compiled/.../SnackProductEditor.js`) shows why:

```js
put("rows", _jac.builtin.enumerate(rows).map(([n, r]) => ((n === i) ? _jac.builtin.dict(r) : r)));
```

The `**{key: value}` argument is gone, with no error or warning. The same code works on the server (Python), so only a browser test caught it.

## Workaround (in place)
Copy, then assign by subscript, which compiles correctly:

```jac
def:pub with_field(row: dict[str, any], key: str, value: any) -> dict[str, any] {
    copy: dict[str, any] = dict(row);
    copy[key] = value;
    return copy;
}
```

## Suggestion upstream
Compile `dict(mapping, **kwargs)` to `{...mapping, ...kwargs}` in client code, or have `jac check` report `**` in a client `dict(...)` call as unsupported.
