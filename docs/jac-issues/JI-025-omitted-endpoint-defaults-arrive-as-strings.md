# JI-025: An omitted endpoint parameter with a non-string default arrives as a string

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-28, P2.1 (`claim(..., ttl: int = 0)` failed with `'>' not supported between instances of 'str' and 'int'`)
- **Status:** open (guarded)

## Reproduction (real server, `jac run`, a `service` app)
```jac
def:pub dflt(x: int = 0, f: float = 1.5, b: bool = False, s: str = "a") -> str {
    return f"{type(x).__name__}:{x!r} {type(f).__name__}:{f!r} {type(b).__name__}:{b!r} {type(s).__name__}:{s!r}";
}
```
```
POST /function/dflt  {}                              -> str:'0' str:'1.5' str:'False' str:'a'
POST /function/dflt  {"x": 5, "f": 2.5, "b": true}   -> int:5 float:2.5 bool:True str:'a'
```
The in-process `JacTestClient` behaves the same way.

## Impact
- Arithmetic and comparisons on an omitted numeric parameter fail at runtime.
- **An omitted `bool = False` becomes the truthy string `'False'`**, so `if flag { ... }` takes the wrong branch silently.

## Workaround (in place)
Endpoint parameters of type int, float or bool never have defaults, and callers always send them. `tests/unit/endpoint_signature_tests.jac` fails on any `def:pub` / `def:priv` that breaks this rule. UI components returning `JsxElement` are exempt, because they get their props from JSX, not HTTP.

## Possible improvement (suggestion)
Apply the declared default as the typed Python value, rather than its source text, when an argument is omitted.
