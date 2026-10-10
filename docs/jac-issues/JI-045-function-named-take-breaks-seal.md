# JI-045: A function named `take` passes jac check and tests, but fails the build's seal step

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-10, P8.6a (CI web and desktop builds)
- **Status:** open (renamed ours to `take_claim`)

## What we saw
`core/claims.jac` defined `def take(namespace: str, key: str) -> str | None`, and `core/oauth/state.jac` called `take(namespace, _hash(secret))`. `jac check`, `jac fmt --check` and every test passed. The CI builds (`jac build`, web and desktop) failed while sealing:

```
error[E1319]: Invalid take place: expected positional place arguments
  --> core/oauth/state.jac:71:12
   71 |     kept = take(namespace, _hash(secret));
help: take(place) requires an optional local or field and leaves None. ...
```

The seal compiler treats `take(...)` as the ownership built-in `take(place)` (with `swap` and `pop` as siblings), even though the module imports a function of that name.

## Workaround (in place)
Don't name a function `take` (or `swap`). Ours is `take_claim`.

## Suggestion upstream
Let an imported or locally defined name shadow the built-in, as in every other phase, or have `jac check` report the clash.
