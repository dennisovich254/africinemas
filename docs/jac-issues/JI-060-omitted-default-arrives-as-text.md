# JI-060: An endpoint parameter left out of the request arrives as the text of its default

- **Version:** Jac 0.38.0
- **Found:** 2026-10-27, building P15.2 (refund fee credits).
- **Status:** open; worked around by making such parameters required.

## Reproduction

```jac
def:pub probe(a: str, flag: bool = False, n: float = 0.0, s: str = "") -> str {
    return f"{flag!r}|{n!r}|{s!r}";
}
```

Calling `POST /function/probe` with `{"a": "x"}` returns `'False'|'0.0'|''`: the
omitted `flag` and `n` arrive as the **strings** `"False"` and `"0.0"`, not as `False`
and `0.0`. With every parameter sent, `{"a": "x", "flag": false, "n": 1.5, "s": "y"}`
returns `False|1.5|'y'`, as expected.

## Why it matters

`"False"` is a non-empty string, so it's **true**. Code such as
`if platform_failure { ... }` takes the wrong branch whenever a client leaves the
parameter out, silently, and `jac check` can't see it. In P15.2 a refund left without
`platform_failure` credited AfriCinemas' fee as if the Platform had failed. Numeric
defaults happen to survive `float("0.0")`, but arithmetic on them directly would fail.

## Workaround

Endpoint parameters with a `bool`, `int` or `float` default are made **required**, and
every caller sends them. A scan of `def:pub` and `def:protect` endpoints found only
the two added in P15.2 (`set_cinema_fee_terms`, and the test-only `t_refund`). Both
now take every parameter.

## Suggested fix

Apply the declared default (as its typed value) when a parameter is missing from the
request body, or validate and coerce the body against the signature's types.
